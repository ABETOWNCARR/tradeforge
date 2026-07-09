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
    """Register or heartbeat a device.

    Existing configs are preserved. Only explicitly provided non-default
    heartbeats (e.g. fcm_token) update an already-registered device so the
    app opening doesn't reset risk limits every launch.
    """
    configs = store.load("device_configs")
    existing = configs.get(device_id)
    if existing:
        cfg = risk.get_config(device_id)
        # Only merge keys the caller explicitly wants to refresh
        for k in ("fcm_token",):
            if kwargs.get(k) is not None and kwargs.get(k) != "":
                cfg[k] = kwargs[k]
        cfg["last_seen_at"] = datetime.now(timezone.utc).isoformat()
        cfg["device_id"] = device_id
        configs[device_id] = cfg
        store.save("device_configs", configs)
        paper_broker.get_portfolio(device_id)
        return cfg

    cfg = risk.get_config(device_id)
    for k, v in kwargs.items():
        if v is not None:
            cfg[k] = v
    cfg["registered_at"] = datetime.now(timezone.utc).isoformat()
    cfg["last_seen_at"] = cfg["registered_at"]
    cfg["device_id"] = device_id
    configs[device_id] = cfg
    store.save("device_configs", configs)
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


def _save_last_cycle(device_id: str, summary: dict) -> None:
    data = store.load("last_cycles")
    data[device_id] = {
        **summary,
        "finished_at": datetime.now(timezone.utc).isoformat(),
    }
    store.save("last_cycles", data)


def get_last_cycle(device_id: str) -> dict:
    return store.load("last_cycles").get(device_id, {})


def _candidate_signals_from_market(
    market_data: dict,
    cfg: dict,
    *,
    min_conf: float,
    strict: bool,
    stats: dict,
) -> list[dict]:
    """Build entry candidates from live OHLC frames."""
    candidates = []
    for ticker, df in market_data.items():
        hits = patterns.detect_patterns(df)
        if not hits:
            stats["no_pattern"] += 1
            continue
        best = hits[0]
        if best.get("signal") != "bullish":
            stats["not_bullish"] += 1
            continue
        if best.get("confidence", 0) < min_conf:
            stats["low_confidence"] += 1
            continue
        if not _strategy_enabled(cfg, best.get("pattern", "")):
            stats["strategy_off"] += 1
            continue
        if not patterns.confirm_signal(df, best, strict=strict):
            stats["not_confirmed"] += 1
            continue
        candidates.append({
            "ticker": ticker,
            "pattern": best.get("pattern"),
            "signal": best.get("signal"),
            "confidence": best.get("confidence"),
            "price": best.get("price"),
            "breakout_level": best.get("breakout_level"),
            "stop_level": best.get("stop_level"),
            "target_level": best.get("target_level"),
            "source": "live",
        })
    return candidates


def _candidate_signals_from_cache(cfg: dict, *, min_conf: float, stats: dict) -> list[dict]:
    """Fallback: use last successful /scan high-confidence alerts."""
    cached = store.load("last_scan_signals")
    alerts = cached.get("alerts") or []
    if not alerts:
        stats["cache_empty"] = 1
        return []
    candidates = []
    for a in alerts:
        if a.get("signal") != "bullish":
            stats["not_bullish"] += 1
            continue
        if float(a.get("confidence") or 0) < min_conf:
            stats["low_confidence"] += 1
            continue
        if not _strategy_enabled(cfg, a.get("pattern", "")):
            stats["strategy_off"] += 1
            continue
        # setup mode: cached high-confidence alerts are already scan-qualified
        candidates.append({
            "ticker": a.get("ticker"),
            "pattern": a.get("pattern"),
            "signal": a.get("signal"),
            "confidence": a.get("confidence"),
            "price": a.get("price"),
            "breakout_level": a.get("breakout_level"),
            "stop_level": a.get("stop_level"),
            "target_level": a.get("target_level"),
            "source": "scan_cache",
        })
    return candidates


