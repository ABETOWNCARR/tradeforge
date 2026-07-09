"""
Resilient market data layer.

Yahoo Finance rate-limits cloud IPs (Railway) aggressively. Strategy:
  1. Short TTL cache so scan + auto cycle share one download
  2. Chunked yfinance batch download
  3. Fallback to Yahoo chart API (v8) via httpx for missing tickers
"""
from __future__ import annotations

import logging
import time
from typing import Optional

import httpx
import pandas as pd
import yfinance as yf

log = logging.getLogger("tradeforge.market_data")

_CACHE: dict[str, tuple[float, pd.DataFrame]] = {}
_CACHE_TTL = 180.0  # seconds
_QUOTE_CACHE: dict[str, tuple[float, float]] = {}

_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)


def _cache_get(ticker: str) -> Optional[pd.DataFrame]:
    hit = _CACHE.get(ticker)
    if not hit:
        return None
    ts, df = hit
    if time.time() - ts > _CACHE_TTL:
        return None
    return df


def _cache_set(ticker: str, df: pd.DataFrame) -> None:
    if df is not None and not df.empty:
        _CACHE[ticker] = (time.time(), df)


def _normalize_frame(df: pd.DataFrame) -> pd.DataFrame:
    if df is None or df.empty:
        return pd.DataFrame()
    if isinstance(df.columns, pd.MultiIndex):
        df = df.copy()
        df.columns = df.columns.get_level_values(0)
    # standardize column names
    cols = {c: str(c).title() for c in df.columns}
    df = df.rename(columns=cols)
    needed = ["Open", "High", "Low", "Close"]
    if not all(c in df.columns for c in needed):
        return pd.DataFrame()
    out = df[needed + (["Volume"] if "Volume" in df.columns else [])].dropna(how="all")
    return out


def _http_get_json(url: str, params: dict) -> Optional[dict]:
    """GET JSON with Chrome impersonation when available (bypasses many Yahoo 429s)."""
    # 1) curl_cffi (best for Yahoo from cloud IPs)
    try:
        from curl_cffi import requests as crequests  # type: ignore

        r = crequests.get(
            url,
            params=params,
            impersonate="chrome",
            timeout=25,
        )
        if r.status_code == 200:
            return r.json()
        log.debug("curl_cffi status %s for %s", r.status_code, url)
    except Exception as e:
        log.debug("curl_cffi failed: %s", e)

    # 2) plain httpx fallback
    try:
        headers = {
            "User-Agent": _UA,
            "Accept": "application/json,text/plain,*/*",
            "Accept-Language": "en-US,en;q=0.9",
        }
        with httpx.Client(timeout=25.0, headers=headers, follow_redirects=True) as client:
            r = client.get(url, params=params)
            if r.status_code == 200:
                return r.json()
    except Exception as e:
        log.debug("httpx failed: %s", e)
    return None


def _fetch_chart_api(ticker: str, range_: str = "3mo", interval: str = "1d") -> pd.DataFrame:
    """Yahoo chart API — preferred path with browser TLS impersonation."""
    hosts = (
        "https://query2.finance.yahoo.com",
        "https://query1.finance.yahoo.com",
    )
    params = {"range": range_, "interval": interval, "includePrePost": "false"}
    for host in hosts:
        url = f"{host}/v8/finance/chart/{ticker}"
        try:
            payload = _http_get_json(url, params)
            if not payload:
                continue
            result = (payload.get("chart") or {}).get("result") or []
            if not result:
                continue
            block = result[0]
            ts = block.get("timestamp") or []
            quote = (block.get("indicators") or {}).get("quote") or [{}]
            q0 = quote[0] if quote else {}
            if not ts:
                continue
            df = pd.DataFrame(
                {
                    "Open": q0.get("open"),
                    "High": q0.get("high"),
                    "Low": q0.get("low"),
                    "Close": q0.get("close"),
                    "Volume": q0.get("volume"),
                },
                index=pd.to_datetime(ts, unit="s", utc=True).tz_convert(None),
            )
            df = df.dropna(subset=["Close"])
            if not df.empty:
                return df
        except Exception as e:
            log.debug("chart api failed %s via %s: %s", ticker, host, e)
            continue
    return pd.DataFrame()


def _yf_batch(tickers: list[str], period: str, interval: str) -> dict[str, pd.DataFrame]:
    if not tickers:
        return {}
    out: dict[str, pd.DataFrame] = {}
    try:
        raw = yf.download(
            tickers=tickers if len(tickers) > 1 else tickers[0],
            period=period,
            interval=interval,
            group_by="ticker",
            threads=True,
            progress=False,
            auto_adjust=True,
        )
    except Exception as e:
        log.warning("yfinance batch failed: %s", e)
        return {}

    if raw is None or raw.empty:
        return {}

    multi = isinstance(raw.columns, pd.MultiIndex)
    if len(tickers) == 1 and not multi:
        frame = _normalize_frame(raw)
        if len(frame) >= 30:
            out[tickers[0]] = frame
        return out

    for t in tickers:
        try:
            frame = raw[t] if multi else raw
            frame = _normalize_frame(frame)
            if len(frame) >= 30:
                out[t] = frame
        except Exception:
            continue
    return out


