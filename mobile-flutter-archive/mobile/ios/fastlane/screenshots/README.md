# iOS Screenshots

App Store Connect requires screenshots for these device sizes:

| Required | Device | Resolution |
|---|---|---|
| Yes | 6.7" iPhone (Pro Max) | 1290x2796 |
| Yes | 6.5" iPhone (XS Max / 11 Pro Max) | 1284x2778 or 1242x2688 |
| Yes | 5.5" iPhone (8 Plus / fallback) | 1242x2208 |
| Optional | 12.9" iPad Pro (3rd gen+) | 2048x2732 |

File naming convention (fastlane deliver auto-picks up):

`<locale>/<device>_<index>_<name>.png`

Example: `en-US/iPhone_6.7_01_chat.png`

### Capture list (min 3, max 10 per device)

1. Chat screen with a topic branching
2. Memory explorer — knowledge graph view
3. Topic list / sidebar
4. Voice conversation view
5. Daily digest view
6. Quick capture modal
7. Widget preview on home screen

Generate with `flutter drive --target=test_driver/screenshots.dart`
or by hand via the iOS Simulator (`Cmd+S`).
