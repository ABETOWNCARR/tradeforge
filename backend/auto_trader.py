"""
Autonomous paper trading loop.

Every cycle:
  1. Load registered devices
  2. Scan universe for patterns
  3. Apply risk gates
  4. Enter paper positions (or queue for approval)
  5. Manage exits (stops / targets)
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

import patterns
import paper_broker
import risk
import store

log = logging.getLogger("tradeforge.auto_trader")

# Map pattern names to strategy toggles
PATTERN_STRATEGY_MAP = {
    "RSI Oversold Bounce": "rsi_bounce",
    "Bull Flag": "bull_flag",
    "Ascending Triangle": "ascending_triangle",
    "Cup & Handle": "cup_handle",
    "Head & Shoulders": "head_shoulders",
    "Golden Cross (20/50)": "ma_cross",
    "Death Cross (20/50)": "ma_cross",
    "Volume Breakout": "volume_breakout",
}


def register_device(device_id: str, **kwargs) -> dict:
    configs = store.load("device_configs")
    cfg = risk.get_config(device_id)
    for k, v in kwargs.items():
        if v is not None:
            cfg[k] = v
    cfg["registered_at"] = datetime.now(timezone.utc).isoformat()
    cfg["device_id"] = device_id
    configs[device_id] = cfg
    store.save("device_configs", configs)
    # ensure paper portfolio exists
    paper_broker.get_portfolio(device_id)
    return cfg


def list_devices() -> list[str]:
    return list(store.load("device_configs").keys())


def _strategy_enabled(cfg: dict, pattern_name: str) -> bool:
    key = PATTERN_STRATEGY_MAP.get(pattern_name)
    if not key:
        return True
    return bool(cfg.get("strategies", {}).get(key, True))


def _pending_approvals() -> dict:
    return store.load("pending_approvals")


def queue_approval(device_id: str, signal: dict) -> dict:
    pending = _pending_approvals()
    device_list = pending.get(device_id, [])
    # de-dupe same ticker same day
    ticker = signal["ticker"]
    if any(p.get("ticker") == ticker and p.get("status") == "pending" for p in device_list):
        return {"queued": False, "reason": "already_pending"}
    signal["id"] = f"{device_id}-{ticker}-{int(datetime.now(timezone.utc).timestamp())}"
    signal["status"] = "pending"
    signal["created_at"] = datetime.now(timezone.utc).isoformat()
    device_list.insert(0, signal)
    pending[device_id] = device_list[:50]
    store.save("pending_approvals", pending)
    return {"queued": True, "signal": signal}


def get_approvals(device_id: str) -> list[dict]:
    return _pending_approvals().get(device_id, [])


def resolve_approval(device_id: str, approval_id: str, approve: bool) -> dict:
    pending = _pending_approvals()
    rows = pending.get(device_id, [])
    target = None
    for row in rows:
        if row.get("id") == approval_id:
            target = row
            break
    if not target:
        return {"success": False, "error": "Approval not found"}
    if target.get("status") != "pending":
        return {"success": False, "error": "Already resolved"}

    if not approve:
        target["status"] = "rejected"
        store.save("pending_approvals", pending)
        return {"success": True, "status": "rejected"}

    # execute paper buy
    result = paper_broker.buy(
        device_id,
        target["ticker"],
        dollar_amount=float(target.get("dollar_amount", 100)),
        reason=target.get("reason", "Approved signal"),
        pattern=target.get("pattern", ""),
        confidence=float(target.get("confidence", 0)),
        stop_level=target.get("stop_level"),
        target_level=target.get("target_level"),
        mode="paper_approved",
    )
    target["status"] = "approved" if result.get("success") else "failed"
    target["result"] = result
    store.save("pending_approvals", pending)
    if result.get("success"):
        risk.record_trade(device_id, 0.0)
    return {"success": result.get("success", False), "status": target["status"], "result": result}


def run_cycle_for_device(device_id: str, market_data: dict) -> dict[str, Any]:
    cfg = risk.get_config(device_id)
    summary: dict[str, Any] = {
        "device_id": device_id,
        "entries": [],
        "exits": [],
        "skipped": [],
        "queued": [],
    }

    if cfg.get("kill_switch") or cfg.get("is_paused"):
        summary["skipped"].append("paused_or_kill_switch")
        return summary

    if cfg.get("trade_schedule") == "market_hours_only" and not risk.is_market_hours():
        summary["skipped"].append("outside_market_hours")
        # still manage exits if auto_exit
        if cfg.get("auto_exit", True):
            summary["exits"] = paper_broker.check_exits(device_id)
        return summary

    # exits first
    if cfg.get("auto_exit", True):
        summary["exits"] = paper_broker.check_exits(device_id)
        for ex in summary["exits"]:
            risk.record_trade(device_id, float(ex.get("realized_pnl", 0)))

    mode = cfg.get("trading_mode", "paper")
    min_conf = float(cfg.get("min_confidence", 0.75))
    max_pos = float(cfg.get("max_position_dollars", 500))
    portfolio = paper_broker.mark_to_market(device_id)
    open_tickers = set(portfolio.get("positions", {}).keys())

    for ticker, df in market_data.items():
        hits = patterns.detect_patterns(df)
        if not hits:
            continue
        best = hits[0]
        if best.get("signal") != "bullish":
            continue  # paper auto only long for safety in MVP
        if best.get("confidence", 0) < min_conf:
            continue
        if not _strategy_enabled(cfg, best.get("pattern", "")):
            continue
        if not patterns.confirm_signal(df, best):
            continue
        if ticker in open_tickers:
            summary["skipped"].append(f"{ticker}: already_open")
            continue

        ok, reason = risk.can_trade(device_id, ticker, float(best["confidence"]), max_pos)
        if not ok:
            summary["skipped"].append(f"{ticker}: {reason}")
            continue

        signal = {
            "ticker": ticker,
            "pattern": best.get("pattern"),
            "signal": best.get("signal"),
            "confidence": best.get("confidence"),
            "price": best.get("price"),
            "breakout_level": best.get("breakout_level"),
            "stop_level": best.get("stop_level"),
            "target_level": best.get("target_level"),
            "dollar_amount": max_pos,
            "reason": f"{best.get('pattern')} ({best.get('confidence'):.0%})",
        }

        if mode == "approval":
            q = queue_approval(device_id, signal)
            if q.get("queued"):
                summary["queued"].append(signal)
            continue

        # paper (and reserved live path uses paper until brokerage wired)
        result = paper_broker.buy(
            device_id,
            ticker,
            dollar_amount=max_pos,
            reason=signal["reason"],
            pattern=signal["pattern"],
            confidence=float(signal["confidence"]),
            stop_level=signal.get("stop_level"),
            target_level=signal.get("target_level"),
            mode="paper_auto",
        )
        if result.get("success"):
            risk.record_trade(device_id, 0.0)
            summary["entries"].append(result["trade"])
            open_tickers.add(ticker)
        else:
            summary["skipped"].append(f"{ticker}: {result.get('error')}")

    return summary


def run_all_devices(universe: list[str]) -> dict[str, Any]:
    devices = list_devices()
    if not devices:
        return {"devices": 0, "results": []}
    log.info("Auto cycle for %d devices, universe=%d", len(devices), len(universe))
    market_data = patterns.fetch_universe_data(universe)
    results = []
    for device_id in devices:
        try:
            results.append(run_cycle_for_device(device_id, market_data))
        except Exception as e:
            log.exception("Device %s failed: %s", device_id, e)
            results.append({"device_id": device_id, "error": str(e)})
    return {
        "devices": len(devices),
        "tickers_scanned": len(market_data),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "results": results,
    }
