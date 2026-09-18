# FrameRelay execution rules

FrameRelay is a personal-use macOS AirPlay receiver for the iPhone Control Center
Screen Mirroring path. The source of truth for the implementation is in `docs/`.

Before every task, read these files in order:

1. `AGENTS.md`
2. `docs/PLAN.md`
3. `docs/DECISIONS.md`
4. `docs/STATUS.md`
5. `docs/ARCHITECTURE.md`

## Non-negotiable boundaries

- The project root is `/Users/danko/workspace/FrameRelay`.
- Never modify `/Users/danko/workspace/chat` or `TokChan`.
- The host is Swift 6.2/AppKit with the C bridge in `Sources/FrameRelayCoreBridge`.
- Do not replace the AirPlay core with ReplayKit, OBS, QuickTime, a virtual camera,
  a SwiftUI host, a Rust host, or a subprocess architecture.
- Do not use macOS iPhone Mirroring. The required source is iPhone Control Center
  Screen Mirroring, with iPhone touch control remaining on the phone.
- Do not implement audio before the video-only v0.1 acceptance gate passes.
- Do not move the UxPlay submodule away from the pinned commit in
  `docs/UPSTREAM.md`.
- Apply only the patch files explicitly listed in `docs/UPSTREAM.md`; never edit the
  UxPlay checkout with an undocumented local change.
- Do not add a fallback architecture when iOS protocol validation fails. Record the
  blocker in `docs/STATUS.md` and stop at the gate.

## Context-compression protocol

After every implementation phase, update `docs/STATUS.md` and `docs/TESTLOG.md`.
Record the exact command, result, files changed, test evidence, and the next exact
action. Never rely on the chat history as the only memory of a decision.

## Concurrency and lifetime rules

- AppKit objects are main-actor isolated.
- `AirPlayEngine` is the only Swift type allowed to call the C bridge.
- All C bridge calls are serialized inside `AirPlayEngine`.
- Never call `fr_core_stop` directly from the main actor. It joins the AirPlay
  worker and may block.
- Stop the core and wait for it to return before releasing the host `NSView` or
  the log callback user object.
- The C callback must copy the message immediately and must never touch AppKit.

## Required phase record

After every phase, update `docs/STATUS.md` with the exact current phase, last command,
result, changed files, passed/failed tests, blocker and next exact action. Append a
structured entry to `docs/TESTLOG.md`; a real-device gate may be marked pending, but
must never be reported as passed without the iPhone 15 Pro Max on iOS 26.5.

The fixed build order is:

```text
Scripts/bootstrap.sh
Scripts/build-core.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
Scripts/build-app.sh
Scripts/bundle-gstreamer.sh
Scripts/verify-bundle.sh
Scripts/package-dmg.sh
```

The final release is not complete until the two artifacts in `dist/` pass static
verification and the real-device/douyin acceptance fields in `docs/TESTLOG.md` are
filled with observed results.

## Completion rule

Do not mark v0.1 complete unless the real iPhone 15 Pro Max on iOS 26.5 can find
FrameRelay, mirror a game into its independent window, and remain usable through
the complete Douyin Window Capture workflow described in `docs/OPERATIONS.md`.
