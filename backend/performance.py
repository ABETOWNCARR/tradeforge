"""Portfolio performance helpers from trade journal + mark-to-market."""
from __future__ import annotations

from typing import Any

import brokers


def summarize(device_id: str) -> dict[str, Any]:
    portfolio = brokers.mark_to_market(device_id)
    journal = brokers.get_journal(device_id, limit=200)
    buys = [t for t in journal if t.get("side") == "buy"]
    sells = [t for t in journal if t.get("side") == "sell"]
    realized = sum(float(t.get("realized_pnl") or 0) for t in sells)
    wins = [t for t in sells if float(t.get("realized_pnl") or 0) > 0]
    losses = [t for t in sells if float(t.get("realized_pnl") or 0) < 0]
    win_rate = (len(wins) / len(sells) * 100) if sells else 0.0

    by_pattern: dict[str, dict] = {}
    for t in sells:
        # try match reason/pattern
        pat = t.get("pattern") or "unknown"
        bucket = by_pattern.setdefault(pat, {"trades": 0, "pnl": 0.0})
        bucket["trades"] += 1
        bucket["pnl"] += float(t.get("realized_pnl") or 0)

    return {
        "equity": portfolio.get("equity"),
        "cash": portfolio.get("cash"),
        "total_pnl": portfolio.get("total_pnl"),
        "total_pnl_pct": portfolio.get("total_pnl_pct"),
        "open_positions": portfolio.get("position_count"),
        "broker_mode": portfolio.get("broker_mode"),
        "broker_label": portfolio.get("broker_label"),
        "stats": {
            "buys": len(buys),
            "sells": len(sells),
            "realized_pnl": round(realized, 2),
            "wins": len(wins),
            "losses": len(losses),
            "win_rate_pct": round(win_rate, 1),
            "avg_win": round(sum(float(t.get("realized_pnl") or 0) for t in wins) / len(wins), 2) if wins else 0,
            "avg_loss": round(sum(float(t.get("realized_pnl") or 0) for t in losses) / len(losses), 2) if losses else 0,
        },
        "by_pattern": by_pattern,
    }
