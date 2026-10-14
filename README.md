# የኢትዮጵያ ዳማ Pro — Ethiopian Dama Pro

[Amharic] ባህላዊውና የተወደደው የኢትዮጵያ ዳማ (ጠጠር) ጨዋታ — በFlutter ተሰራ፣ በአርቴፊሻል ኢንተለጀንስ የተጎላበተ፣ ከይፉታ (huffing) ስርዓት ጋር።

[English] The classic Ethiopian checkers game — built with Flutter, powered by a Grandmaster-level AI, featuring the authentic **Yifuta** (huffing) rule, pass-and-play, and offline hotspot multiplayer. No internet required.

## ✨ ግብረ ባህሪያት / Features

- 🎯 **Complete Ethiopian Dama rules** — 8×8 board, flying kings (ንጉሥ), mandatory multi-capture chains, mid-capture promotion
- 🔥 **Yifuta (ይፉታ) system** — traditional huffing (burn / force re-capture / let it go) or strict forced-capture mode
- 🦉 **“የዳማ አውራ” AI engine** — Minimax + alpha-beta pruning running in an Isolate (60 FPS UI): ጀማሪ / መካከለኛ / የዳማ አውራ (depth 7–8)
- 👥 **Pass & Play** — two players on one phone with board flipping
- 📡 **Hotspot LAN multiplayer** — pure `dart:io` TCP on port 4545, zero online dependencies; host shows its 192.168.x.x IP, friend joins
- 🇪🇹 **አማርኛ + English** — full bilingual interface (Amharic default)
- 🎨 Wooden board, 3D pieces, gold crowns, haptic feedback

## 📱 Getting the APK

This repository contains **pure Dart sources only** — no binary Gradle wrapper is committed. GitHub Actions builds the Android shell with `flutter create` on every push:

1. Open the **Actions** tab → latest **Build Ethiopian Dama APK** run
2. Download the `ethiopian-dama-pro-release-apk` artifact
3. Unzip and install `app-release.apk` on your Android phone (allow “install from unknown sources”)

Or trigger a build manually: **Actions → Build Ethiopian Dama APK → Run workflow**.

## 🔨 Building locally

```bash
flutter create --org com.henok.dama --project-name ethiopian_dama --platforms android .
flutter pub get
flutter run            # or: flutter build apk --release
```

## 🧠 AI details

| Level | Depth | Extras |
|-------|-------|--------|
| ጀማሪ (Beginner) | 2 | random blunders, eval noise |
| መካከለኛ (Medium) | 4 | quiescence search |
| የዳማ አውራ (Master) | 7 (8 in endgames) | full move ordering, time-capped iterative deepening |

Evaluation: material (ተራ 100 / ንጉሥ 350), diagonals +20, center +12, back-row defense +18, advancement +4/row, mobility +5/move. The AI even decides Yifuta disputes with a depth-4 minimax on both branches.

## 📄 License

Free for personal use. ለግል አገልግሎት በነፃ ይጠቀሙ!
