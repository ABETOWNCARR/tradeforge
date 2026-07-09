# TradeForge

**Paper-first auto trading assistant** — chart pattern scanner, virtual portfolio, autonomous bot, and hard risk controls.

This project is intentionally **separate** from the Claude-built `robin_the_hood` / AutoTrade app so you can compare both side-by-side and pick the stronger candidate for Play Store.

## Why TradeForge is different

| Area | Robin the Hood (Claude) | TradeForge (this repo) |
|------|-------------------------|-------------------------|
| Primary mode | Live brokerage (Robinhood / SnapTrade) + scanner | **Paper trading first** ($10k virtual) |
| Navigation | 7 bottom tabs | 5 focused tabs (Home / Scanner / Portfolio / Bot / Settings) |
| Risk UX | Settings + agent screens | **Dedicated Bot cockpit** with kill switch, mode, strategy toggles |
| Architecture | Large mono-backend + many services | Smaller, clearer modules (`patterns`, `paper_broker`, `risk`, `auto_trader`) |
| Onboarding | Disclaimer → brokerage connect → security | Disclaimer → product tour → paper home |
| Play Store posture | Live trading assistant (higher review risk) | Educational / paper-first (clearer compliance path) |
| Brand | Green / AutoTrade | Teal Material 3 **TradeForge** |

Both apps can detect patterns and drive automated decisions. TradeForge optimizes for **safe demos, clarity, and store readiness**; Robin the Hood optimizes for **brokerage connectivity depth**.

## Features

- Pattern detection: RSI bounce, bull flag, ascending triangle, cup & handle, head & shoulders, MA cross, volume breakout
- Universe scan with confidence filter
- Paper portfolio with cash, positions, mark-to-market, journal
- Auto bot cycles (every 5 min on server) with stops / targets
- Modes: **auto paper** or **approval required**
- Risk: kill switch, pause, min confidence, max position $, max trades/day, daily loss limit, market hours only
- Per-strategy toggles
- Privacy policy endpoint for Play Store listing

## Project layout

```
tradeforge/
├── lib/                 # Flutter app
│   ├── main.dart
│   ├── screens/
│   ├── services/
│   ├── theme/
│   └── widgets/
├── backend/             # FastAPI API
│   ├── main.py
│   ├── patterns.py
│   ├── paper_broker.py
│   ├── risk.py
│   ├── auto_trader.py
│   └── ticker_universe.json
├── android/ ios/
└── README.md
```

## Quick start

### Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Health check: http://127.0.0.1:8000/

### Flutter app

```bash
# from repo root
flutter pub get

# iOS Simulator / desktop / chrome
flutter run --dart-define=BASE_URL=http://127.0.0.1:8000

# Android emulator (special host loopback)
flutter run --dart-define=BASE_URL=http://10.0.2.2:8000
```

### Manual bot cycle (demo)

```bash
curl -X POST http://127.0.0.1:8000/auto/run
```

## Play Store notes

1. Keep the product **educational + paper-first** in store listing copy.
2. Host `/privacy` publicly (or mirror `PRIVACY_POLICY.md`).
3. Screenshots: Home equity card, Scanner results, Bot kill switch, Portfolio journal.
4. If you later add live brokerage, expect stricter financial-app review; ship paper mode first.
5. Strong disclaimer is required on first launch (already implemented).

## Compare with Claude's app

| Path | App |
|------|-----|
| `/Users/michaelbarksdale/Projects/robin_the_hood` | Claude / AutoTrade |
| `/Users/michaelbarksdale/Projects/tradeforge` | TradeForge (this) |

GitHub for Claude app (existing): `https://github.com/ABETOWNCARR/robin-the-hood-app2`  
GitHub for TradeForge: created as a **separate** repository under the same account.

## Disclaimer

Not financial advice. Paper results ≠ live results. Trading involves risk of loss.
