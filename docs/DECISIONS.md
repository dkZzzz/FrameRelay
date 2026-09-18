# Locked decisions

| Decision | Value |
|---|---|
| Project root | `/Users/danko/workspace/FrameRelay` |
| Host | Swift 6.2 + AppKit |
| UI toolkit | AppKit, no SwiftUI |
| C bridge | Pure C `dlopen`/`dlsym` bridge |
| AirPlay engine | Popyachsa/UxPlay `uxplay-core` |
| Engine branch | `popyachsa-integration` |
| Engine commit | `587111368390479b7f65feb881c9257c02e508b5` |
| Render sink | `avlayer` and `AVSampleBufferDisplayLayer` |
| Window source | iPhone Control Center Screen Mirroring |
| Douyin source | Window Capture |
| Audio | Enabled with `-as osxaudiosink`; output to the Mac default device |
| Microphone | Direct Mac microphone in Douyin |
| Architecture | In-process dylib, not subprocess |
| Runtime dependencies | Bundled into the App |
| CPU | arm64-only |
| App identity | `com.framerelay.FrameRelay` |
| AirPlay name | `FrameRelay` |
| Port policy | UxPlay custom fixed port group via `-p 47000` |
| Host prerequisite | macOS built-in AirPlay Receiver may remain on; TCP/UDP 47000–47002 must be available and allowed by the firewall |
| Codec policy | UxPlay `decodebin`; no forced decoder name |
| Release signing | ad-hoc |
| Distribution | local `.app` and `.dmg` |

## Temporary diagnostic exception

The normal launch path remains the locked v0.1 option string. For the current frame-rate
root-cause investigation only, the executable accepts three explicit command-line profiles:

```text
--diagnostic-1080p: normal 1920x1080 options plus -FPSdata
--diagnostic-720p: 1280x720 options plus -FPSdata
--diagnostic-1080p-nosync: normal 1920x1080 options plus -vsync no and -FPSdata
```

These profiles are not a replacement architecture, are not the release default, and must
not be used to claim that the final 1080p path has changed. The no-sync profile exists only
to compare the
iPhone/AirPlay client report with FrameRelay's pulled/enqueued/drop counters under the same
network conditions and to isolate timestamp pacing from the sender's negotiated FPS.

## Diagnostic implementation lock

The current root-cause pass is measurement-only. It is fixed to the following design:

- The existing `-FPSdata` opt-in flag is the only diagnostic gate; normal startup does not
  enable the new counters.
- Measurements stay in the pinned UxPlay C/Objective-C hot path and are aggregated once per
  second. Swift receives only the resulting log strings through the existing callback.
- The diagnostic patch must not change the normal launch options, fixed port group, audio
  policy, default timestamp sync, window behavior, decoder policy, or `-fps 60` request.
- The diagnostic patch must report transport, `video_process`, `gst_app_src_push_buffer`,
  actual decoder/caps, GStreamer queue/appsink levels, AVSampleBufferDisplayLayer enqueue
  work, and pause/resume marker recovery before any performance optimization is selected.
- The next optimization phase may begin only after a real iPhone 15 Pro Max / iOS 26.5
  diagnostic log has been collected and interpreted. No `-fps 120` experiment is part of
  this phase.

This section records the earlier measurement-only Phase 3A contract. Phase 3E is the later
optimization decision made from that measurement: it leaves the formal command-line options
unchanged but supersedes timestamp scheduling inside the custom live AVLayer branch only.

## Phase 3B pause/resume recovery lock

The lock-screen recovery fix is fixed to a one-shot media-time rebase in the pinned UxPlay
video renderer. When the AVSampleBufferDisplayLayer is resumed, the renderer arms
`gst_video_pts_rebase_pending`. The first valid post-resume raw NTP timestamp becomes the
new `gst_video_pts_rebase_origin`; all subsequent buffers use `raw_pts - origin` until the
next AirPlay session or resume marker. A backwards sender-clock jump starts a fresh origin
at zero instead of allowing timestamp underflow. The normal port, `-fps 60`, resolution,
decoder, audio, window, and synchronization options remain unchanged.

