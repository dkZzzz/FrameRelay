#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXECUTABLE="$PROJECT_ROOT/dist/FrameRelay.app/Contents/MacOS/FrameRelay"
ITERATIONS="${1:-20}"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-6}"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "Missing executable: $APP_EXECUTABLE" >&2
    exit 1
fi

for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
    log_path="$PROJECT_ROOT/build/restart-loop-$iteration.log"
    runtime_log="$HOME/Library/Logs/FrameRelay/FrameRelay.log"
    before_log_lines=0
    if [[ -f "$runtime_log" ]]; then
        before_log_lines="$(wc -l < "$runtime_log" | tr -d ' ')"
    fi
    "$APP_EXECUTABLE" >"$log_path" 2>&1 &
    process_id=$!
    trap 'kill -TERM "$process_id" 2>/dev/null || true; wait "$process_id" 2>/dev/null || true' EXIT
    sleep "$STARTUP_WAIT_SECONDS"
    new_runtime_log=""
    if [[ -f "$runtime_log" ]]; then
        new_runtime_log="$(tail -n +$((before_log_lines + 1)) "$runtime_log" 2>/dev/null || true)"
    fi
    if printf '%s\n%s\n' "$(cat "$log_path")" "$new_runtime_log" | grep -Eiq 'required gstreamer plugin|error initialising|worker exited unexpectedly|fatal'; then
        echo "FrameRelay reported a startup failure during loop $iteration/$ITERATIONS:" >&2
        tail -n 40 "$log_path" >&2
        printf '%s\n' "$new_runtime_log" | tail -n 40 >&2
        kill -TERM "$process_id" 2>/dev/null || true
        wait "$process_id" 2>/dev/null || true
        trap - EXIT
        exit 1
    fi
    kill -TERM "$process_id" 2>/dev/null || true
    wait "$process_id" 2>/dev/null || true
    trap - EXIT
    echo "restart loop $iteration/$ITERATIONS passed"
done
