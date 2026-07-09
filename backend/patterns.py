"""
TradeForge pattern detection.

Each detector returns confidence, breakout/stop/target levels, and whether
volume confirmation is required before entry.
"""
from __future__ import annotations

from typing import Any, Optional

import numpy as np
import pandas as pd

from market_data import fetch_universe_data, get_candles, get_quote, get_quotes  # re-export

# re-export for existing imports
__all__ = [
    "fetch_universe_data",
    "detect_patterns",
    "confirm_signal",
    "get_quote",
    "get_quotes",
    "get_candles",
]


def _rsi(series: pd.Series, window: int = 14) -> pd.Series:
    delta = series.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.rolling(window).mean()
    avg_loss = loss.rolling(window).mean()
    rs = avg_gain / avg_loss.replace(0, np.nan)
    return 100 - (100 / (1 + rs))


def _avg_volume(data: pd.DataFrame, lookback: int = 20) -> float:
    vol = data.get("Volume")
    if vol is None or vol.empty or len(vol) < lookback:
        return 0.0
    return float(vol.iloc[-lookback:].mean())


def _volume_ratio(data: pd.DataFrame) -> float:
    avg = _avg_volume(data)
    curr = float(data["Volume"].iloc[-1]) if "Volume" in data else 0.0
    if avg <= 0:
        return 0.0
    return round(curr / avg, 2)


def _sma(series: pd.Series, window: int) -> pd.Series:
    return series.rolling(window).mean()


def _detect_rsi_oversold_bounce(close: pd.Series, data: pd.DataFrame) -> Optional[dict]:
    rsi = _rsi(close)
    recent = rsi.dropna().iloc[-5:]
    if len(recent) < 5:
        return None
    min_rsi = float(recent.min())
    latest_rsi = float(rsi.iloc[-1])
    if min_rsi < 35 and latest_rsi > min_rsi:
        confidence = min(0.95, max(0.5, (35 - min_rsi) / 35 + (latest_rsi - min_rsi) / 100))
        current = float(close.iloc[-1])
        recent_low = float(close.iloc[-5:].min())
        return {
            "pattern": "RSI Oversold Bounce",
            "signal": "bullish",
            "confidence": round(confidence, 2),
            "breakout_level": round(current * 1.005, 4),
            "stop_level": round(recent_low * 0.985, 4),
            "target_level": round(current * 1.04, 4),
            "needs_volume": False,
            "volume_ratio": _volume_ratio(data),
        }
    return None


def _detect_bull_flag(close: pd.Series, data: pd.DataFrame) -> Optional[dict]:
    if len(close) < 20:
        return None
    pole = close.iloc[-20:-8]
    flag = close.iloc[-8:]
    pole_ret = float(pole.iloc[-1] / pole.iloc[0] - 1) if pole.iloc[0] else 0
    flag_range = float((flag.max() - flag.min()) / flag.mean()) if flag.mean() else 1
    flag_slope = float((flag.iloc[-1] - flag.iloc[0]) / flag.iloc[0]) if flag.iloc[0] else 0
    if pole_ret > 0.08 and flag_range < 0.06 and -0.04 < flag_slope < 0.02:
        current = float(close.iloc[-1])
        breakout = float(flag.max())
        stop = float(flag.min()) * 0.99
        target = breakout + (float(pole.max()) - float(pole.min()))
        conf = min(0.92, 0.55 + pole_ret + (0.06 - flag_range))
        return {
            "pattern": "Bull Flag",
            "signal": "bullish",
            "confidence": round(conf, 2),
            "breakout_level": round(breakout, 4),
            "stop_level": round(stop, 4),
            "target_level": round(target, 4),
            "needs_volume": True,
            "volume_ratio": _volume_ratio(data),
        }
    return None


