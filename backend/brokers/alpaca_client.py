"""
Alpaca REST client (paper + live).

Uses the official HTTP API so we don't hard-depend on alpaca-py version churn.
Docs: https://docs.alpaca.markets/

Paper base: https://paper-api.alpaca.markets
Live base:  https://api.alpaca.markets
"""
from __future__ import annotations

import logging
from typing import Any, Optional

import httpx

log = logging.getLogger("tradeforge.alpaca")

PAPER_BASE = "https://paper-api.alpaca.markets"
LIVE_BASE = "https://api.alpaca.markets"


class AlpacaError(Exception):
    def __init__(self, message: str, status: int = 0, body: Any = None):
        super().__init__(message)
        self.status = status
        self.body = body


class AlpacaClient:
    def __init__(self, key_id: str, secret: str, *, paper: bool = True):
        self.key_id = key_id.strip()
        self.secret = secret.strip()
        self.paper = paper
        self.base = PAPER_BASE if paper else LIVE_BASE

    def _headers(self) -> dict[str, str]:
        return {
            "APCA-API-KEY-ID": self.key_id,
            "APCA-API-SECRET-KEY": self.secret,
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def _request(self, method: str, path: str, **kwargs) -> Any:
        url = f"{self.base}{path}"
        try:
            with httpx.Client(timeout=30.0, headers=self._headers()) as client:
                r = client.request(method, url, **kwargs)
        except Exception as e:
            raise AlpacaError(f"Network error: {e}") from e
        if r.status_code >= 400:
            try:
                body = r.json()
                msg = body.get("message") or body.get("error") or r.text
            except Exception:
                body, msg = r.text, r.text
            raise AlpacaError(str(msg), status=r.status_code, body=body)
        if r.status_code == 204 or not r.content:
            return None
        return r.json()

    def ping(self) -> dict[str, Any]:
        acct = self.get_account()
        return {
            "ok": True,
            "paper": self.paper,
            "account_number": acct.get("account_number"),
            "status": acct.get("status"),
            "equity": float(acct.get("equity") or 0),
            "cash": float(acct.get("cash") or 0),
            "buying_power": float(acct.get("buying_power") or 0),
            "currency": acct.get("currency", "USD"),
            "pattern_day_trader": acct.get("pattern_day_trader"),
        }

    def get_account(self) -> dict[str, Any]:
        return self._request("GET", "/v2/account")

    def get_positions(self) -> list[dict[str, Any]]:
        data = self._request("GET", "/v2/positions")
        return data if isinstance(data, list) else []

    def get_position(self, symbol: str) -> Optional[dict[str, Any]]:
        try:
            return self._request("GET", f"/v2/positions/{symbol.upper()}")
        except AlpacaError as e:
            if e.status == 404:
                return None
            raise

    def submit_market_order(
        self,
        symbol: str,
        *,
        side: str,
        notional: Optional[float] = None,
        qty: Optional[float] = None,
        client_order_id: Optional[str] = None,
    ) -> dict[str, Any]:
        body: dict[str, Any] = {
            "symbol": symbol.upper(),
            "side": side.lower(),  # buy | sell
            "type": "market",
            "time_in_force": "day",
        }
        if notional is not None:
            body["notional"] = str(round(float(notional), 2))
        elif qty is not None:
            body["qty"] = str(qty)
        else:
            raise AlpacaError("Provide notional or qty")
        if client_order_id:
            body["client_order_id"] = client_order_id[:48]
        return self._request("POST", "/v2/orders", json=body)

    def close_position(self, symbol: str) -> dict[str, Any]:
        return self._request("DELETE", f"/v2/positions/{symbol.upper()}")

    def get_orders(self, status: str = "all", limit: int = 50) -> list[dict[str, Any]]:
        data = self._request(
            "GET",
            "/v2/orders",
            params={"status": status, "limit": limit, "direction": "desc"},
        )
        return data if isinstance(data, list) else []