The implementation must remain in the UxPlay C video hot path and must not create a Swift
Task per frame. Diagnostic profiles may write the low-frequency markers
`FrameRelay diagnostic pts: action=resume-rebase-pending`,
`FrameRelay diagnostic pts: action=resume-rebase`, and
`FrameRelay diagnostic pts: action=resume-rebase-reset`. The Swift host writes a matching
`FrameRelay diagnostic host: videoStarted ... applied=...` line after applying each geometry
event, so the core geometry and AppKit window response can be compared in one log.

## Phase 3C resume display-clock anchor lock

The first real-device regression showed that the Phase 3B PTS rebase alone was not sufficient.
After a rapid lock/wake cycle, the first decoded frame could arrive roughly 756 ms after the
resume marker while the AVSampleBufferDisplayLayer still reported `readyForMoreMediaData = NO`.
Transport, decoder, PixelBuffer creation, and frame-copy counters showed that the input path was
healthy; the displayed portrait passcode frame was simply the last sample accepted before the
display queue became back-pressured, while the later landscape geometry correctly resized the
window.

The fixed Phase 3C repair is therefore:

- `avlayer_sink_pause` and `avlayer_sink_resume` arm an atomic
  `resume_timebase_anchor_pending` flag and a one-shot `resume_seed_pending` flag;
- resume leaves the display CMTimebase stopped at zero instead of starting it at the resume
  marker;
- the first post-resume decoded sample atomically anchors the CMTimebase to its own PTS and
  starts the clock at that sample's arrival, so a delayed first frame is not already late;
- exactly one post-resume sample may pass through the AVLayer readiness gate even if the layer
  temporarily reports not-ready; if Core Media sample construction fails, the one-shot permit is
  restored for the next frame;
- normal playback keeps the existing bounded, low-latency readiness gate and does not enqueue an
  unbounded backlog.

This repair is contained in `patches/0005-uxplay-resume-display-clock-anchor.patch`, is replayed
after patches 0001–0004 by `Scripts/build-core.sh`, and does not change the AirPlay protocol,
fixed port, 1080p target, `-fps 60`, decoder, audio policy, or window architecture. The real
device lock/wake/unlock regression must pass before Phase 3C can be marked complete.

## Phase 3D live video-format transition lock

The 03:52 real-device regression proved that the Phase 3C transport, decode, enqueue and
display-clock path could be healthy while the window still showed the portrait lock-screen
image after a later landscape `videoStarted` event. The fixed Phase 3D decision is therefore:

- Apply `patches/0006-uxplay-format-transition-recovery.patch` after 0001–0005.
- When `videoflip` changes method, negotiated width, or negotiated height, set the new
  `video-direction` first, then call `avlayer_sink_flush_image` to remove the old AVLayer image
  and queued samples.
- Preserve the running CMTimebase and the already-rebased PTS during a format-only transition;
  a rotation/size change is not a pause and must not introduce a second clock reset.
- Arm exactly one `resume_seed_pending` after the flush. The next successfully created sample may
  seed the new format; normal `readyForMoreMediaData` gating and bounded dropping remain active.
- Record the actual appsink output dimensions and the number of format flushes only in the
  existing opt-in diagnostic path. No per-frame Swift work or AppKit call is added.
- Keep normal options, port group, 1080p target, `-fps 60`, default timestamp sync, decoder,
  audio policy, AppKit window and in-process core unchanged.

Phase 3D is not complete from a successful build alone. It requires a real iPhone 15 Pro Max /
iOS 26.5 lock-wake-unlock test showing a post-transition landscape sample replacing the
portrait lock-screen image. If the actual output dimensions do not switch, or dimensions switch
but the layer remains visually stale, preserve the diagnostic interval and stop for evidence;
do not change the route or try `-fps 120`.

## Phase 3E live AVLayer immediate-presentation lock

The Phase 3D real-device run at approximately Beijing 04:40 showed a more specific failure:
the transport, decoder, appsink and sample-construction path continued at roughly 57–65 FPS;
the portrait-to-landscape format transitions were observed and `ready_rejects` stayed at zero;
yet the user-visible image remained frozen at the first frame of the lock-screen or unlocked
game stream. This evidence rules out the earlier hypotheses of a missing frame, a format
negotiation failure, or an AVLayer readiness backlog as the primary cause. The remaining
timestamp-driven presentation path was therefore the fixed point of this phase.

