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
- **Sim paper** ($10k virtual) + **Alpaca paper / live** broker path
- Auto bot cycles (every 5 min) with stops / targets
- Modes: auto execute or approval-required
- Risk: kill switch, **% equity sizing**, max $ cap, max open positions, max entries/day, daily loss, market hours
- Performance stats (win rate, buys/sells)
- Privacy policy endpoint for Play Store listing

## Broker modes (ready for real money)

| Mode | Money | Keys | Notes |
|------|-------|------|--------|
| **sim** | Virtual $10k | None | Default, safest |
| **alpaca_paper** | Alpaca paper | Paper API keys | Same bot → real broker API |
| **alpaca_live** | **Real money** | Live keys + confirm | Kill switch + limits still apply |

In the app: **Settings → Brokerage**  
Keys: https://app.alpaca.markets  

Live switch requires an explicit confirmation dialog (and `live_confirm=true` on the API).

## Project layout

```
tradeforge/
├── lib/                 # Flutter app
│   ├── screens/         # includes broker_screen.dart
│   └── services/
├── backend/
│   ├── brokers/         # sim + Alpaca adapters
│   ├── main.py
│   ├── patterns.py
│   ├── paper_broker.py
│   ├── risk.py
│   ├── auto_trader.py
│   └── performance.py
└── README.md
```

## Quick start

### Production API (Railway)

**Base URL:** https://tradeforge-production-4b30.up.railway.app

| Endpoint | URL |
|----------|-----|
| Health | https://tradeforge-production-4b30.up.railway.app/ |
| Privacy | https://tradeforge-production-4b30.up.railway.app/privacy |
| Dashboard | Railway project `tradeforge` (service: `tradeforge`) |

The Flutter app defaults to this production URL. No `--dart-define` required for normal runs.

### Backend (local)

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Health check: http://127.0.0.1:8000/

Redeploy after backend changes:

```bash
cd backend
railway up -y --detach
```

### Flutter app

```bash
# from repo root — uses production API by default
flutter pub get
flutter run

# point at local backend instead
flutter run --dart-define=BASE_URL=http://127.0.0.1:8000

# Android emulator + local backend
flutter run --dart-define=BASE_URL=http://10.0.2.2:8000
```

### Manual bot cycle (demo)

```bash
curl -X POST https://tradeforge-production-4b30.up.railway.app/auto/run
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
