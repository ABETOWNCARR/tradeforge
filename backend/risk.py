"""
Risk controls for TradeForge auto-trading.

Hard guards:
  - kill switch / pause
  - max entries per day (exits do NOT count toward this)
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
    "trading_mode": "paper",  # paper = auto execute | approval = queue first
    "broker_mode": "sim",  # sim | alpaca_paper | alpaca_live
    "live_enabled": False,
    "min_confidence": 0.70,
    "max_trades_per_day": 15,  # entries only
    "max_position_dollars": 500.0,  # hard cap per entry
    "position_size_pct": 5.0,  # % of equity per new entry (capped by max_position_dollars)
    "max_open_positions": 8,
    "daily_loss_limit": 200.0,
    "is_paused": False,
    "kill_switch": False,
    "allowed_tickers": [],
    "trade_schedule": "market_hours_only",
    "auto_exit": True,
    "entry_style": "setup",  # setup | confirmed
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
    merged = {**DEFAULT_CONFIG, **configs[device_id]}
    if "strategies" in DEFAULT_CONFIG:
        merged["strategies"] = {**DEFAULT_CONFIG["strategies"], **merged.get("strategies", {})}
    return merged


def set_config(device_id: str, updates: dict[str, Any]) -> dict[str, Any]:
    configs = store.load("device_configs")
    current = get_config(device_id)
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
        state = {
            "date": today,
            "trades": 0,  # legacy: same as entries
            "entries": 0,
            "exits": 0,
            "realized_pnl": 0.0,
        }
        states[device_id] = state
        store.save("daily_state", states)
    # migrate old records that only had "trades"
    if "entries" not in state:
        state["entries"] = int(state.get("trades", 0))
    if "exits" not in state:
        state["exits"] = 0
    return state


def record_trade(
    device_id: str,
    realized_pnl: float = 0.0,
    *,
    count_toward_limit: bool = True,
    is_exit: bool = False,
) -> None:
    """Record a fill.

    count_toward_limit=True  → counts as a daily *entry* (blocks further buys when cap hit)
    is_exit=True             → exit fill; never counts toward entry limit
    """
    states = store.load("daily_state")
    state = _daily_state(device_id)
    if is_exit or not count_toward_limit:
        state["exits"] = int(state.get("exits", 0)) + 1
    else:
        state["entries"] = int(state.get("entries", 0)) + 1
        state["trades"] = int(state.get("entries", 0))  # keep legacy field in sync
    state["realized_pnl"] = float(state.get("realized_pnl", 0)) + float(realized_pnl)
    states[device_id] = state
    store.save("daily_state", states)


def reset_daily(device_id: str) -> dict:
    states = store.load("daily_state")
    state = {
        "date": str(date.today()),
        "trades": 0,
        "entries": 0,
        "exits": 0,
        "realized_pnl": 0.0,
    }
    states[device_id] = state
    store.save("daily_state", states)
    return state


def _entry_count(state: dict) -> int:
    return int(state.get("entries", state.get("trades", 0)))


def position_size_dollars(device_id: str, portfolio: Optional[dict] = None) -> float:
    """Dollar size for next entry: min(max_position_dollars, equity * pct/100)."""
    cfg = get_config(device_id)
    cap = float(cfg.get("max_position_dollars", 500))
    pct = float(cfg.get("position_size_pct", 5.0))
    equity = None
    if portfolio:
        equity = portfolio.get("equity")
    if equity is None:
        equity = 10_000.0
    sized = float(equity) * max(0.0, pct) / 100.0
    # never size below $25 for practical fractionals
    return round(max(25.0, min(cap, sized)), 2)


def can_trade(
    device_id: str,
    ticker: str,
    confidence: float,
    dollar_amount: float,
    portfolio_equity: Optional[float] = None,
    open_positions: Optional[int] = None,
) -> tuple[bool, str]:
    cfg = get_config(device_id)

    if cfg.get("kill_switch"):
        return False, "Kill switch is ON"
    if cfg.get("is_paused"):
        return False, "Trading is paused"
    if cfg.get("broker_mode") == "alpaca_live" and not cfg.get("live_enabled"):
        return False, "Live broker locked"
    if cfg.get("trade_schedule") == "market_hours_only" and not is_market_hours():
        return False, "Outside market hours"
    if confidence < float(cfg.get("min_confidence", 0.70)):
        return False, f"Confidence {confidence:.0%} below minimum"

    allowed = cfg.get("allowed_tickers") or []
    if allowed and ticker.upper() not in [t.upper() for t in allowed]:
        return False, f"{ticker} not in allowed tickers"

    max_pos = float(cfg.get("max_position_dollars", 500))
    if dollar_amount > max_pos + 0.01:
        return False, f"Order ${dollar_amount:.0f} exceeds max position ${max_pos:.0f}"

    max_open = int(cfg.get("max_open_positions", 8))
    if open_positions is not None and open_positions >= max_open:
        return False, f"Max open positions ({max_open})"

    state = _daily_state(device_id)
    max_trades = int(cfg.get("max_trades_per_day", 15))
    entries = _entry_count(state)
    if entries >= max_trades:
        return False, f"Daily entry limit reached ({entries}/{max_trades})"

    daily_loss_limit = float(cfg.get("daily_loss_limit", 200))
    if float(state.get("realized_pnl", 0)) <= -abs(daily_loss_limit):
        return False, "Daily loss limit reached"

    return True, "ok"


def blocked_reason(device_id: str) -> Optional[str]:
    """Human-readable reason the bot won't open new entries right now."""
    cfg = get_config(device_id)
    state = _daily_state(device_id)
    if cfg.get("kill_switch"):
        return "Kill switch is ON"
    if cfg.get("is_paused"):
        return "Trading is paused"
    if cfg.get("trade_schedule") == "market_hours_only" and not is_market_hours():
        return "Outside NYSE market hours"
    max_trades = int(cfg.get("max_trades_per_day", 15))
    entries = _entry_count(state)
    if entries >= max_trades:
        return f"Daily entry limit hit ({entries}/{max_trades})"
    if float(state.get("realized_pnl", 0)) <= -abs(float(cfg.get("daily_loss_limit", 200))):
        return "Daily loss limit reached"
    return None


def risk_status(device_id: str) -> dict[str, Any]:
    cfg = get_config(device_id)
    state = _daily_state(device_id)
    entries = _entry_count(state)
    max_trades = int(cfg.get("max_trades_per_day", 15))
    reason = blocked_reason(device_id)
    return {
        "config": cfg,
        "daily": {
            **state,
            "entries": entries,
            "trades": entries,  # backward compatible
            "max_entries": max_trades,
            "entries_remaining": max(0, max_trades - entries),
        },
        "market_open": is_market_hours(),
        "can_trade_now": reason is None,
        "blocked_reason": reason,
    }