The locked Phase 3E decision is:

- Apply `patches/0007-uxplay-live-immediate-display.patch` after 0001–0006.
- In the custom live `avlayer` sink, remove the `CMTimebase` field, creation, binding and
  resume anchor. Do not pass sender PTS/duration into `CMSampleTimingInfo`; use invalid timing
  fields and set `kCMSampleAttachmentKey_DisplayImmediately` on every accepted sample.
- In the custom live branch of `video_renderer.c`, keep the appsink `sync=false` and set the
  internal `vsync_prop=false`, so the live appsrc does not attach GStreamer PTS to the path.
  This is an internal live-sink decision; the locked command-line options and AirPlay protocol
  remain unchanged. Generic timestamped sinks retain their existing timestamp behavior.
- Keep the bounded appsink/AVLayer queue, `readyForMoreMediaData` gate, pause/format flush,
  one-shot seed, and diagnostics. `output_fps` remains an enqueue counter, not a physical
  display-vsync measurement.
- Do not add `-fps 120`, do not force a decoder, and do not replace the AirPlay receiver route.
  The purpose is to prevent a stale or discontinuous sender timestamp from stopping a live
  frame that has already arrived, not to claim that the iPhone sends more than 60 FPS.
- Make `Scripts/build-core.sh` recognize the final 0007 source state before replaying older
  patches, so repeated builds from the same working tree are idempotent. A fresh replay from
  the pinned SHA must still apply 0001–0007 in order and produce byte-equivalent source.

Phase 3E local acceptance requires the pinned core, arm64 App, bundled GStreamer runtime,
ad-hoc signature, DMG and clean-environment start/stop checks to pass. Real-device acceptance
requires the landscape game → lock → wake without unlock and lock-screen interaction → unlock
back to landscape game sequence to keep changing in the FrameRelay window. It must not remain
on the first wake or first post-unlock frame, and the result must be recorded with the Beijing
time interval. Until that test passes, the release remains incomplete.

## Phase 3F AirPlay wake-gap attribution and fast AVLayer resume

The Phase 3E diagnostic log showed that the apparent 0.7–1.6 second “wake recovery” was
measured from the pause marker, not from the resume marker. In the representative longest
interval, `0x56` pause to `0x16` resume was about 1.510 seconds, the largest video arrival gap
was about 1.661 seconds, and the first accepted frame was only about 0.115 seconds after the
resume marker. Transport, decoder, sample construction and enqueue had no failures. The primary
gap is therefore the iPhone/AirPlay sender's sleep interval; the receiver cannot decode a frame
that was not sent.

The fixed Phase 3F repair is:

- Apply `patches/0008-uxplay-fast-avlayer-resume.patch` after 0001–0007.
- Apply `patches/0009-uxplay-audio-live-clock.patch` after 0001–0008. AAC mirror audio is
  arrival-paced (`sync=false`) because the AirPlay/NTP clock domain can precede a newly-created
  GStreamer appsrc base time after reconnect; repeated audio format starts restart the selected
  pipeline, while ALAC timestamp synchronization remains unchanged.
- Record `resume_recovery` from the resume marker to the first accepted AVLayer sample, using
  a dedicated `resume_started_ns`; do not report the preceding phone sleep interval as local
  renderer recovery.
- In the custom live AVLayer branch, do not synchronously wait up to 100 ms for the GStreamer
  `PAUSED -> PLAYING` state transition after `gst_element_set_state`. The pipeline transition
  remains asynchronous and the next appsrc buffer completes it; timestamped/non-AVLayer paths
  retain the existing bounded state wait.
- Keep the existing pause flush, format flush, seed permit, no-PTS `DisplayImmediately` path,
  fixed options and protocol unchanged. Do not retain a stale locked-screen frame merely to
  hide the sender-side gap.

Phase 3F can reduce receiver-side tail latency but cannot remove the iPhone-side no-packet
interval. Real-device acceptance must report both pause-to-resume duration and resume-to-first-
accepted-frame duration, with transport arrival gaps, so the remaining sender behavior is not
misclassified as an AVLayer regression.

