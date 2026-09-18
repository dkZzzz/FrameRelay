#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UXPLAY_COMMIT="587111368390479b7f65feb881c9257c02e508b5"
UXPLAY_WORKER_PATCH="$PROJECT_ROOT/patches/0001-uxplay-report-embedded-worker-exit.patch"
UXPLAY_AVLAYER_PATCH="$PROJECT_ROOT/patches/0002-uxplay-avlayer-timestamps-and-pause-recovery.patch"
UXPLAY_DIAGNOSTICS_PATCH="$PROJECT_ROOT/patches/0003-uxplay-frame-relay-diagnostics.patch"
UXPLAY_RESUME_PTS_PATCH="$PROJECT_ROOT/patches/0004-uxplay-resume-pts-rebase.patch"
UXPLAY_RESUME_ANCHOR_PATCH="$PROJECT_ROOT/patches/0005-uxplay-resume-display-clock-anchor.patch"
UXPLAY_FORMAT_PATCH="$PROJECT_ROOT/patches/0006-uxplay-format-transition-recovery.patch"
UXPLAY_IMMEDIATE_PATCH="$PROJECT_ROOT/patches/0007-uxplay-live-immediate-display.patch"
UXPLAY_FAST_RESUME_PATCH="$PROJECT_ROOT/patches/0008-uxplay-fast-avlayer-resume.patch"
UXPLAY_AUDIO_PATCH="$PROJECT_ROOT/patches/0009-uxplay-audio-live-clock.patch"
UXPLAY_AVLAYER_WATCHDOG_PATCH="$PROJECT_ROOT/patches/0010-uxplay-avlayer-ready-watchdog.patch"
UXPLAY_DISCONNECT_PATCH="$PROJECT_ROOT/patches/0011-uxplay-rebuild-video-on-disconnect.patch"
BREW_PREFIX="$(brew --prefix)"

cd "$PROJECT_ROOT"

if [[ ! -f third_party/uxplay/CMakeLists.txt ]]; then
    echo "UxPlay submodule is not initialized. Run Scripts/bootstrap.sh first." >&2
    exit 1
fi

actual_commit="$(git -C third_party/uxplay rev-parse HEAD)"
if [[ "$actual_commit" != "$UXPLAY_COMMIT" ]]; then
    echo "UxPlay commit mismatch: $actual_commit" >&2
    exit 1
fi

patch_stack_final=false
if grep -q "controlTimebase would conflict with DisplayImmediately" third_party/uxplay/renderers/avsample_sink.m; then
    patch_stack_final=true
fi

