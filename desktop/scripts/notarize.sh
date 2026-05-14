#!/usr/bin/env bash
set -euo pipefail

DMG="${1:?DMG path required}"

echo "Notarizing: $DMG"

xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_NOTARIZATION_APPLE_ID" \
  --password "$APPLE_NOTARIZATION_PASSWORD" \
  --team-id "$APPLE_DEVELOPER_TEAM_ID" \
  --wait --timeout 30m

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "Notarization complete: $DMG"
