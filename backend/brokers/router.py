"""
Unified broker router.

Modes:
  sim          — local virtual $10k paper (default, no keys)
  alpaca_paper — Alpaca paper trading account
  alpaca_live  — Alpaca live account (requires live_enabled + confirmation)

Credentials are stored per-device in broker_credentials.json (never logged).
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Optional
from uuid import uuid4

import paper_broker
import patterns
import store
from brokers.alpaca_client import AlpacaClient, AlpacaError

log = logging.getLogger("tradeforge.broker")

VALID_MODES = {"sim", "alpaca_paper", "alpaca_live"}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _creds() -> dict:
    return store.load("broker_credentials")


def _save_creds(data: dict) -> None:
    store.save("broker_credentials", data)


def get_mode(device_id: str) -> str:
    cfg = store.load("device_configs").get(device_id) or {}
    mode = (cfg.get("broker_mode") or "sim").lower()
    return mode if mode in VALID_MODES else "sim"


def set_mode(device_id: str, mode: str) -> dict:
    if mode not in VALID_MODES:
        raise ValueError(f"broker_mode must be one of {VALID_MODES}")
    configs = store.load("device_configs")
    cfg = configs.get(device_id) or {"device_id": device_id}
    if mode == "alpaca_live" and not cfg.get("live_enabled"):
        raise ValueError("Live trading is locked. Enable live_enabled after explicit confirmation.")
    cfg["broker_mode"] = mode
    cfg["device_id"] = device_id
    configs[device_id] = cfg
    store.save("device_configs", configs)
    return cfg


def connect_alpaca(
    device_id: str,
    *,
    api_key: str,
    api_secret: str,
    paper: bool = True,
    enable_live: bool = False,
) -> dict[str, Any]:
    """Validate keys, store credentials, switch broker mode."""
    if not api_key or not api_secret:
        return {"success": False, "error": "API key and secret are required"}
    client = AlpacaClient(api_key, api_secret, paper=paper)
    try:
        account = client.ping()
    except AlpacaError as e:
        return {"success": False, "error": f"Alpaca auth failed: {e}"}

    creds = _creds()
    creds[device_id] = {
        "provider": "alpaca",
        "api_key": api_key.strip(),
        "api_secret": api_secret.strip(),
        "paper_ok": True,
        "connected_at": _now(),
        # never store live flag without explicit enable
    }
    _save_creds(creds)

    configs = store.load("device_configs")
    cfg = configs.get(device_id) or {"device_id": device_id}
    cfg["broker_mode"] = "alpaca_paper" if paper else ("alpaca_live" if enable_live else "alpaca_paper")
    cfg["broker_provider"] = "alpaca"
    cfg["live_enabled"] = bool(enable_live and not paper)
    cfg["alpaca_account"] = {
        "account_number": account.get("account_number"),
        "status": account.get("status"),
        "paper": paper,
    }
    cfg["device_id"] = device_id
    configs[device_id] = cfg
    store.save("device_configs", configs)

    return {
        "success": True,
        "broker_mode": cfg["broker_mode"],
        "account": account,
        "warning": None
        if paper
        else "LIVE MODE — real money. Double-check risk limits before enabling the bot.",
    }


def disconnect_broker(device_id: str) -> dict[str, Any]:
    creds = _creds()
    if device_id in creds:
        del creds[device_id]
        _save_creds(creds)
    configs = store.load("device_configs")
    cfg = configs.get(device_id) or {"device_id": device_id}
    cfg["broker_mode"] = "sim"
    cfg["live_enabled"] = False
    cfg.pop("alpaca_account", None)
    configs[device_id] = cfg
    store.save("device_configs", configs)
    return {"success": True, "broker_mode": "sim"}


def get_broker_status(device_id: str) -> dict[str, Any]:
    mode = get_mode(device_id)
    cfg = store.load("device_configs").get(device_id) or {}
    has_keys = device_id in _creds()
    status: dict[str, Any] = {
        "broker_mode": mode,
        "provider": cfg.get("broker_provider") or ("alpaca" if mode.startswith("alpaca") else "sim"),
        "connected": mode == "sim" or has_keys,
        "live_enabled": bool(cfg.get("live_enabled")),
        "account": cfg.get("alpaca_account"),
        "is_live": mode == "alpaca_live",
        "is_sim": mode == "sim",
        "label": {
            "sim": "TradeForge Paper (sim)",
            "alpaca_paper": "Alpaca Paper",
            "alpaca_live": "Alpaca LIVE",
        }.get(mode, mode),
    }
    if mode.startswith("alpaca") and has_keys:
        try:
            client = _alpaca(device_id)
            status["account_live"] = client.ping()
        except Exception as e:
            status["account_error"] = str(e)
    return status


def _alpaca(device_id: str) -> AlpacaClient:
    c = _creds().get(device_id)
    if not c:
        raise AlpacaError("Alpaca not connected for this device")
    mode = get_mode(device_id)
    paper = mode != "alpaca_live"
    if mode == "alpaca_live":
        cfg = store.load("device_configs").get(device_id) or {}
        if not cfg.get("live_enabled"):
            raise AlpacaError("Live trading not enabled")
    return AlpacaClient(c["api_key"], c["api_secret"], paper=paper)


def _append_journal(device_id: str, entry: dict) -> None:
    journals = store.load("trade_journal")
    rows = journals.get(device_id, [])
    rows.insert(0, entry)
    journals[device_id] = rows[:500]
    store.save("trade_journal", journals)


def get_journal(device_id: str, limit: int = 50) -> list[dict]:
    # unified journal (sim + alpaca fills we recorded)
    return paper_broker.get_journal(device_id, limit)


def mark_to_market(device_id: str) -> dict[str, Any]:
    mode = get_mode(device_id)
    if mode == "sim":
        data = paper_broker.mark_to_market(device_id)
        data["broker_mode"] = "sim"
        data["broker_label"] = "TradeForge Paper (sim)"
        return data

    try:
        client = _alpaca(device_id)
        acct = client.get_account()
        positions_raw = client.get_positions()
    except AlpacaError as e:
        return {
            "device_id": device_id,
            "broker_mode": mode,
            "error": str(e),
            "cash": 0,
            "equity": 0,
            "positions": {},
            "position_count": 0,
        }

    enriched = {}
    positions_value = 0.0
    for p in positions_raw:
        sym = p.get("symbol")
        qty = float(p.get("qty") or 0)
        mv = float(p.get("market_value") or 0)
        upnl = float(p.get("unrealized_pl") or 0)
        avg = float(p.get("avg_entry_price") or 0)
        last = float(p.get("current_price") or 0)
        positions_value += mv
        enriched[sym] = {
            "qty": qty,
            "avg_price": avg,
            "last_price": last,
            "market_value": round(mv, 2),
            "unrealized_pnl": round(upnl, 2),
            "unrealized_pnl_pct": round(float(p.get("unrealized_plpc") or 0) * 100, 2),
            "side": p.get("side"),
            "stop_level": None,
            "target_level": None,
        }

    # merge local stop/target overlays if any
    overlays = store.load("position_overlays").get(device_id, {})
    for sym, o in overlays.items():
        if sym in enriched:
            enriched[sym]["stop_level"] = o.get("stop_level")
            enriched[sym]["target_level"] = o.get("target_level")
            enriched[sym]["pattern"] = o.get("pattern")
            enriched[sym]["confidence"] = o.get("confidence")

    cash = float(acct.get("cash") or 0)
    equity = float(acct.get("equity") or 0)
    last_equity = float(acct.get("last_equity") or equity)
    return {
        "device_id": device_id,
        "broker_mode": mode,
        "broker_label": "Alpaca Paper" if mode == "alpaca_paper" else "Alpaca LIVE",
        "cash": round(cash, 2),
        "positions_value": round(positions_value, 2),
        "equity": round(equity, 2),
        "starting_cash": round(last_equity, 2),
        "total_pnl": round(equity - last_equity, 2),
        "total_pnl_pct": round(((equity - last_equity) / last_equity * 100) if last_equity else 0, 2),
        "positions": enriched,
        "position_count": len(enriched),
        "buying_power": float(acct.get("buying_power") or 0),
        "account_status": acct.get("status"),
    }


def reset_portfolio(device_id: str) -> dict[str, Any]:
    if get_mode(device_id) != "sim":
        return {
            "success": False,
            "error": "Reset only applies to sim paper. Use Alpaca dashboard for real/paper accounts.",
        }
    paper_broker.reset_portfolio(device_id)
    return {"success": True, "portfolio": mark_to_market(device_id)}


def _set_overlay(device_id: str, ticker: str, **fields) -> None:
    data = store.load("position_overlays")
    device = data.get(device_id, {})
    cur = device.get(ticker, {})
    cur.update({k: v for k, v in fields.items() if v is not None})
    device[ticker] = cur
    data[device_id] = device
    store.save("position_overlays", data)


def _clear_overlay(device_id: str, ticker: str) -> None:
    data = store.load("position_overlays")
    device = data.get(device_id, {})
    if ticker in device:
        del device[ticker]
        data[device_id] = device
        store.save("position_overlays", data)


def buy(
    device_id: str,
    ticker: str,
    *,
    dollar_amount: Optional[float] = None,
    quantity: Optional[float] = None,
    reason: str = "",
    pattern: str = "",
    confidence: float = 0.0,
    stop_level: Optional[float] = None,
    target_level: Optional[float] = None,
    mode: str = "auto",
) -> dict[str, Any]:
    ticker = ticker.upper().strip()
    broker_mode = get_mode(device_id)

    if broker_mode == "sim":
        result = paper_broker.buy(
            device_id,
            ticker,
            dollar_amount=dollar_amount,
            quantity=quantity,
            reason=reason,
            pattern=pattern,
            confidence=confidence,
            stop_level=stop_level,
            target_level=target_level,
            mode=mode,
        )
        if result.get("success") and result.get("portfolio"):
            result["portfolio"]["broker_mode"] = "sim"
        return result

    # Alpaca
    try:
        client = _alpaca(device_id)
        if dollar_amount is not None:
            order = client.submit_market_order(
                ticker,
                side="buy",
                notional=float(dollar_amount),
                client_order_id=f"tf-b-{uuid4().hex[:12]}",
            )
            qty = float(order.get("qty") or 0) or None
            notional = float(dollar_amount)
        elif quantity is not None:
            order = client.submit_market_order(
                ticker,
                side="buy",
                qty=float(quantity),
                client_order_id=f"tf-b-{uuid4().hex[:12]}",
            )
            qty = float(quantity)
            notional = None
        else:
            return {"success": False, "error": "Provide dollar_amount or quantity"}

        _set_overlay(
            device_id,
            ticker,
            stop_level=stop_level,
            target_level=target_level,
            pattern=pattern,
            confidence=confidence,
            reason=reason,
        )
        price = patterns.get_quote(ticker)
        entry = {
            "id": order.get("id") or str(uuid4()),
            "side": "buy",
            "ticker": ticker,
            "qty": qty,
            "price": price,
            "notional": notional or (qty * price if qty and price else None),
            "reason": reason,
            "pattern": pattern,
            "confidence": confidence,
            "mode": f"{broker_mode}:{mode}",
            "timestamp": _now(),
            "broker": broker_mode,
            "order_status": order.get("status"),
        }
        _append_journal(device_id, entry)
        return {"success": True, "trade": entry, "portfolio": mark_to_market(device_id), "order": order}
    except AlpacaError as e:
        return {"success": False, "error": str(e)}


def sell(
    device_id: str,
    ticker: str,
    *,
    quantity: Optional[float] = None,
    reason: str = "",
    mode: str = "auto",
) -> dict[str, Any]:
    ticker = ticker.upper().strip()
    broker_mode = get_mode(device_id)

    if broker_mode == "sim":
        result = paper_broker.sell(
            device_id, ticker, quantity=quantity, reason=reason, mode=mode
        )
        if result.get("success") and result.get("portfolio"):
            result["portfolio"]["broker_mode"] = "sim"
        return result

    try:
        client = _alpaca(device_id)
        if quantity is None:
            order = client.close_position(ticker)
            qty = float(order.get("qty") or 0) if isinstance(order, dict) else None
        else:
            order = client.submit_market_order(
                ticker,
                side="sell",
                qty=float(quantity),
                client_order_id=f"tf-s-{uuid4().hex[:12]}",
            )
            qty = float(quantity)
        price = patterns.get_quote(ticker)
        entry = {
            "id": (order or {}).get("id") if isinstance(order, dict) else str(uuid4()),
            "side": "sell",
            "ticker": ticker,
            "qty": qty,
            "price": price,
            "notional": (qty * price) if qty and price else None,
            "reason": reason,
            "mode": f"{broker_mode}:{mode}",
            "timestamp": _now(),
            "broker": broker_mode,
        }
        _append_journal(device_id, entry)
        _clear_overlay(device_id, ticker)
        return {"success": True, "trade": entry, "portfolio": mark_to_market(device_id), "order": order}
    except AlpacaError as e:
        return {"success": False, "error": str(e)}


def check_exits(device_id: str) -> list[dict]:
    """Close positions that hit stop/target using local overlays + quotes."""
    mode = get_mode(device_id)
    if mode == "sim":
        return paper_broker.check_exits(device_id)

    portfolio = mark_to_market(device_id)
    positions = portfolio.get("positions") or {}
    exits = []
    for ticker, pos in list(positions.items()):
        price = pos.get("last_price")
        stop = pos.get("stop_level")
        target = pos.get("target_level")
        if price is None:
            continue
        reason = None
        if stop is not None and price <= float(stop):
            reason = f"Stop loss hit @ {price}"
        elif target is not None and price >= float(target):
            reason = f"Take profit hit @ {price}"
        if reason:
            result = sell(device_id, ticker, reason=reason, mode="auto_exit")
            if result.get("success"):
                exits.append(result["trade"])
    return exits
