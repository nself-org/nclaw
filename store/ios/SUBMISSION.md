# App Store Submission — ɳClaw iOS

## [USER-ACTION] — UA-13

Apple Developer account credentials are required to complete submission:
- `APPLE_TEAM_ID` — Apple Developer Team ID
- `APP_STORE_CONNECT_API_KEY_ID` — App Store Connect API Key ID
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID` — Issuer ID
- `APP_STORE_CONNECT_API_KEY_P8` — Private key content (base64)

These are currently commented out in `~/.claude/vault.env`. See UA-04 in USER-ACTION-QUEUE.

## Build and Submit

```bash
cd mobile
flutter build ipa --release --export-options-plist ios/ExportOptions.plist
xcrun altool --upload-app -f build/ios/ipa/*.ipa \
  --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_API_KEY_ISSUER_ID"
```

Or use Fastlane deliver (preferred):
```bash
bundle exec fastlane deliver
```

## App Store Connect

- App Name: ɳClaw — AI Personal Assistant
- Bundle ID: org.nself.nclaw
- Primary Category: Productivity
- Secondary Category: Utilities
- Age Rating: 4+
- Price: Free (in-app: ɳClaw Bundle $0.99/mo or ɳSelf+ $3.99/mo)

## Review Information

- Backend: nSelf open-source (https://github.com/nself-org/cli)
- Requires nSelf backend URL configured in app settings
- Demo backend available at claw.nself.org for review team