if [[ "$patch_stack_final" != true ]] && [[ -f "$UXPLAY_WORKER_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_WORKER_PATCH" >/dev/null 2>&1; then
    git -C third_party/uxplay apply "$UXPLAY_WORKER_PATCH"
fi
if [[ "$patch_stack_final" != true ]] && [[ -f "$UXPLAY_AVLAYER_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_AVLAYER_PATCH" >/dev/null 2>&1; then
    if ! grep -q "CMTimebaseCreateWithMasterClock" third_party/uxplay/renderers/avsample_sink.m; then
        git -C third_party/uxplay apply "$UXPLAY_AVLAYER_PATCH"
    fi
fi
if [[ "$patch_stack_final" != true ]] && [[ -f "$UXPLAY_DIAGNOSTICS_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_DIAGNOSTICS_PATCH" >/dev/null 2>&1; then
    if ! grep -q "FrameRelay diagnostic transport" third_party/uxplay/lib/raop_rtp_mirror.c; then
        git -C third_party/uxplay apply "$UXPLAY_DIAGNOSTICS_PATCH"
    fi
fi
if [[ "$patch_stack_final" != true ]] && [[ -f "$UXPLAY_RESUME_PTS_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_RESUME_PTS_PATCH" >/dev/null 2>&1; then
    if ! grep -q "gst_video_pts_rebase_pending" third_party/uxplay/renderers/video_renderer.c; then
        git -C third_party/uxplay apply "$UXPLAY_RESUME_PTS_PATCH"
    fi
fi
if [[ "$patch_stack_final" != true ]] && [[ -f "$UXPLAY_RESUME_ANCHOR_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_RESUME_ANCHOR_PATCH" >/dev/null 2>&1; then
    if ! grep -q "resume_timebase_anchor_pending" third_party/uxplay/renderers/avsample_sink.m; then
        git -C third_party/uxplay apply "$UXPLAY_RESUME_ANCHOR_PATCH"
    fi
fi
if [[ "$patch_stack_final" != true ]] && [[ -f "$UXPLAY_FORMAT_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_FORMAT_PATCH" >/dev/null 2>&1; then
    if ! grep -q "avlayer_sink_flush_image" third_party/uxplay/renderers/avsample_sink.m; then
        git -C third_party/uxplay apply "$UXPLAY_FORMAT_PATCH"
    fi
fi
if [[ "$patch_stack_final" != true ]] && [[ -f "$UXPLAY_IMMEDIATE_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_IMMEDIATE_PATCH" >/dev/null 2>&1; then
    if ! grep -q "controlTimebase would conflict with DisplayImmediately" third_party/uxplay/renderers/avsample_sink.m; then
        git -C third_party/uxplay apply "$UXPLAY_IMMEDIATE_PATCH"
    fi
fi
if [[ -f "$UXPLAY_FAST_RESUME_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_FAST_RESUME_PATCH" >/dev/null 2>&1; then
    if ! grep -q "resume_started_ns" third_party/uxplay/renderers/avsample_sink.m; then
        git -C third_party/uxplay apply "$UXPLAY_FAST_RESUME_PATCH"
    fi
fi
if [[ -f "$UXPLAY_AUDIO_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_AUDIO_PATCH" >/dev/null 2>&1; then
    if ! grep -q "FrameRelay audio stats" third_party/uxplay/renderers/audio_renderer.c; then
        git -C third_party/uxplay apply "$UXPLAY_AUDIO_PATCH"
    fi
fi
if [[ -f "$UXPLAY_AVLAYER_WATCHDOG_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_AVLAYER_WATCHDOG_PATCH" >/dev/null 2>&1; then
    if ! grep -q "AVLAYER_READY_WATCHDOG_INTERVAL_NS" third_party/uxplay/renderers/avsample_sink.m; then
        git -C third_party/uxplay apply "$UXPLAY_AVLAYER_WATCHDOG_PATCH"
    fi
fi
if [[ -f "$UXPLAY_DISCONNECT_PATCH" ]] && ! git -C third_party/uxplay apply --reverse --check "$UXPLAY_DISCONNECT_PATCH" >/dev/null 2>&1; then
    if ! grep -q "action=disconnect-reset reason=last-client-closed" third_party/uxplay/uxplay.cpp; then
        git -C third_party/uxplay apply "$UXPLAY_DISCONNECT_PATCH"
    fi
fi

mkdir -p build

PKG_CONFIG_PATH_VALUE="$BREW_PREFIX/lib/pkgconfig:$BREW_PREFIX/opt/openssl@3/lib/pkgconfig"
export HOMEBREW_PREFIX="$BREW_PREFIX"
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH_VALUE"

cmake \
    -S third_party/uxplay \
    -B build/uxplay \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_CORE_DLL=ON \
    -DNO_MARCH_NATIVE=ON \
    -DGST_MACOS=1 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0

cmake --build build/uxplay --target uxplay-core
cmake --build build/uxplay --target uxplay

CORE_PATH="$PROJECT_ROOT/build/uxplay/uxplay-core.dylib"
STANDALONE_PATH="$PROJECT_ROOT/build/uxplay/uxplay"

if [[ ! -f "$CORE_PATH" ]]; then
    echo "uxplay-core.dylib was not produced." >&2
    exit 1
fi
if [[ ! -x "$STANDALONE_PATH" ]]; then
    echo "standalone uxplay was not produced." >&2
    exit 1
fi

if ! file "$CORE_PATH" | grep -q 'arm64'; then
    echo "uxplay-core.dylib is not arm64." >&2
    exit 1
fi
if ! file "$STANDALONE_PATH" | grep -q 'arm64'; then
    echo "standalone uxplay is not arm64." >&2
    exit 1
fi

echo "Built: $CORE_PATH"
echo "Built: $STANDALONE_PATH"
