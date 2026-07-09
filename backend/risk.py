"""
Risk controls for TradeForge auto-trading.

Hard guards:
  - kill switch / pause
  - max trades per day
  - max position size ($)
  - daily loss limit
  - min pattern confidence
  - market hours (optional)
  - allowed ticker whitelist
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Any, Optional
from zoneinfo import ZoneInfo

import store

DEFAULT_CONFIG = {
    "trading_mode": "paper",  # paper | approval | live (live reserved)
    "min_confidence": 0.70,
    "max_trades_per_day": 5,
    "max_position_dollars": 500.0,
    "daily_loss_limit": 200.0,
    "is_paused": False,
    "kill_switch": False,
    "allowed_tickers": [],
    "trade_schedule": "market_hours_only",  # always | market_hours_only
    "auto_exit": True,
    # confirmed = price past breakout (+ volume when needed)
    # setup     = high-confidence pattern even if breakout not fully triggered (better for paper demos)
    "entry_style": "setup",
    "strategies": {
        "rsi_bounce": True,
        "bull_flag": True,
        "ascending_triangle": True,
        "cup_handle": True,
        "head_shoulders": True,
        "ma_cross": True,
        "volume_breakout": True,
    },
}


def get_config(device_id: str) -> dict[str, Any]:
    configs = store.load("device_configs")
    if device_id not in configs:
        cfg = {**DEFAULT_CONFIG, "device_id": device_id}
        configs[device_id] = cfg
        store.save("device_configs", configs)
        return cfg
    # merge defaults for new keys
    merged = {**DEFAULT_CONFIG, **configs[device_id]}
    if "strategies" in DEFAULT_CONFIG:
        merged["strategies"] = {**DEFAULT_CONFIG["strategies"], **merged.get("strategies", {})}
    return merged


def set_config(device_id: str, updates: dict[str, Any]) -> dict[str, Any]:
    configs = store.load("device_configs")
    current = get_config(device_id)
    # only allow known keys
    allowed = set(DEFAULT_CONFIG.keys()) | {"fcm_token", "device_id"}
    for k, v in updates.items():
        if k in allowed or k == "fcm_token":
            if k == "strategies" and isinstance(v, dict):
                current["strategies"] = {**current.get("strategies", {}), **v}
            else:
                current[k] = v
    current["device_id"] = device_id
    configs[device_id] = current
    store.save("device_configs", configs)
    return current


def is_market_hours() -> bool:
    et = ZoneInfo("America/New_York")
    now = datetime.now(et)
    if now.weekday() >= 5:
        return False
    open_ = now.replace(hour=9, minute=30, second=0, microsecond=0)
    close_ = now.replace(hour=16, minute=0, second=0, microsecond=0)
    return open_ <= now <= close_


def _daily_state(device_id: str) -> dict:
    states = store.load("daily_state")
    today = str(date.today())
    state = states.get(device_id, {})
    if state.get("date") != today:
        state = {"date": today, "trades": 0, "realized_pnl": 0.0}
        states[device_id] = state
        store.save("daily_state", states)
    return state


def record_trade(device_id: str, realized_pnl: float = 0.0) -> None:
    states = store.load("daily_state")
    state = _daily_state(device_id)
    state["trades"] = int(state.get("trades", 0)) + 1
    state["realized_pnl"] = float(state.get("realized_pnl", 0)) + float(realized_pnl)
    states[device_id] = state
    store.save("daily_state", states)


def can_trade(
    device_id: str,
    ticker: str,
    confidence: float,
    dollar_amount: float,
    portfolio_equity: Optional[float] = None,
) -> tuple[bool, str]:
    cfg = get_config(device_id)

    if cfg.get("kill_switch"):
        return False, "Kill switch is ON"
    if cfg.get("is_paused"):
        return False, "Trading is paused"
    if cfg.get("trade_schedule") == "market_hours_only" and not is_market_hours():
        return False, "Outside market hours"
    if confidence < float(cfg.get("min_confidence", 0.75)):
        return False, f"Confidence {confidence:.0%} below minimum"

    allowed = cfg.get("allowed_tickers") or []
    if allowed and ticker.upper() not in [t.upper() for t in allowed]:
        return False, f"{ticker} not in allowed tickers"

    max_pos = float(cfg.get("max_position_dollars", 500))
    if dollar_amount > max_pos + 0.01:
        return False, f"Order ${dollar_amount:.0f} exceeds max position ${max_pos:.0f}"

    state = _daily_state(device_id)
    max_trades = int(cfg.get("max_trades_per_day", 5))
    if int(state.get("trades", 0)) >= max_trades:
        return False, "Daily trade limit reached"

    daily_loss_limit = float(cfg.get("daily_loss_limit", 200))
    if float(state.get("realized_pnl", 0)) <= -abs(daily_loss_limit):
        return False, "Daily loss limit reached"

    return True, "ok"


def risk_status(device_id: str) -> dict[str, Any]:
    cfg = get_config(device_id)
    state = _daily_state(device_id)
    return {
        "config": cfg,
        "daily": state,
        "market_open": is_market_hours(),
        "can_trade_now": (
            not cfg.get("kill_switch")
            and not cfg.get("is_paused")
            and (cfg.get("trade_schedule") != "market_hours_only" or is_market_hours())
            and int(state.get("trades", 0)) < int(cfg.get("max_trades_per_day", 5))
            and float(state.get("realized_pnl", 0)) > -abs(float(cfg.get("daily_loss_limit", 200)))
        ),
    }
