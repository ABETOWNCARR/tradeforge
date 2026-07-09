"""
Paper trading broker — simulated portfolio with cash, positions, stops/targets.

Default starting capital: $10,000 virtual USD.
All fills use latest market price from yfinance (no slippage model in MVP).
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional
from uuid import uuid4

import store
import patterns

STARTING_CASH = 10_000.0


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def get_portfolio(device_id: str) -> dict[str, Any]:
    portfolios = store.load("paper_portfolios")
    if device_id not in portfolios:
        portfolios[device_id] = {
            "cash": STARTING_CASH,
            "starting_cash": STARTING_CASH,
            "positions": {},  # ticker -> position dict
            "created_at": _now(),
        }
        store.save("paper_portfolios", portfolios)
    return portfolios[device_id]


def _save_portfolio(device_id: str, portfolio: dict) -> None:
    portfolios = store.load("paper_portfolios")
    portfolios[device_id] = portfolio
    store.save("paper_portfolios", portfolios)


def reset_portfolio(device_id: str) -> dict[str, Any]:
    portfolios = store.load("paper_portfolios")
    portfolios[device_id] = {
        "cash": STARTING_CASH,
        "starting_cash": STARTING_CASH,
        "positions": {},
        "created_at": _now(),
        "reset_at": _now(),
    }
    store.save("paper_portfolios", portfolios)
    # clear journal for this device
    journals = store.load("trade_journal")
    journals[device_id] = []
    store.save("trade_journal", journals)
    return portfolios[device_id]


def _append_journal(device_id: str, entry: dict) -> None:
    journals = store.load("trade_journal")
    rows = journals.get(device_id, [])
    rows.insert(0, entry)
    journals[device_id] = rows[:500]
    store.save("trade_journal", journals)


def get_journal(device_id: str, limit: int = 50) -> list[dict]:
    journals = store.load("trade_journal")
    return journals.get(device_id, [])[:limit]


def mark_to_market(device_id: str) -> dict[str, Any]:
    """Refresh position market values and return summary."""
    portfolio = get_portfolio(device_id)
    positions = portfolio.get("positions", {})
    tickers = list(positions.keys())
    quotes = patterns.get_quotes(tickers) if tickers else {}
    equity = float(portfolio["cash"])
    positions_value = 0.0
    enriched = {}
    for ticker, pos in positions.items():
        price = quotes.get(ticker, float(pos.get("avg_price", 0)))
        qty = float(pos["qty"])
        market_value = price * qty
        cost = float(pos["avg_price"]) * qty
        unrealized = market_value - cost
        positions_value += market_value
        equity += market_value
        enriched[ticker] = {
            **pos,
            "last_price": price,
            "market_value": round(market_value, 2),
            "unrealized_pnl": round(unrealized, 2),
            "unrealized_pnl_pct": round((unrealized / cost * 100) if cost else 0, 2),
        }
    starting = float(portfolio.get("starting_cash", STARTING_CASH))
    return {
        "device_id": device_id,
        "cash": round(float(portfolio["cash"]), 2),
        "positions_value": round(positions_value, 2),
        "equity": round(equity, 2),
        "starting_cash": starting,
        "total_pnl": round(equity - starting, 2),
        "total_pnl_pct": round((equity - starting) / starting * 100, 2) if starting else 0,
        "positions": enriched,
        "position_count": len(enriched),
    }


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
    mode: str = "paper",
) -> dict[str, Any]:
    ticker = ticker.upper().strip()
    price = patterns.get_quote(ticker)
    if price is None or price <= 0:
        return {"success": False, "error": f"No quote available for {ticker}"}

    portfolio = get_portfolio(device_id)
    cash = float(portfolio["cash"])

    if dollar_amount is not None:
        qty = dollar_amount / price
        cost = dollar_amount
    elif quantity is not None:
        qty = float(quantity)
        cost = qty * price
    else:
        return {"success": False, "error": "Provide dollar_amount or quantity"}

    if qty <= 0:
        return {"success": False, "error": "Quantity must be positive"}
    if cost > cash + 0.01:
        return {"success": False, "error": f"Insufficient cash (${cash:.2f}) for ${cost:.2f} order"}

    positions = portfolio.setdefault("positions", {})
    existing = positions.get(ticker)
    if existing:
        old_qty = float(existing["qty"])
        old_avg = float(existing["avg_price"])
        new_qty = old_qty + qty
        new_avg = ((old_qty * old_avg) + cost) / new_qty
        existing["qty"] = new_qty
        existing["avg_price"] = new_avg
        if stop_level:
            existing["stop_level"] = stop_level
        if target_level:
            existing["target_level"] = target_level
    else:
        positions[ticker] = {
            "qty": qty,
            "avg_price": price,
            "opened_at": _now(),
            "stop_level": stop_level,
            "target_level": target_level,
            "pattern": pattern,
            "confidence": confidence,
        }

    portfolio["cash"] = cash - cost
    _save_portfolio(device_id, portfolio)

    trade_id = str(uuid4())
    entry = {
        "id": trade_id,
        "side": "buy",
        "ticker": ticker,
        "qty": round(qty, 6),
        "price": round(price, 4),
        "notional": round(cost, 2),
        "reason": reason,
        "pattern": pattern,
        "confidence": confidence,
        "mode": mode,
        "timestamp": _now(),
    }
    _append_journal(device_id, entry)
    return {"success": True, "trade": entry, "portfolio": mark_to_market(device_id)}


def sell(
    device_id: str,
    ticker: str,
    *,
    quantity: Optional[float] = None,
    reason: str = "",
    mode: str = "paper",
) -> dict[str, Any]:
    ticker = ticker.upper().strip()
    portfolio = get_portfolio(device_id)
    positions = portfolio.get("positions", {})
    pos = positions.get(ticker)
    if not pos:
        return {"success": False, "error": f"No open position in {ticker}"}

    price = patterns.get_quote(ticker)
    if price is None or price <= 0:
        return {"success": False, "error": f"No quote available for {ticker}"}

    open_qty = float(pos["qty"])
    qty = open_qty if quantity is None else min(float(quantity), open_qty)
    if qty <= 0:
        return {"success": False, "error": "Quantity must be positive"}

    proceeds = qty * price
    portfolio["cash"] = float(portfolio["cash"]) + proceeds

    if qty >= open_qty - 1e-9:
        del positions[ticker]
    else:
        pos["qty"] = open_qty - qty

    _save_portfolio(device_id, portfolio)

    cost_basis = float(pos["avg_price"]) * qty
    realized = proceeds - cost_basis
    trade_id = str(uuid4())
    entry = {
        "id": trade_id,
        "side": "sell",
        "ticker": ticker,
        "qty": round(qty, 6),
        "price": round(price, 4),
        "notional": round(proceeds, 2),
        "realized_pnl": round(realized, 2),
        "reason": reason,
        "mode": mode,
        "timestamp": _now(),
    }
    _append_journal(device_id, entry)
    return {"success": True, "trade": entry, "portfolio": mark_to_market(device_id)}


def check_exits(device_id: str) -> list[dict]:
    """Close positions that hit stop or target. Returns list of exit trades."""
    portfolio = get_portfolio(device_id)
    positions = dict(portfolio.get("positions", {}))
    if not positions:
        return []
    quotes = patterns.get_quotes(list(positions.keys()))
    exits = []
    for ticker, pos in positions.items():
        price = quotes.get(ticker)
        if price is None:
            continue
        stop = pos.get("stop_level")
        target = pos.get("target_level")
        reason = None
        if stop is not None and price <= float(stop):
            reason = f"Stop loss hit @ {price}"
        elif target is not None and price >= float(target):
            reason = f"Take profit hit @ {price}"
        if reason:
            result = sell(device_id, ticker, reason=reason, mode="paper_auto_exit")
            if result.get("success"):
                exits.append(result["trade"])
    return exits