## Phase 3G live AVLayer readiness watchdog lock

The recent real-device freeze showed that transport, GStreamer push/callback and audio could
remain healthy while the live AVLayer returned `readyForMoreMediaData = false` for every frame.
The fixed repair is `patches/0010-uxplay-avlayer-ready-watchdog.patch`, applied after 0001–0009:

- Measure continuous readiness rejection with a monotonic timestamp in the Objective-C sink;
  do not infer the condition from packet loss or run a Swift task per frame.
- After three seconds of continuous ordinary-frame rejection, flush the current AVLayer image
  and queue and arm exactly one seed sample. The bounded gate remains in place for all other
  frames, and at most two watchdog flush attempts are made in one uninterrupted episode.
- If the episode remains stuck after those attempts, emit the precise restart marker
  `FrameRelay avlayer watchdog: action=restart reason=ready-stuck`. Swift schedules a controlled
  restart through the existing fixed backoff policy, with no direct main-actor `fr_core_stop`.
- Record watchdog flushes/escalations in the existing once-per-second diagnostic summary and
  record manual/automatic restart reason plus lifecycle generation in the application log so a
  reconnect cannot be mistaken for a single clean restart.

This repair does not change AirPlay protocol, fixed ports, decoder, audio policy, window
architecture, `-fps 60`, or the bounded live AVLayer queue. Real-device freeze recovery remains
pending until the new bundle is exercised with the iPhone 15 Pro Max / iOS 26.5 and the Douyin
Window Capture workflow.

## Prohibited substitutions

Do not replace the implementation with macOS iPhone Mirroring, ReplayKit, an iPhone
companion app, QuickTime, OBS, ScreenCaptureKit, a virtual camera, SwiftUI, Rust, or
an external UxPlay process.

## Fixed implementation details

These values are part of the interface contract and must not be selected differently by
a later agent:

```text
Project: FrameRelay
Root: /Users/danko/workspace/FrameRelay
Mac: MacBook Pro 2021 / M1 Pro / arm64
macOS: 26.5; deployment target 26.0
iPhone: iPhone 15 Pro Max / iOS 26.5
Swift tools: 6.2
Bundle ID: com.framerelay.FrameRelay
Version: 0.1.0
AirPlay name: FrameRelay
Core repository: https://github.com/Recluse/UxPlay.git
Core branch: popyachsa-integration
Core SHA: 587111368390479b7f65feb881c9257c02e508b5
Core output: uxplay-core.dylib loaded in-process through pure C dlopen/dlsym
Video sink: avlayer -> AVSampleBufferDisplayLayer
Maximum requested video: 1920x1080 / 60 fps
Options: -p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080
Port group: TCP 47000, 47001, 47002; UDP 47000, 47001, 47002
Window: AppKit regular application, standard titled/closable/miniaturizable/resizable window; default content 1280x720, minimum content 320x240; Stage Manager managed
Window capture: Douyin Live Companion Window Capture
Audio: enabled with -as osxaudiosink; Mac default output; no microphone capture
Microphone: direct Mac microphone in Douyin
Runtime: bundled GStreamer, no target Homebrew dependency
Architecture: arm64-only
Signing: ad-hoc
Distribution: FrameRelay.app + FrameRelay-0.1.0-arm64.dmg
```

## Runtime and threading decisions

- `AirPlayEngine` is an actor and the sole Swift caller of the C bridge.
- The actor receives only a `UInt` opaque `NSView` address; it never stores an AppKit
  object.
- The worker callback copies its C string immediately and yields to an AsyncStream.
- AppKit is main-actor isolated. It never synchronously calls `fr_core_stop`.
- The host view remains alive until the actor's stop operation returns.
- Explicit restart suppresses the intermediate `engineStopped` event; user stop still
  emits it.
- Automatic restart uses only 0.5 seconds, 1 second, and 2 seconds, with at most three
  attempts inside 60 seconds. A fourth attempt is never scheduled.
- `Open connections: 0` clears the old frame and returns to waiting. The last-client
  disconnect also stops and rebuilds the live video renderer inside the running UxPlay
  core; it does not restart the whole App or stop/join the HTTP server from its own worker.