def fetch_universe_data(
    tickers: list[str],
    period: str = "3mo",
    interval: str = "1d",
) -> dict[str, pd.DataFrame]:
    """Download OHLC for many tickers with cache + fallbacks."""
    tickers = [t.upper().strip() for t in tickers if t]
    result: dict[str, pd.DataFrame] = {}
    missing: list[str] = []

    for t in tickers:
        cached = _cache_get(t)
        if cached is not None and len(cached) >= 30:
            result[t] = cached
        else:
            missing.append(t)

    # Prefer chart API first on cloud (yfinance batch is often rate-limited there).
    # Fall back to yfinance for anything still missing.
    range_map = {"1mo": "1mo", "3mo": "3mo", "6mo": "6mo", "1y": "1y", "5d": "5d", "5d": "5d"}
    chart_range = range_map.get(period, "3mo")

    for t in list(missing):
        df = _normalize_frame(_fetch_chart_api(t, range_=chart_range, interval=interval))
        if len(df) >= 25:
            _cache_set(t, df)
            result[t] = df
        time.sleep(0.04)

    still = [t for t in missing if t not in result]
    chunk_size = 10
    for i in range(0, len(still), chunk_size):
        chunk = still[i : i + chunk_size]
        batch = _yf_batch(chunk, period, interval)
        for t, df in batch.items():
            _cache_set(t, df)
            result[t] = df
        if i + chunk_size < len(still):
            time.sleep(0.25)

    log.info("market_data fetched %d/%d tickers", len(result), len(tickers))
    return result


def get_quote(ticker: str) -> Optional[float]:
    ticker = ticker.upper().strip()
    q = _QUOTE_CACHE.get(ticker)
    if q and time.time() - q[0] < 60:
        return q[1]

    cached = _cache_get(ticker)
    if cached is not None and not cached.empty:
        price = float(cached["Close"].iloc[-1])
        _QUOTE_CACHE[ticker] = (time.time(), price)
        return price

    # chart API 5d
    df = _fetch_chart_api(ticker, range_="5d", interval="1d")
    df = _normalize_frame(df)
    if not df.empty:
        price = float(df["Close"].iloc[-1])
        _cache_set(ticker, df if len(df) >= 30 else df)
        _QUOTE_CACHE[ticker] = (time.time(), price)
        return price

    try:
        t = yf.Ticker(ticker)
        hist = t.history(period="5d", auto_adjust=True)
        if hist is not None and not hist.empty:
            price = float(hist["Close"].iloc[-1])
            _QUOTE_CACHE[ticker] = (time.time(), price)
            return price
    except Exception:
        pass
    return None


def get_quotes(tickers: list[str]) -> dict[str, float]:
    out: dict[str, float] = {}
    need: list[str] = []
    for t in tickers:
        t = t.upper().strip()
        q = _QUOTE_CACHE.get(t)
        if q and time.time() - q[0] < 60:
            out[t] = q[1]
        else:
            need.append(t)
    if need:
        frames = fetch_universe_data(need, period="5d", interval="1d")
        for t, df in frames.items():
            try:
                price = round(float(df["Close"].iloc[-1]), 4)
                out[t] = price
                _QUOTE_CACHE[t] = (time.time(), price)
            except Exception:
                continue
        for t in need:
            if t not in out:
                p = get_quote(t)
                if p is not None:
                    out[t] = round(p, 4)
    return out


def get_candles(ticker: str, timeframe: str = "3mo") -> list[dict]:
    interval_map = {
        "1d": ("5d", "1h"),
        "5d": ("1mo", "1d"),
        "1mo": ("3mo", "1d"),
        "3mo": ("6mo", "1d"),
        "1y": ("1y", "1d"),
    }
    period, interval = interval_map.get(timeframe, ("3mo", "1d"))
    frames = fetch_universe_data([ticker.upper()], period=period, interval=interval)
    df = frames.get(ticker.upper())
    if df is None or df.empty:
        # try chart directly
        range_map = {"1d": "5d", "5d": "1mo", "1mo": "3mo", "3mo": "6mo", "1y": "1y"}
        df = _normalize_frame(
            _fetch_chart_api(ticker.upper(), range_=range_map.get(timeframe, "3mo"), interval=interval)
        )
    if df is None or df.empty:
        return []
    candles = []
    for idx, row in df.iterrows():
        candles.append({
            "time": idx.isoformat() if hasattr(idx, "isoformat") else str(idx),
            "open": round(float(row["Open"]), 4),
            "high": round(float(row["High"]), 4),
            "low": round(float(row["Low"]), 4),
            "close": round(float(row["Close"]), 4),
            "volume": int(row["Volume"]) if "Volume" in row and pd.notna(row.get("Volume", 0)) else 0,
        })
    return candles
