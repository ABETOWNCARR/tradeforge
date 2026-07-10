# TradeForge — Sharing builds & store readiness

## Shareable APK (testing now)

| File | Path |
|------|------|
| **Easy share copy** | `~/Desktop/TradeForge-1.0.0.apk` |
| Project copy | `~/Projects/tradeforge/dist/TradeForge-1.0.0.apk` |
| Build output | `~/Projects/tradeforge/build/app/outputs/flutter-apk/app-release.apk` |
| Play Store bundle | `~/Projects/tradeforge/build/app/outputs/bundle/release/app-release.aab` |

Size: ~50 MB · Version: **1.0.0** (build 1)

### Install on another Android phone

1. Send the APK (AirDrop, Drive, Messages, USB).
2. On the phone: allow **Install unknown apps** for that source.
3. Open the APK and install.
4. App talks to production API: `https://tradeforge-production-4b30.up.railway.app`

> This release is signed with **debug keys** (fine for testing).  
> Play Store needs a **upload keystore** you create once and never lose.

Rebuild anytime:
```bash
cd ~/Projects/tradeforge
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk dist/TradeForge-1.0.0.apk
```

---

## Google Play Store checklist

### 1. Developer account
- [ ] Google Play Console: https://play.google.com/console  
- [ ] One-time fee (~$25)

### 2. Create a real release keystore (do once, back up!)
```bash
keytool -genkey -v -keystore ~/tradeforge-upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias tradeforge
```
Create `android/key.properties` (do **not** commit secrets):
```
storePassword=***
keyPassword=***
keyAlias=tradeforge
storeFile=/Users/YOU/tradeforge-upload-keystore.jks
```
Wire it into `android/app/build.gradle.kts` signingConfigs, then:
```bash
flutter build appbundle --release
```
Upload: `build/app/outputs/bundle/release/app-release.aab`

### 3. Store listing
- [ ] App name: **TradeForge**
- [ ] Short + full description (educational / paper-first)
- [ ] Screenshots: phone (Home, Scanner, Portfolio, Bot, Brokerage)
- [ ] Feature graphic 1024×500
- [ ] High-res icon 512×512
- [ ] Privacy policy URL (live):  
  https://tradeforge-production-4b30.up.railway.app/privacy

### 4. Content / compliance (important for trading apps)
- [ ] **Strong disclaimer**: not financial advice; paper-first
- [ ] Data safety form in Play Console
- [ ] Finance / education category as appropriate
- [ ] If you enable **live brokerage**, expect stricter review  
  → Ship **sim + Alpaca paper** first is safer

### 5. App identity polish
- [ ] Final package id (e.g. `com.yourname.tradeforge`) — hard to change later  
  Current: `com.tradeforge.tradeforge`
- [ ] Bump `version:` in `pubspec.yaml` each release (`1.0.1+2`, etc.)
- [ ] Turn off cleartext traffic for production if not needed
- [ ] Target recent Android / SDK (Flutter defaults usually OK)

### 6. Testing tracks
1. **Internal testing** (you + testers via email)  
2. **Closed testing**  
3. **Production**

---

## Apple App Store checklist

### 1. Accounts & Mac tooling
- [ ] Apple Developer Program (~$99/year)
- [ ] Xcode installed, signed in
- [ ] Apple ID with 2FA

### 2. iOS project
```bash
cd ~/Projects/tradeforge
open ios/Runner.xcworkspace
```
- [ ] Bundle ID: e.g. `com.yourname.tradeforge` (unique)
- [ ] Signing & Capabilities → Team
- [ ] Display name TradeForge
- [ ] App icons in Assets.xcassets
- [ ] Privacy strings in `Info.plist` if needed (network is fine)

Build:
```bash
flutter build ipa --release
```
Or archive from Xcode → Organizer → Distribute.

### 3. App Store Connect
- [ ] Create app record
- [ ] Screenshots (6.7" and 6.1" iPhones minimum)
- [ ] Description, keywords, support URL, privacy policy URL
- [ ] Age rating questionnaire
- [ ] Export compliance (usually “no” for standard HTTPS)

### 4. Review notes for Apple
- Demo account not required if no login
- Explain: **educational paper trading / optional user-supplied broker API keys**
- Live trading is user-initiated with disclaimers
- Provide privacy policy link

### 5. TestFlight first
- Upload build → TestFlight → internal + external testers  
- Then submit for App Review

---

## What to do before you “go store”

| Priority | Item |
|----------|------|
| Must | Real Android upload keystore (backup!) |
| Must | Hosted privacy policy (done) |
| Must | Screenshots + store text |
| Must | Final package / bundle IDs |
| Should | Persistent backend storage (Railway volume) so data survives deploys |
| Should | Remove debug cleartext if unused |
| Should | Crash reporting (Firebase Crashlytics / Sentry) |
| Nice | Support email + simple website |
| Careful | Live auto-trading increases review risk — paper-first listing is safer |

---

## Quick commands

```bash
# Android APK for friends
flutter build apk --release

# Android Play Store
flutter build appbundle --release

# iOS (Mac + paid Apple dev account)
flutter build ipa --release
```
