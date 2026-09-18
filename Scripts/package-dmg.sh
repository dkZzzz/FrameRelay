#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$PROJECT_ROOT/dist/FrameRelay.app"
DMG_PATH="$PROJECT_ROOT/dist/FrameRelay-0.1.0-arm64.dmg"

cd "$PROJECT_ROOT"

"$PROJECT_ROOT/Scripts/verify-bundle.sh"
rm -f "$DMG_PATH"

hdiutil create \
    -volname FrameRelay \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "Created: $DMG_PATH"
