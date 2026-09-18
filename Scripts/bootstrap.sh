#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UXPLAY_COMMIT="587111368390479b7f65feb881c9257c02e508b5"

cd "$PROJECT_ROOT"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "FrameRelay requires an arm64 Mac." >&2
    exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "FrameRelay requires macOS." >&2
    exit 1
fi

for required in brew git swift; do
    if ! command -v "$required" >/dev/null 2>&1; then
        echo "Missing required command: $required" >&2
        exit 1
    fi
done

brew install \
    cmake \
    ninja \
    pkg-config \
    gstreamer \
    gst-plugins-base \
    gst-plugins-good \
    gst-plugins-bad \
    gst-libav \
    libplist \
    openssl@3

git submodule update --init --recursive
git -C third_party/uxplay fetch --quiet origin popyachsa-integration
git -C third_party/uxplay checkout --detach "$UXPLAY_COMMIT"

actual_commit="$(git -C third_party/uxplay rev-parse HEAD)"
if [[ "$actual_commit" != "$UXPLAY_COMMIT" ]]; then
    echo "UxPlay commit mismatch: $actual_commit" >&2
    exit 1
fi

echo "FrameRelay bootstrap complete."
echo "UxPlay: $actual_commit"
echo "Homebrew prefix: $(brew --prefix)"