def run_cycle_for_device(device_id: str, market_data: dict) -> dict[str, Any]:
    cfg = risk.get_config(device_id)
    summary: dict[str, Any] = {
        "device_id": device_id,
        "entries": [],
        "exits": [],
        "skipped": [],
        "queued": [],
        "candidates": 0,
        "entry_style": cfg.get("entry_style", "setup"),
        "trading_mode": cfg.get("trading_mode", "paper"),
        "tickers_considered": len(market_data),
    }

    if cfg.get("kill_switch") or cfg.get("is_paused"):
        summary["skipped"].append("paused_or_kill_switch")
        summary["message"] = "Bot is paused or kill switch is on"
        _save_last_cycle(device_id, summary)
        return summary

    if cfg.get("trade_schedule") == "market_hours_only" and not risk.is_market_hours():
        summary["skipped"].append("outside_market_hours")
        summary["message"] = "Outside NYSE market hours — entries skipped"
        if cfg.get("auto_exit", True):
            summary["exits"] = paper_broker.check_exits(device_id)
        _save_last_cycle(device_id, summary)
        return summary

    if cfg.get("auto_exit", True):
        summary["exits"] = paper_broker.check_exits(device_id)
        for ex in summary["exits"]:
            # Exits must NOT burn the daily entry quota
            risk.record_trade(
                device_id,
                float(ex.get("realized_pnl", 0) or 0),
                count_toward_limit=False,
                is_exit=True,
            )

    mode = cfg.get("trading_mode", "paper")
    min_conf = float(cfg.get("min_confidence", 0.70))
    max_pos = float(cfg.get("max_position_dollars", 500))
    entry_style = (cfg.get("entry_style") or "setup").lower()
    strict = entry_style == "confirmed"
    portfolio = paper_broker.mark_to_market(device_id)
    open_tickers = set(portfolio.get("positions", {}).keys())

    stats = {
        "no_pattern": 0,
        "not_bullish": 0,
        "low_confidence": 0,
        "strategy_off": 0,
        "not_confirmed": 0,
        "already_open": 0,
        "risk_blocked": 0,
        "buy_failed": 0,
        "cache_empty": 0,
        "used_scan_cache": 0,
    }

    candidates = _candidate_signals_from_market(
        market_data, cfg, min_conf=min_conf, strict=strict, stats=stats
    )
    if not candidates:
        # Live OHLC missing/empty or too strict — use last scan alerts (setup mode only)
        if not strict:
            cached = _candidate_signals_from_cache(cfg, min_conf=min_conf, stats=stats)
            if cached:
                stats["used_scan_cache"] = 1
                candidates = cached
                summary["data_source"] = "scan_cache"
        if not candidates and len(market_data) == 0:
            summary["filter_stats"] = stats
            summary["message"] = (
                "No market data right now (Yahoo rate limit) and no cached scan signals. "
                "Open Scanner → Scan once, then tap Run bot again."
            )
            _save_last_cycle(device_id, summary)
            return summary

    summary["data_source"] = summary.get("data_source") or "live"
    # Rank by confidence, take best opportunities up to remaining daily capacity
    candidates.sort(key=lambda x: float(x.get("confidence") or 0), reverse=True)

    for signal in candidates:
        ticker = (signal.get("ticker") or "").upper()
        if not ticker:
            continue
        summary["candidates"] += 1

        if ticker in open_tickers:
            stats["already_open"] += 1
            summary["skipped"].append(f"{ticker}: already_open")
            continue

        ok, reason = risk.can_trade(device_id, ticker, float(signal["confidence"]), max_pos)
        if not ok:
            stats["risk_blocked"] += 1
            summary["skipped"].append(f"{ticker}: {reason}")
            continue

        entry_style_tag = entry_style
        signal_body = {
            **signal,
            "dollar_amount": max_pos,
            "reason": (
                f"{signal.get('pattern')} ({float(signal.get('confidence') or 0):.0%}) "
                f"[{entry_style_tag}/{signal.get('source', 'live')}]"
            ),
        }

        if mode == "approval":
            q = queue_approval(device_id, signal_body)
            if q.get("queued"):
                summary["queued"].append(signal_body)
            continue

        result = paper_broker.buy(
            device_id,
            ticker,
            dollar_amount=max_pos,
            reason=signal_body["reason"],
            pattern=signal_body.get("pattern") or "",
            confidence=float(signal_body.get("confidence") or 0),
            stop_level=signal_body.get("stop_level"),
            target_level=signal_body.get("target_level"),
            mode="paper_auto",
        )
        if result.get("success"):
            risk.record_trade(device_id, 0.0, count_toward_limit=True, is_exit=False)
            summary["entries"].append(result["trade"])
            open_tickers.add(ticker)
        else:
            stats["buy_failed"] += 1
            summary["skipped"].append(f"{ticker}: {result.get('error')}")

    summary["filter_stats"] = stats
    n_entries = len(summary["entries"])
    n_queued = len(summary["queued"])
    if n_entries:
        summary["message"] = f"Opened {n_entries} paper trade(s)"
    elif n_queued:
        summary["message"] = f"Queued {n_queued} signal(s) for approval"
    elif summary["candidates"] == 0:
        summary["message"] = (
            f"No entry candidates (filtered: "
            f"{stats['not_confirmed']} not near breakout, "
            f"{stats['low_confidence']} low confidence, "
            f"{stats['not_bullish']} non-bullish). "
            "Try Scanner → Scan, then Run bot."
        )
    else:
        summary["message"] = (
            f"Found {summary['candidates']} candidate(s) but none filled "
            f"({'; '.join(summary['skipped'][:3]) or 'risk/limits'})"
        )

    log.info(
        "cycle device=%s entries=%s candidates=%s stats=%s",
        device_id,
        n_entries,
        summary["candidates"],
        stats,
    )
    _save_last_cycle(device_id, summary)
    return summary


def run_all_devices(universe: list[str]) -> dict[str, Any]:
    devices = list_devices()
    if not devices:
        return {"devices": 0, "results": [], "message": "No registered devices"}
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
