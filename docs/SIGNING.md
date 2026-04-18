# ɳClaw — Code Signing & Distribution Guide

Source-of-truth for all signing material, App Store / Play Store enrollment,
and release workflow for the `nself-org/claw` repo. This document never
contains actual keys — only key IDs, vault variable names, and workflow.

---

## 1. Vault variables

All secrets live in `~/.claude/vault.env`. CI pulls from the corresponding
GitHub Actions Secrets (same names).

### iOS / macOS (Apple)

| Vault var | Purpose |
|---|---|
| `APPLE_TEAM_ID` | 10-char team identifier (used in entitlements + AASA) |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID for the API key |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Base64-encoded `.p8` key |
| `MATCH_PASSWORD` | fastlane match decrypt password |
| `MATCH_GIT_URL` | Private git repo hosting encrypted certs |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Base64 `user:pat` for the match repo |
| `APPLE_ID_EMAIL` | Apple ID used for notarization + altool |
| `APPLE_ID_APP_SPECIFIC_PASSWORD` | App-specific password for `notarytool` |
| `MACOS_DEVELOPER_ID_APPLICATION_CERT` | Developer ID Application cert (base64 .p12) |
| `MACOS_DEVELOPER_ID_INSTALLER_CERT` | Developer ID Installer cert (base64 .p12) |

### Android (Google Play)

| Vault var | Purpose |
|---|---|
| `ANDROID_KEYSTORE_PATH` | Absolute path to release keystore on dev machine |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded keystore for CI |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias inside the keystore |
| `ANDROID_KEY_PASSWORD` | Key password |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google Play Console service account JSON (base64) |
| `ANDROID_PACKAGE_NAME` | `com.nself.claw` |