def _detect_ascending_triangle(close: pd.Series, data: pd.DataFrame) -> Optional[dict]:
    if len(close) < 25:
        return None
    window = close.iloc[-25:]
    highs = window.rolling(3).max()
    lows = window.rolling(3).min()
    recent_highs = highs.dropna().iloc[-8:]
    recent_lows = lows.dropna().iloc[-8:]
    if len(recent_highs) < 5 or len(recent_lows) < 5:
        return None
    high_flat = (recent_highs.max() - recent_highs.min()) / recent_highs.mean() < 0.025
    low_rising = float(recent_lows.iloc[-1]) > float(recent_lows.iloc[0]) * 1.01
    if high_flat and low_rising:
        resistance = float(recent_highs.mean())
        current = float(close.iloc[-1])
        support = float(recent_lows.iloc[-1])
        conf = min(0.9, 0.6 + (current / resistance) * 0.2)
        return {
            "pattern": "Ascending Triangle",
            "signal": "bullish",
            "confidence": round(conf, 2),
            "breakout_level": round(resistance * 1.002, 4),
            "stop_level": round(support * 0.99, 4),
            "target_level": round(resistance + (resistance - support), 4),
            "needs_volume": True,
            "volume_ratio": _volume_ratio(data),
        }
    return None


def _detect_cup_and_handle(close: pd.Series, data: pd.DataFrame) -> Optional[dict]:
    if len(close) < 40:
        return None
    window = close.iloc[-40:]
    left = float(window.iloc[:10].max())
    bottom = float(window.iloc[10:28].min())
    right = float(window.iloc[28:35].max())
    handle = window.iloc[35:]
    cup_depth = (left - bottom) / left if left else 0
    rim_ok = abs(left - right) / left < 0.05 if left else False
    handle_shallow = float(handle.min()) > bottom + 0.5 * (left - bottom)
    if 0.12 < cup_depth < 0.4 and rim_ok and handle_shallow:
        current = float(close.iloc[-1])
        conf = min(0.9, 0.55 + cup_depth)
        return {
            "pattern": "Cup & Handle",
            "signal": "bullish",
            "confidence": round(conf, 2),
            "breakout_level": round(right * 1.005, 4),
            "stop_level": round(float(handle.min()) * 0.98, 4),
            "target_level": round(right + (left - bottom), 4),
            "needs_volume": True,
            "volume_ratio": _volume_ratio(data),
        }
    return None


def _detect_head_and_shoulders(close: pd.Series, data: pd.DataFrame) -> Optional[dict]:
    if len(close) < 35:
        return None
    w = close.iloc[-35:]
    # simple 3-peak approximation
    thirds = [w.iloc[i : i + 12] for i in range(0, 30, 10)]
    if len(thirds) < 3:
        return None
    peaks = [float(t.max()) for t in thirds]
    left, head, right = peaks
    if head > left * 1.03 and head > right * 1.03 and abs(left - right) / head < 0.04:
        neckline = float(min(w.iloc[10:15].min(), w.iloc[20:25].min()))
        current = float(close.iloc[-1])
        if current < head * 0.98:
            conf = min(0.88, 0.55 + (head - max(left, right)) / head)
            return {
                "pattern": "Head & Shoulders",
                "signal": "bearish",
                "confidence": round(conf, 2),
                "breakout_level": round(neckline * 0.998, 4),
                "stop_level": round(head * 1.01, 4),
                "target_level": round(neckline - (head - neckline), 4),
                "needs_volume": True,
                "volume_ratio": _volume_ratio(data),
            }
    return None


