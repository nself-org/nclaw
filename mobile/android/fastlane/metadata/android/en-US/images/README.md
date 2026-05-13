# Google Play Images

Required:
- `icon.png` — 512x512
- `featureGraphic.png` — 1024x500

Screenshots (place under `images/phoneScreenshots/`):
- 2 to 8 PNG or JPG, 16:9 or 9:16 ratio
- Min 320px, max 3840px per side

Optional tablets:
- `images/sevenInchScreenshots/` — 7" tablets
- `images/tenInchScreenshots/` — 10" tablets
- `images/tvScreenshots/` — Android TV (not applicable for ɳClaw)
- `images/wearScreenshots/` — Wear OS (not applicable)

Generate via `flutter drive --target=test_driver/screenshots.dart`
or by hand on a real device / emulator.
