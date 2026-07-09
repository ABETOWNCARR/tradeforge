"""
JSON file-backed persistence for devices, paper portfolios, and trade journals.
Simple and portable — no database required for MVP / comparison demos.
"""
from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import Any

_LOCK = threading.Lock()
_DATA_DIR = Path(__file__).parent / "data"
_DATA_DIR.mkdir(exist_ok=True)


def _path(name: str) -> Path:
    return _DATA_DIR / f"{name}.json"


def load(name: str) -> dict[str, Any]:
    p = _path(name)
    if not p.exists():
        return {}
    try:
        with _LOCK:
            return json.loads(p.read_text())
    except Exception:
        return {}


def save(name: str, data: dict[str, Any]) -> None:
    p = _path(name)
    with _LOCK:
        p.write_text(json.dumps(data, indent=2, default=str))


def update(name: str, key: str, value: Any) -> dict[str, Any]:
    data = load(name)
    data[key] = value
    save(name, data)
    return data
