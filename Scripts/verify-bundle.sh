#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$PROJECT_ROOT/dist/FrameRelay.app"
CONTENTS_PATH="$APP_PATH/Contents"

cd "$PROJECT_ROOT"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing app bundle: $APP_PATH" >&2
    exit 1
fi

plutil -lint "$CONTENTS_PATH/Info.plist"
[[ "$(plutil -extract CFBundleExecutable raw -o - "$CONTENTS_PATH/Info.plist")" == "FrameRelay" ]]
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$CONTENTS_PATH/Info.plist")" == "com.framerelay.FrameRelay" ]]
[[ "$(plutil -extract CFBundleName raw -o - "$CONTENTS_PATH/Info.plist")" == "FrameRelay" ]]
[[ "$(plutil -extract CFBundlePackageType raw -o - "$CONTENTS_PATH/Info.plist")" == "APPL" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw -o - "$CONTENTS_PATH/Info.plist")" == "26.0" ]]
ui_element="$(plutil -extract LSUIElement raw -o - "$CONTENTS_PATH/Info.plist" 2>/dev/null || true)"
[[ -z "$ui_element" || "$ui_element" == "false" ]]
[[ "$(plutil -extract FRCoreCommit raw -o - "$CONTENTS_PATH/Info.plist")" == "587111368390479b7f65feb881c9257c02e508b5" ]]
[[ "$(plutil -extract FRGStreamerVersion raw -o - "$CONTENTS_PATH/Info.plist")" == "1.28.7" ]]
[[ "$(plutil -extract NSLocalNetworkUsageDescription raw -o - "$CONTENTS_PATH/Info.plist")" == *"本地网络"* ]]
plutil -p "$CONTENTS_PATH/Info.plist" | grep -Fq '_airplay._tcp'
plutil -p "$CONTENTS_PATH/Info.plist" | grep -Fq '_raop._tcp'
[[ -x "$CONTENTS_PATH/MacOS/FrameRelay" ]]
[[ -f "$CONTENTS_PATH/Frameworks/uxplay-core.dylib" ]]
[[ -d "$CONTENTS_PATH/Resources/gstreamer-1.0" ]]
[[ -x "$CONTENTS_PATH/Resources/gstreamer-1.0/gst-plugin-scanner" ]]
[[ ! -s "$CONTENTS_PATH/Resources/FrameRelay.uxplayrc" ]]

while IFS= read -r -d '' file_path; do
    if file "$file_path" | grep -q 'Mach-O'; then
        architectures="$(lipo -archs "$file_path")"
        if [[ "$architectures" != "arm64" ]]; then
            echo "Non-arm64-only binary: $file_path ($architectures)" >&2
            exit 1
        fi
    fi
done < <(find "$APP_PATH" -type f -print0)

while IFS= read -r -d '' file_path; do
    if file "$file_path" | grep -q 'Mach-O'; then
        dependencies="$(otool -L "$file_path" | awk 'NR > 1 { print $1 }')"
        if printf '%s\n' "$dependencies" | grep -E '/opt/homebrew|/usr/local|/Users/danko/workspace/FrameRelay/build' >/dev/null; then
            echo "Unbundled absolute dependency in $file_path" >&2
            printf '%s\n' "$dependencies" >&2
            exit 1
        fi
    fi
done < <(find "$APP_PATH" -type f -print0)

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Bundle verification passed: $APP_PATH"