- The formal command-line options still request the UxPlay default mode, but the custom live
  `avlayer` path is explicitly arrival-driven: its appsink uses `sync=false`, the renderer sets
  `vsync_prop=false`, no sender PTS is attached to the appsrc buffer, and the sink creates
  invalid-timing `CMSampleBuffer` objects with `DisplayImmediately`. It has no
  `controlTimebase`. The bounded queue and readiness gate remain in place to limit latency.
- AirPlay pause/resume and live format transitions flush the displayed image and arm a one-shot
  seed sample. Recovery samples are displayed immediately; there is no presentation clock to
  reset or anchor in this live path. Timestamp rebase code remains only for generic timestamped
  sinks and historical diagnostics. A phone lock interval must not leave a stale lock-screen
  frame or make the first unlocked frame late.
- `videoStarted` geometry is a window contract: the standard content area is fitted to the
  negotiated aspect ratio, the window is kept on the current display, and manual resizing
  stays at that ratio.
- The custom `47000–47002` port group is intentional so the built-in macOS AirPlay Receiver
  may remain enabled. A socket-binding failure must be diagnosed as custom-port availability
  or firewall blocking; it is not resolved by changing the fixed project configuration.
- User `~/.uxplayrc` is ignored. `Resources/FrameRelay.uxplayrc` is empty.

## Allowed upstream patch

The project patches on the pinned UxPlay checkout are:

```text
patches/0001-uxplay-report-embedded-worker-exit.patch
patches/0002-uxplay-avlayer-timestamps-and-pause-recovery.patch
patches/0003-uxplay-frame-relay-diagnostics.patch
patches/0004-uxplay-resume-pts-rebase.patch
patches/0005-uxplay-resume-display-clock-anchor.patch
patches/0006-uxplay-format-transition-recovery.patch
patches/0007-uxplay-live-immediate-display.patch
patches/0008-uxplay-fast-avlayer-resume.patch
patches/0009-uxplay-audio-live-clock.patch
patches/0010-uxplay-avlayer-ready-watchdog.patch
patches/0011-uxplay-rebuild-video-on-disconnect.patch
```

`0001` adds an atomic intentional-stop flag and forwards the exact text `FrameRelay worker
exited unexpectedly` when the embedded upstream worker returns without a requested stop.
`0002` keeps the custom `avlayer` path, forwards GStreamer PTS/duration into
`AVSampleBufferDisplayLayer`, gives it a zero-based Core Media timebase, bounds the ready
queue, reports one-second output/drop counters, and flushes/resets the layer on AirPlay
pause/resume. `0003` adds the opt-in once-per-second transport, decoder/caps, GStreamer
queue, appsrc and AVLayer timing counters described in `docs/ARCHITECTURE.md`; it does not
change the normal media path. `0004` fixes the pause/resume timestamp-origin mismatch by
rebasing the first resumed video buffer to zero. `0005` keeps the display clock stopped until
the first resumed sample arrives, anchors that clock to the sample, and allows one seed sample
through a stale readiness rejection so the layer can recover without opening an unbounded queue.
`0006` flushes the current AVLayer image/queue after a live `videoflip` orientation or geometry
change, arms one new-format seed sample after the flush, and records actual appsink output
dimensions plus format-flush counts. `0007` removes the live AVLayer timestamp/timebase
scheduling path, uses invalid sample timing plus `DisplayImmediately` for every live sample,
and disables the internal `vsync_prop`/PTS attachment for that custom branch while preserving
the bounded queue and flush recovery. `Scripts/build-core.sh` checks the pinned SHA and replays
all eleven patches idempotently. These patches do not change the AirPlay protocol, device name,
or process model. Patch 0009 keeps AAC mirror audio arrival-paced and adds low-frequency audio
pipeline counters; ALAC timestamp synchronization remains unchanged. Patch 0010 adds the
bounded readiness watchdog and precise host restart marker described in Phase 3G. Patch 0011
stops the live video renderer after the last normal client disconnect and arms the existing
main-loop renderer rebuild so a subsequent client receives a fresh AVLayer attached to the host
view.
