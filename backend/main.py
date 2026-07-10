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
import brokers
import patterns
import performance
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
    # Optional overrides only applied for brand-new devices via register_device defaults path.
    # Existing devices keep their saved config (heartbeat-only register).


class ConfigUpdate(BaseModel):
    device_id: str
    trading_mode: Optional[str] = None
    min_confidence: Optional[float] = None
    max_trades_per_day: Optional[int] = None
    max_position_dollars: Optional[float] = None
    position_size_pct: Optional[float] = None
    max_open_positions: Optional[int] = None
    daily_loss_limit: Optional[float] = None
    is_paused: Optional[bool] = None
    kill_switch: Optional[bool] = None
    trade_schedule: Optional[str] = None
    allowed_tickers: Optional[list[str]] = None
    auto_exit: Optional[bool] = None
    entry_style: Optional[str] = None  # setup | confirmed
    broker_mode: Optional[str] = None  # sim | alpaca_paper | alpaca_live
    live_enabled: Optional[bool] = None
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


class AlpacaConnectRequest(BaseModel):
    device_id: str
    api_key: str
    api_secret: str
    paper: bool = True
    enable_live: bool = False


class BrokerModeRequest(BaseModel):
    device_id: str
    broker_mode: str  # sim | alpaca_paper | alpaca_live
    live_confirm: bool = False  # required to switch to alpaca_live


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
            if best.get("confidence", 0) >= 0.70:
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
    # Cache signals so auto-trader can still act if a later Yahoo fetch is rate-limited
    import store as _store
    from datetime import datetime, timezone as _tz
    _store.save(
        "last_scan_signals",
        {
            "saved_at": datetime.now(_tz.utc).isoformat(),
            "tickers_scanned": len(data),
            "alerts": high_confidence,
            "results": {k: v for k, v in list(results.items())[:80]},
        },
    )
    return {
        "tickers_scanned": len(data),
        "results": results,
        "high_confidence_alerts": high_confidence,
        "market_open": risk.is_market_hours(),
        "data_ok": len(data) > 0,
        "message": None
        if data
        else "Market data temporarily unavailable (Yahoo rate limit). Try again in a minute.",
    }


# ── Device / risk ───────────────────────────────────────────────────────────

@app.post("/register")
def register(req: RegisterRequest):
    # Heartbeat only — do not blast risk settings on every app launch.
    # New devices get DEFAULT_CONFIG; existing devices keep their limits.
    cfg = auto_trader.register_device(
        req.device_id,
        fcm_token=req.fcm_token or None,
    )
    return {"success": True, "config": cfg}


@app.post("/daily/reset")
def reset_daily(device_id: str):
    """Reset today's entry counter (paper debugging / new session)."""
    state = risk.reset_daily(device_id)
    return {"success": True, "daily": state, **risk.risk_status(device_id)}


@app.get("/config/{device_id}")
def get_config(device_id: str):
    status = risk.risk_status(device_id)
    status["last_cycle"] = auto_trader.get_last_cycle(device_id)
    status["broker"] = brokers.get_broker_status(device_id)
    status["performance"] = performance.summarize(device_id)
    return status


@app.post("/config")
def update_config(req: ConfigUpdate):
    updates = req.model_dump(exclude_none=True)
    device_id = updates.pop("device_id")
    # Never silently enable live from generic config
    if updates.get("broker_mode") == "alpaca_live" and not updates.get("live_enabled"):
        raise HTTPException(400, "Use /broker/mode with live_confirm to enable live trading")
    cfg = risk.set_config(device_id, updates)
    return {"success": True, "config": cfg}


@app.post("/kill-switch")
def kill_switch(device_id: str, enabled: bool = True):
    cfg = risk.set_config(device_id, {"kill_switch": enabled, "is_paused": enabled})
    return {"success": True, "config": cfg}


# ── Broker connection (Alpaca paper / live) ─────────────────────────────────

@app.get("/broker/{device_id}")
def broker_status(device_id: str):
    return brokers.get_broker_status(device_id)


@app.post("/broker/alpaca/connect")
def broker_alpaca_connect(req: AlpacaConnectRequest):
    """Connect Alpaca. Default paper=True. Live requires enable_live=True."""
    if not req.paper and not req.enable_live:
        raise HTTPException(
            400,
            "Refusing live connect without enable_live=true. Start with paper=true.",
        )
    result = brokers.connect_alpaca(
        req.device_id,
        api_key=req.api_key,
        api_secret=req.api_secret,
        paper=req.paper,
        enable_live=req.enable_live,
    )
    if not result.get("success"):
        raise HTTPException(400, result.get("error") or "Connect failed")
    return result


@app.post("/broker/disconnect")
def broker_disconnect(device_id: str):
    return brokers.disconnect_broker(device_id)


@app.post("/broker/mode")
def broker_mode(req: BrokerModeRequest):
    """Switch sim / alpaca_paper / alpaca_live with live confirmation gate."""
    mode = req.broker_mode.lower()
    if mode == "alpaca_live":
        if not req.live_confirm:
            raise HTTPException(
                400,
                "Switching to LIVE requires live_confirm=true. Real money will be used.",
            )
        risk.set_config(req.device_id, {"live_enabled": True, "broker_mode": "alpaca_live"})
    elif mode == "alpaca_paper":
        risk.set_config(req.device_id, {"broker_mode": "alpaca_paper", "live_enabled": False})
    elif mode == "sim":
        risk.set_config(req.device_id, {"broker_mode": "sim", "live_enabled": False})
    else:
        raise HTTPException(400, f"Unknown broker_mode: {mode}")
    try:
        if mode != "sim":
            brokers.set_mode(req.device_id, mode)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"success": True, "broker": brokers.get_broker_status(req.device_id)}


# ── Portfolio (sim or live broker) ──────────────────────────────────────────

@app.get("/portfolio/{device_id}")
def portfolio(device_id: str):
    return brokers.mark_to_market(device_id)


@app.post("/portfolio/{device_id}/reset")
def reset_portfolio(device_id: str):
    result = brokers.reset_portfolio(device_id)
    if not result.get("success", True) and result.get("error"):
        raise HTTPException(400, result["error"])
    return result


@app.get("/journal/{device_id}")
def journal(device_id: str, limit: int = 50):
    return {"trades": brokers.get_journal(device_id, limit)}


@app.get("/performance/{device_id}")
def perf(device_id: str):
    return performance.summarize(device_id)


@app.post("/trade")
def trade(req: PaperTradeRequest):
    side = req.side.lower()
    if side == "buy":
        result = brokers.buy(
            req.device_id,
            req.ticker,
            dollar_amount=req.dollar_amount,
            quantity=req.quantity,
            reason=req.reason,
            stop_level=req.stop_level,
            target_level=req.target_level,
            mode="manual",
        )
    elif side == "sell":
        result = brokers.sell(
            req.device_id,
            req.ticker,
            quantity=req.quantity,
            reason=req.reason,
            mode="manual",
        )
    else:
        raise HTTPException(400, "side must be buy or sell")
    if result.get("success"):
        is_exit = side == "sell"
        risk.record_trade(
            req.device_id,
            float(result.get("trade", {}).get("realized_pnl", 0) or 0),
            count_toward_limit=not is_exit,
            is_exit=is_exit,
        )
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