def _detect_ma_crossover(close: pd.Series, data: pd.DataFrame) -> Optional[dict]:
    if len(close) < 55:
        return None
    sma20 = _sma(close, 20)
    sma50 = _sma(close, 50)
    if pd.isna(sma20.iloc[-1]) or pd.isna(sma50.iloc[-1]):
        return None
    prev_diff = float(sma20.iloc[-2] - sma50.iloc[-2])
    curr_diff = float(sma20.iloc[-1] - sma50.iloc[-1])
    current = float(close.iloc[-1])
    if prev_diff <= 0 < curr_diff:
        return {
            "pattern": "Golden Cross (20/50)",
            "signal": "bullish",
            "confidence": 0.72,
            "breakout_level": round(current * 1.002, 4),
            "stop_level": round(float(sma50.iloc[-1]) * 0.98, 4),
            "target_level": round(current * 1.06, 4),
            "needs_volume": False,
            "volume_ratio": _volume_ratio(data),
        }
    if prev_diff >= 0 > curr_diff:
        return {
            "pattern": "Death Cross (20/50)",
            "signal": "bearish",
            "confidence": 0.72,
            "breakout_level": round(current * 0.998, 4),
            "stop_level": round(float(sma50.iloc[-1]) * 1.02, 4),
            "target_level": round(current * 0.94, 4),
            "needs_volume": False,
            "volume_ratio": _volume_ratio(data),
        }
    return None


def _detect_breakout_volume(close: pd.Series, data: pd.DataFrame) -> Optional[dict]:
    if len(close) < 30:
        return None
    lookback = close.iloc[-21:-1]
    resistance = float(lookback.max())
    current = float(close.iloc[-1])
    vol_ratio = _volume_ratio(data)
    if current > resistance * 1.005 and vol_ratio >= 1.5:
        stop = float(lookback.iloc[-5:].min())
        conf = min(0.93, 0.6 + min(vol_ratio, 3) * 0.08)
        return {
            "pattern": "Volume Breakout",
            "signal": "bullish",
            "confidence": round(conf, 2),
            "breakout_level": round(resistance, 4),
            "stop_level": round(stop * 0.99, 4),
            "target_level": round(current + (current - stop), 4),
            "needs_volume": True,
            "volume_ratio": vol_ratio,
        }
    return None


DETECTORS = [
    _detect_rsi_oversold_bounce,
    _detect_bull_flag,
    _detect_ascending_triangle,
    _detect_cup_and_handle,
    _detect_head_and_shoulders,
    _detect_ma_crossover,
    _detect_breakout_volume,
]


def detect_patterns(data: pd.DataFrame) -> list[dict[str, Any]]:
    """Run all detectors on a single ticker OHLC frame."""
    if data is None or data.empty or "Close" not in data.columns:
        return []
    close = data["Close"].dropna()
    if len(close) < 30:
        return []
    found = []
    for detector in DETECTORS:
        try:
            hit = detector(close, data)
            if hit:
                hit["price"] = round(float(close.iloc[-1]), 4)
                found.append(hit)
        except Exception:
            continue
    found.sort(key=lambda x: x.get("confidence", 0), reverse=True)
    return found


def confirm_signal(data: pd.DataFrame, pattern: dict, *, strict: bool = True) -> bool:
    """Confirm entry.

    strict=True  → price must clear breakout (+ volume when needs_volume).
    strict=False → setup mode: allow near-breakout / high-quality patterns for paper trading.
    """
    if data is None or data.empty or "Close" not in data.columns:
        return False
    price = float(data["Close"].iloc[-1])
    breakout = pattern.get("breakout_level")
    if breakout is None:
        return not strict
    breakout = float(breakout)
    signal = pattern.get("signal", "bullish")

    if strict:
        if signal == "bullish" and price < breakout:
            return False
        if signal == "bearish" and price > breakout:
            return False
        if pattern.get("needs_volume"):
            return _volume_ratio(data) >= 1.2
        return True

    # Setup mode (paper-friendly): accept if already through breakout OR within 1.5% of it
    # with solid confidence. Volume is a soft preference, not a hard block.
    conf = float(pattern.get("confidence") or 0)
    if conf < 0.65:
        return False
    if signal == "bullish":
        # price at least 98.5% of breakout (forming / near trigger)
        return price >= breakout * 0.985
    if signal == "bearish":
        return price <= breakout * 1.015
    return conf >= 0.7


# get_quote / get_quotes / get_candles imported from market_data
