"""
TradeForge API — paper-first auto trading backend.

Endpoints cover health, market data, pattern scanning, paper portfolio,
risk controls, approvals, and autonomous cycles.
"""
from __future__ import annotations

import json
import math
import os
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Optional

from apscheduler.schedulers.background import BackgroundScheduler
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field

import auto_trader
import paper_broker
import patterns
import risk

UNIVERSE_PATH = Path(__file__).parent / "ticker_universe.json"
TICKER_UNIVERSE: list[str] = json.loads(UNIVERSE_PATH.read_text())


def _json_safe(obj: Any) -> Any:
    if isinstance(obj, float):
        return obj if math.isfinite(obj) else None
    if isinstance(obj, dict):
        return {k: _json_safe(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_json_safe(v) for v in obj]
    return obj


class SafeJSONResponse(JSONResponse):
    def render(self, content: Any) -> bytes:
        return json.dumps(
            _json_safe(content),
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")


@asynccontextmanager
async def lifespan(app: FastAPI):
    scheduler = BackgroundScheduler(timezone="UTC")
    interval = int(os.environ.get("AUTO_CYCLE_MINUTES", "5"))
    scheduler.add_job(
        lambda: auto_trader.run_all_devices(TICKER_UNIVERSE),
        "interval",
        minutes=interval,
        id="auto_cycle",
        replace_existing=True,
    )
    scheduler.start()
    yield
    scheduler.shutdown(wait=False)


app = FastAPI(
    title="TradeForge API",
    version="1.0.0",
    lifespan=lifespan,
    default_response_class=SafeJSONResponse,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Models ──────────────────────────────────────────────────────────────────

class ScanRequest(BaseModel):
    tickers: Optional[list[str]] = None
    min_confidence: float = 0.0


class QuotesRequest(BaseModel):
    tickers: list[str]


class RegisterRequest(BaseModel):
    device_id: str
    fcm_token: str = ""
    trading_mode: str = "paper"
    min_confidence: float = 0.75
    max_trades_per_day: int = 5
    max_position_dollars: float = 500.0
    daily_loss_limit: float = 200.0
    is_paused: bool = False
    kill_switch: bool = False
    trade_schedule: str = "market_hours_only"
    allowed_tickers: list[str] = Field(default_factory=list)


class ConfigUpdate(BaseModel):
    device_id: str
    trading_mode: Optional[str] = None
    min_confidence: Optional[float] = None
    max_trades_per_day: Optional[int] = None
    max_position_dollars: Optional[float] = None
    daily_loss_limit: Optional[float] = None
    is_paused: Optional[bool] = None
    kill_switch: Optional[bool] = None
    trade_schedule: Optional[str] = None
    allowed_tickers: Optional[list[str]] = None
    auto_exit: Optional[bool] = None
    strategies: Optional[dict[str, bool]] = None
    fcm_token: Optional[str] = None


class PaperTradeRequest(BaseModel):
    device_id: str
    ticker: str
    side: str  # buy | sell
    dollar_amount: Optional[float] = None
    quantity: Optional[float] = None
    reason: str = "manual"
    stop_level: Optional[float] = None
    target_level: Optional[float] = None


class ApprovalAction(BaseModel):
    device_id: str
    approval_id: str
    approve: bool


# ── Health & privacy ────────────────────────────────────────────────────────

@app.get("/")
def health():
    return {
        "status": "ok",
        "service": "tradeforge-backend",
        "version": "1.0.0",
        "universe_size": len(TICKER_UNIVERSE),
        "market_open": risk.is_market_hours(),
    }


@app.get("/privacy", response_class=HTMLResponse)
def privacy_policy():
    return """<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Privacy Policy — TradeForge</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:720px;margin:40px auto;padding:0 20px;line-height:1.7;color:#111}
h1{color:#0d9488}h2{margin-top:2em}a{color:#0d9488}
</style></head><body>
<h1>Privacy Policy for TradeForge</h1>
<p><em>Last updated: July 9, 2026</em></p>
<p>TradeForge is an educational chart-pattern scanner and paper-trading assistant.
This policy explains what information we collect and how it is used.</p>
<h2>1. Information We Collect</h2>
<ul>
<li><strong>Device identifier</strong> — a random ID generated on your device to associate paper portfolios and settings. It is not your name, email, or phone number.</li>
<li><strong>Portfolio &amp; settings you configure</strong> — risk limits, strategy toggles, and paper trade history stored for the service you use.</li>
<li><strong>Tickers you scan</strong> — sent to our backend only to fetch market data and detect patterns.</li>
</ul>
<p>We do not collect government IDs, payment card numbers, or brokerage passwords in the paper-first product.</p>
<h2>2. How We Use Information</h2>
<ul>
<li>To run pattern scans and paper trades you request.</li>
<li>To enforce risk limits and autonomous paper trading cycles.</li>
<li>To improve reliability of the App.</li>
</ul>
<p>We do not sell your data.</p>
<h2>3. Third-Party Services</h2>
<ul>
<li><strong>Market data</strong> via Yahoo Finance (yfinance).</li>
<li><strong>Hosting</strong> of the optional backend API.</li>
</ul>
<h2>4. Your Choices</h2>
<p>You can reset your paper portfolio, pause trading, enable the kill switch, or uninstall the App at any time.</p>
<h2>5. Not Financial Advice</h2>
<p>TradeForge is educational. Paper results do not guarantee live trading results. All investing involves risk of loss.</p>
<h2>6. Contact</h2>
<p>Questions: open an issue on the TradeForge GitHub repository.</p>
</body></html>"""


# ── Market data ─────────────────────────────────────────────────────────────

@app.post("/quotes")
def quotes(req: QuotesRequest):
    return {"quotes": patterns.get_quotes(req.tickers[:50])}


@app.get("/candles/{ticker}")
def candles(ticker: str, timeframe: str = "3mo"):
    return {"ticker": ticker.upper(), "candles": patterns.get_candles(ticker.upper(), timeframe)}


@app.get("/universe")
def universe():
    return {"tickers": TICKER_UNIVERSE, "count": len(TICKER_UNIVERSE)}


# ── Scanner ─────────────────────────────────────────────────────────────────

@app.post("/scan")
def scan(req: ScanRequest):
    tickers = req.tickers or TICKER_UNIVERSE
    tickers = [t.upper() for t in tickers][:100]
    data = patterns.fetch_universe_data(tickers)
    results: dict[str, list] = {}
    high_confidence = []
    for ticker, df in data.items():
        hits = patterns.detect_patterns(df)
        hits = [h for h in hits if h.get("confidence", 0) >= req.min_confidence]
        if hits:
            results[ticker] = hits
            best = hits[0]
            if best.get("confidence", 0) >= 0.75:
                high_confidence.append({
                    "ticker": ticker,
                    "pattern": best.get("pattern"),
                    "signal": best.get("signal"),
                    "confidence": best.get("confidence"),
                    "price": best.get("price"),
                    "breakout_level": best.get("breakout_level"),
                    "stop_level": best.get("stop_level"),
                    "target_level": best.get("target_level"),
                })
    high_confidence.sort(key=lambda x: x.get("confidence", 0), reverse=True)
    return {
        "tickers_scanned": len(data),
        "results": results,
        "high_confidence_alerts": high_confidence,
        "market_open": risk.is_market_hours(),
    }


# ── Device / risk ───────────────────────────────────────────────────────────

@app.post("/register")
def register(req: RegisterRequest):
    cfg = auto_trader.register_device(
        req.device_id,
        fcm_token=req.fcm_token,
        trading_mode=req.trading_mode,
        min_confidence=req.min_confidence,
        max_trades_per_day=req.max_trades_per_day,
        max_position_dollars=req.max_position_dollars,
        daily_loss_limit=req.daily_loss_limit,
        is_paused=req.is_paused,
        kill_switch=req.kill_switch,
        trade_schedule=req.trade_schedule,
        allowed_tickers=req.allowed_tickers,
    )
    return {"success": True, "config": cfg}


@app.get("/config/{device_id}")
def get_config(device_id: str):
    return risk.risk_status(device_id)


@app.post("/config")
def update_config(req: ConfigUpdate):
    updates = req.model_dump(exclude_none=True)
    device_id = updates.pop("device_id")
    cfg = risk.set_config(device_id, updates)
    return {"success": True, "config": cfg}


@app.post("/kill-switch")
def kill_switch(device_id: str, enabled: bool = True):
    cfg = risk.set_config(device_id, {"kill_switch": enabled, "is_paused": enabled})
    return {"success": True, "config": cfg}


# ── Paper portfolio ─────────────────────────────────────────────────────────

@app.get("/portfolio/{device_id}")
def portfolio(device_id: str):
    return paper_broker.mark_to_market(device_id)


@app.post("/portfolio/{device_id}/reset")
def reset_portfolio(device_id: str):
    p = paper_broker.reset_portfolio(device_id)
    return {"success": True, "portfolio": paper_broker.mark_to_market(device_id), "raw": p}


@app.get("/journal/{device_id}")
def journal(device_id: str, limit: int = 50):
    return {"trades": paper_broker.get_journal(device_id, limit)}


@app.post("/trade")
def trade(req: PaperTradeRequest):
    side = req.side.lower()
    if side == "buy":
        result = paper_broker.buy(
            req.device_id,
            req.ticker,
            dollar_amount=req.dollar_amount,
            quantity=req.quantity,
            reason=req.reason,
            stop_level=req.stop_level,
            target_level=req.target_level,
            mode="paper_manual",
        )
    elif side == "sell":
        result = paper_broker.sell(
            req.device_id,
            req.ticker,
            quantity=req.quantity,
            reason=req.reason,
            mode="paper_manual",
        )
    else:
        raise HTTPException(400, "side must be buy or sell")
    if result.get("success"):
        risk.record_trade(req.device_id, float(result.get("trade", {}).get("realized_pnl", 0) or 0))
    return result


# ── Approvals ───────────────────────────────────────────────────────────────

@app.get("/approvals/{device_id}")
def approvals(device_id: str):
    return {"approvals": auto_trader.get_approvals(device_id)}


@app.post("/approvals/resolve")
def resolve_approval(req: ApprovalAction):
    return auto_trader.resolve_approval(req.device_id, req.approval_id, req.approve)


# ── Auto cycle ──────────────────────────────────────────────────────────────

@app.post("/auto/run")
def run_auto():
    """Manually trigger one autonomous cycle (useful for demos)."""
    return auto_trader.run_all_devices(TICKER_UNIVERSE)


@app.post("/auto/run/{device_id}")
def run_auto_device(device_id: str):
    data = patterns.fetch_universe_data(TICKER_UNIVERSE)
    return auto_trader.run_cycle_for_device(device_id, data)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=int(os.environ.get("PORT", "8000")), reload=True)
