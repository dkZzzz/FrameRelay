#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

if [[ ! -f build/uxplay/uxplay-core.dylib ]]; then
    "$PROJECT_ROOT/Scripts/build-core.sh"
fi

swift build -c release --arch arm64
SWIFT_BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)"

APP_PATH="$PROJECT_ROOT/dist/FrameRelay.app"
CONTENTS_PATH="$APP_PATH/Contents"

rm -rf "$APP_PATH"
mkdir -p \
    "$CONTENTS_PATH/MacOS" \
    "$CONTENTS_PATH/Frameworks" \
    "$CONTENTS_PATH/Resources/LICENSES"

cp "$SWIFT_BIN_PATH/FrameRelay" "$CONTENTS_PATH/MacOS/FrameRelay"
cp build/uxplay/uxplay-core.dylib "$CONTENTS_PATH/Frameworks/uxplay-core.dylib"
cp Resources/Info.plist "$CONTENTS_PATH/Info.plist"
cp Resources/FrameRelay.uxplayrc "$CONTENTS_PATH/Resources/FrameRelay.uxplayrc"
cp LICENSE "$CONTENTS_PATH/Resources/LICENSES/GPL-3.0-or-later.txt"
cp NOTICE "$CONTENTS_PATH/Resources/LICENSES/NOTICE.txt"

if [[ -d Resources/LICENSES ]]; then
    find Resources/LICENSES -maxdepth 1 -type f -exec cp {} "$CONTENTS_PATH/Resources/LICENSES/" \;
fi

chmod 755 "$CONTENTS_PATH/MacOS/FrameRelay"

echo "Built unsigned app bundle: $APP_PATH"
echo "Next exact action: Scripts/bundle-gstreamer.sh"