Never commit these values. Never paste them in PR descriptions, chat, or
build logs. If a value leaks, rotate immediately using the procedures in
[Rotation](#6-rotation).

---

## 2. iOS / macOS signing

### 2.1 Bundle identifiers

| Target | Identifier |
|---|---|
| iOS app (`Runner`) | `com.nself.claw` |
| Notification Service Extension | `com.nself.claw.NotificationService` |
| Share Extension | `com.nself.claw.ShareExtension` |
| Home Screen Widget | `com.nself.claw.ClawWidget` |
| macOS app | `com.nself.claw` |

All extensions inherit the parent team ID and must be signed with matching
provisioning profiles.

### 2.2 Certificates & provisioning profiles

Managed by **fastlane match** (repo: the private `MATCH_GIT_URL` repo).
Four profile types are maintained:

- `development` — local simulator + on-device debug builds
- `adhoc` — internal TestFlight-alternative distribution
- `appstore` — App Store Connect submissions
- `developer_id` — macOS DMG signing outside the Mac App Store

Developer workflow:

```bash
cd app/ios
bundle exec fastlane match development --readonly
bundle exec fastlane match appstore --readonly
```

CI workflow pulls readonly and archives:

```bash
bundle exec fastlane beta    # TestFlight
bundle exec fastlane release # App Store
```

### 2.3 Push (APNs)

Two entitlements files live at `app/ios/Runner/`:

- `Runner.entitlements` — Debug (`aps-environment=development`)
- `RunnerRelease.entitlements` — Release (`aps-environment=production`)

Xcode picks the correct file per build configuration. The
`Runner.xcodeproj/project.pbxproj` target must set `CODE_SIGN_ENTITLEMENTS`
to `Runner/Runner.entitlements` for Debug and
`Runner/RunnerRelease.entitlements` for Release.

The Notification Service Extension (`app/ios/NotificationService/`) inherits
APNs from the host app — it does not need its own `aps-environment` key.

### 2.4 Universal Links (iOS)

Hosted file: `https://claw.nself.org/.well-known/apple-app-site-association`

Template: `app/ios/apple-app-site-association-template.json`. Before deploy:

1. Replace `REPLACE_TEAM_ID` with the value of `APPLE_TEAM_ID`
2. Upload to `web/claw/public/.well-known/apple-app-site-association`
3. Serve it with `Content-Type: application/json` and no redirects
4. Verify with: `curl -I https://claw.nself.org/.well-known/apple-app-site-association`

Associated Domain entry (`applinks:claw.nself.org`) lives in both entitlements
files.

### 2.5 macOS notarization

Release DMG:

```bash
bash scripts/build-dmg.sh
bash scripts/codesign-macos.sh    # Developer ID Application
bash scripts/notarize-macos.sh    # xcrun notarytool submit --wait
```

Notarization can take 5–30 minutes. The build isn't shippable until
`notarytool info <submission-id>` reports `Accepted` and the DMG is
stapled with `xcrun stapler staple <dmg>`.

---

## 3. Android signing

### 3.1 Release keystore

One keystore per repo, stored **outside** the tree. Developer machines
keep it at `~/Library/nself-keystores/claw-release.jks` (macOS) or
`~/.nself-keystores/claw-release.jks` (Linux).

Gradle reads keystore config from `android/key.properties`, which is
`.gitignore`d. Template at `android/key.properties.template`.

```properties
storeFile=/absolute/path/to/claw-release.jks
storePassword=<from vault ANDROID_KEYSTORE_PASSWORD>
keyAlias=<from vault ANDROID_KEY_ALIAS>
keyPassword=<from vault ANDROID_KEY_PASSWORD>
```

CI injects the keystore from `ANDROID_KEYSTORE_BASE64` at the start of each
build and writes `key.properties` from Actions Secrets. Never commit either.

### 3.2 Google Play Console

Service account JSON (`PLAY_SERVICE_ACCOUNT_JSON`) has the roles:

- `Release manager`
- `View app information and download bulk reports`

Upload via fastlane supply:

```bash
cd app/android
bundle exec fastlane supply --aab app-release.aab \
  --track internal \
  --json_key_data "$PLAY_SERVICE_ACCOUNT_JSON"
```

### 3.3 App Links (Android)

Hosted file: `https://claw.nself.org/.well-known/assetlinks.json`

Template: `app/android/app/src/main/assetlinks-template.json`. Before deploy:

1. Get the SHA-256 fingerprint of the release keystore:
   ```bash
   keytool -list -v -keystore "$ANDROID_KEYSTORE_PATH" \
     -alias "$ANDROID_KEY_ALIAS" -storepass "$ANDROID_KEYSTORE_PASSWORD" \
     | grep SHA256 | head -1 | awk '{print $2}'
   ```
2. Replace `REPLACE_WITH_RELEASE_KEYSTORE_SHA256_FINGERPRINT` with that
   value
3. Upload to `web/claw/public/.well-known/assetlinks.json`
4. Serve with `Content-Type: application/json`
5. Verify with the Google Digital Asset Links API:
   ```bash
   curl -s 'https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://claw.nself.org&relation=delegate_permission/common.handle_all_urls'
   ```

If Google Play App Signing is enabled, use **both** the upload key SHA-256
and the Play-managed app signing key SHA-256 in `assetlinks.json`.

---

## 4. Release workflow

1. Version bump in `app/pubspec.yaml` — requires an approved release plan
   (see GCI Version & Release Lock)
2. Tag: `git tag -a v<version> -m "Release <version>"`
3. CI workflow `release-mobile.yml`:
   - iOS: fastlane `release` → App Store Connect
   - Android: fastlane `supply` → Play Console `internal` track
   - macOS: `build-dmg` → `codesign` → `notarize` → GitHub Release asset
4. Staged rollout on Play (5% → 20% → 50% → 100% over 4 days)
5. App Store Connect — submit for review after TestFlight soak

---

## 5. Emergency hotfix path

1. Branch off `main` as `hotfix/<issue>`
2. Bump the patch version (e.g. 1.1.1 → 1.1.2)
3. Open PR — CR + QA mandatory even for hotfix
4. After merge: re-run the full release workflow; the staged rollout halves
   the cadence (5% → 50% → 100% over 1 day)

---

## 6. Rotation

If any vault variable leaks:

| Variable | Rotation procedure |
|---|---|
| Apple cert / provisioning profile | `fastlane match nuke development` (or target type) then `fastlane match <type>` to regenerate |
| App Store Connect API key | Revoke in App Store Connect → Users → Keys; generate new; update vault |
| Android keystore | **Catastrophic** — cannot rotate without new package name. Protect the keystore like root CA private key |
| Android upload key (with Play App Signing) | Generate new upload key, contact Play support to register it |
| Play service account | Recreate in Google Cloud console → IAM → Service accounts → Keys |

Keystore rotation is impossible for any shipped app version — this is why
the keystore is the single most sensitive file in the repo's signing
surface. Back it up in at least two geographically separate encrypted
stores.

---

## 7. Local test checklist

Before opening a release PR, run:

```bash
# Flutter
cd app
flutter clean
flutter pub get
flutter analyze
flutter test

# iOS build (Release)
flutter build ios --release --no-codesign

# Android AAB (Release)
flutter build appbundle --release

# macOS
flutter build macos --release
```

CI runs the same sequence plus code signing + store upload.
