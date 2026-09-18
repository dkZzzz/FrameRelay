# Upstream and build lock

## UxPlay

```text
Repository: https://github.com/Recluse/UxPlay.git
Branch: popyachsa-integration
Pinned commit: 587111368390479b7f65feb881c9257c02e508b5
Expected submodule path: third_party/uxplay
```

The pinned fork supplies the `airplay_core_*` flat C ABI and the macOS `avlayer`
renderer used to place decoded NV12 frames in a host `NSView`.

## FrameRelay port policy

FrameRelay passes `-p 47000` to UxPlay. UxPlay expands this into the fixed TCP and UDP
port group `47000`, `47001`, `47002`, then advertises the selected AirPlay/RAOP endpoint
through Bonjour. The macOS built-in AirPlay Receiver may remain enabled because it uses a
different service endpoint. A binding error must be investigated as a conflict on the
custom port group or as a firewall/network permission problem; the project must not fall
back to dynamic ports or silently change the port configuration.

## Build prerequisites

```text
cmake
ninja
pkg-config
gstreamer
gst-plugins-base
gst-plugins-good
gst-plugins-bad
gst-libav
libplist
openssl@3
```

The exact Homebrew versions, CMake configure output, `otool -L` output, bundle
checksums, and any patch files must be appended here after the first successful build.

## License

The UxPlay-derived engine is GPL-3.0-or-later. Keep all upstream notices and the
license files for bundled runtime dependencies under `Resources/LICENSES/`.

## Host versions recorded on 2026-09-12

```text
cmake: 4.4.3
ninja: 1.13.2
pkgconf/pkg-config: 3.0.7
gstreamer: 1.28.7
gst-plugins-base: 1.28.7 (Homebrew current formula resolution)
gst-plugins-good: 1.28.7 (Homebrew current formula resolution)
gst-plugins-bad: 1.28.7 (Homebrew current formula resolution)
gst-libav: 1.28.7 (Homebrew current formula resolution)
libplist: 2.7.0
openssl@3: 3.6.4
Swift: Apple Swift 6.2.3, arm64-apple-macosx26.0
macOS: 26.5, build 25F71
```

The build uses Homebrew only while compiling and assembling the bundle. Runtime
GStreamer paths are rewritten into `Contents/Resources/gstreamer-1.0` and
`Contents/Frameworks`; the release App must not need Homebrew.

## Release dependency audit — 2026-09-12

The main executable links only against macOS system frameworks and Swift runtime
libraries. The bundled core links against `@rpath` GStreamer libraries and system
frameworks; `Scripts/verify-bundle.sh` found no `/opt/homebrew`, `/usr/local`, or
project-build absolute path in the App's executable dependency graph. The final core
dependency entry points are:

```text
@rpath/uxplay-core.dylib
@rpath/libgstsdp-1.0.0.dylib
@rpath/libgstvideo-1.0.0.dylib
@rpath/libgstapp-1.0.0.dylib
@rpath/libgstbase-1.0.0.dylib
@rpath/libgstreamer-1.0.0.dylib
@rpath/libgobject-2.0.0.dylib
@rpath/libglib-2.0.0.dylib
@rpath/libintl.8.dylib
```

Phase 3A diagnostic SHA-256 values (2026-09-13):

```text
FrameRelay.app/Contents/MacOS/FrameRelay:
e3efe306b329527460a77eae50135ea9c2ec7501671fac24de07c2c898f61600
FrameRelay.app/Contents/Frameworks/uxplay-core.dylib:
8da101bee18c6e012c7740c625d862a36f9f14b254ed72097204d97a503d855e
FrameRelay-0.1.0-arm64.dmg:
980d775ab39d3ceae7688e931f4095231aa5c20d84dd44abaefb7b5ca4d37de6
```

## Build result

The fixed CMake invocation produced both of these arm64 binaries:

```text
build/uxplay/uxplay-core.dylib
build/uxplay/uxplay
```

`nm -gU build/uxplay/uxplay-core.dylib` confirmed all eight required exports:

```text
airplay_core_create
airplay_core_set_device_name
airplay_core_set_log_callback
airplay_core_set_window
airplay_core_set_options
airplay_core_start
airplay_core_stop
airplay_core_destroy
```

The compiler reports the pinned macOS AVSampleBufferDisplayLayer API deprecation
warnings on macOS 26 (`status`, `readyForMoreMediaData`, `flushAndRemoveImage` and
`enqueueSampleBuffer`); the compatibility API still builds successfully on the fixed
deployment target. No GStreamer debug flood is enabled.

## Project patch set

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

All eleven patches are applied idempotently by `Scripts/build-core.sh` after the submodule SHA
is checked. `0001` adds an atomic intentional-stop marker and reports an unexpected
embedded worker return via the existing log callback. `0002` is the video-path repair:
it carries GStreamer PTS/duration into the custom AV layer, uses a dedicated zero-based
Core Media timebase, limits the ready queue, emits one-second performance counters, and
flushes/resets the layer around AirPlay pause/resume. `0003` is measurement-only and is
enabled only by the existing `-FPSdata` diagnostic flag. It records transport callback,
decoder/caps, queue, appsrc, PixelBuffer/NV12 copy, sample creation, enqueue and
pause/resume recovery timing in one-second summaries. `0004` fixes the pause/resume media-time
origin mismatch by rebasing the first resumed raw PTS to zero before it reaches the display
layer; it also emits opt-in PTS rebase markers. `0005` leaves the display timebase stopped until
the first resumed frame arrives, anchors it to that frame's PTS, and allows one seed frame
through a stale readiness rejection without opening an unbounded queue. No patch changes the
AirPlay protocol, audio flag, device name, or external process model. `0006` flushes the current
AVLayer image/queue after a live `videoflip` orientation or geometry change, arms one new-format
seed sample after the flush, and records actual appsink output dimensions plus format-flush
counts. `0007` removes the custom live AVLayer's PTS/CMTimebase presentation scheduling, creates
invalid-timing samples with `kCMSampleAttachmentKey_DisplayImmediately`, and disables the
internal `vsync_prop`/PTS attachment for that live branch while retaining the bounded queue,
ready gate, pause flush, format flush and seed recovery. `0008` measures recovery from the
resume marker rather than the pause marker and avoids the synchronous 100 ms GStreamer state
wait on the live AVLayer resume path; non-AVLayer paths retain their existing state wait. The
patches do not change the AirPlay protocol or process model. `0009` makes AAC mirror
audio arrival-paced (`sync=false`) instead of comparing AirPlay/NTP timestamps against a new
GStreamer appsrc base time, restarts the selected audio pipeline on repeated format starts, and
records five-second received/valid/pushed/flow-error counters for long-running diagnosis. ALAC
timestamp synchronization remains unchanged. `0010` watches the live AVLayer readiness gate
without building an unbounded queue: after three seconds of continuous
`readyForMoreMediaData == false`, it flushes the current image and arms one seed frame, up to
two attempts. If the layer still refuses every frame, it emits a precise watchdog restart
marker for the Swift host; automatic restart is then scheduled through the existing bounded
restart policy. It also records watchdog flushes and escalations in the diagnostic AVLayer
summary. `0011` handles the normal last-client disconnect path: it stops the live video
renderer, arms the existing main-loop renderer rebuild, and records
`FrameRelay video lifecycle: action=disconnect-reset reason=last-client-closed`. The HTTP
server is intentionally left running because the callback executes on the HTTP worker and
must not join that worker from inside its own callback. The next AirPlay client therefore
receives a fresh AVLayer bound to the existing host view without requiring the user to quit
and relaunch FrameRelay.

## Bundled plugin set

The v0.1 audio/video bundle starts with these GStreamer plugins, then recursively copies
their non-system dylib dependencies:

```text
libgstapp.dylib
libgstaudioconvert.dylib
libgstaudioresample.dylib
libgstlevel.dylib
libgstvolume.dylib
libgstosxaudio.dylib
libgstautodetect.dylib
libgstapplemedia.dylib
libgstcoreelements.dylib
libgstlibav.dylib
libgstplayback.dylib
libgsttypefindfunctions.dylib
libgstvideoconvertscale.dylib
libgstvideofilter.dylib
libgstvideoparsersbad.dylib
gst-plugin-scanner
```

The audio sink and conversion plugins are selected because v0.1 passes
`-as osxaudiosink`; dependencies pulled by GStreamer itself remain only when required by a
bundled Mach-O.

## Dependency and checksum record

`Scripts/bundle-gstreamer.sh` rewrites all non-system load commands to `@rpath` or
`@loader_path` and signs only after rewriting. `Scripts/verify-bundle.sh` rejects
Homebrew, `/usr/local`, and project build absolute paths. The final values must be
refreshed after the last release build with:

```bash
find dist/FrameRelay.app -type f -print0 | while IFS= read -r -d '' file; do
  if file "$file" | grep -q 'Mach-O'; then otool -L "$file"; fi
done
shasum -a 256 dist/FrameRelay.app/Contents/MacOS/FrameRelay
shasum -a 256 dist/FrameRelay.app/Contents/Frameworks/uxplay-core.dylib
shasum -a 256 dist/FrameRelay-0.1.0-arm64.dmg
```

The release record is intentionally kept in this file after the final rebuild; a
checksum from an intermediate unsigned bundle must not be presented as final.

Historical release record from the 2026-09-12 rebuild:

```text
FrameRelay.app/Contents/MacOS/FrameRelay:
c4eb2a349e65a72929001f93b7e249991a30b7ed2243d0480a5e3409f07ce6e5

FrameRelay.app/Contents/Frameworks/uxplay-core.dylib:
2f0748c80b229fcc9b8c20665dd08ec23470f673add62e308115db7857116153

FrameRelay-0.1.0-arm64.dmg:
773ad57d1c27ccf7b0a0c701f55c10b31e1b8bc6648e7f592f6b54ac7a80352f

App size: 61M
DMG size: 27M
Contents/Frameworks files: 52
Contents/Resources/gstreamer-1.0 files: 11
codesign --verify --deep --strict: passed
```

## Phase 3A diagnostic build — 2026-09-13

This build contains the opt-in `-FPSdata` segmented diagnostics. The normal launch
configuration is unchanged; the diagnostics are enabled only by the explicit
`--diagnostic-1080p`, `--diagnostic-720p`, or `--diagnostic-1080p-nosync` profile.

```text
FrameRelay.app/Contents/MacOS/FrameRelay:
e3efe306b329527460a77eae50135ea9c2ec7501671fac24de07c2c898f61600

FrameRelay.app/Contents/Frameworks/uxplay-core.dylib:
8da101bee18c6e012c7740c625d862a36f9f14b254ed72097204d97a503d855e

FrameRelay-0.1.0-arm64.dmg:
980d775ab39d3ceae7688e931f4095231aa5c20d84dd44abaefb7b5ca4d37de6

App size: 61M
DMG size: 27M
codesign --verify --deep --strict: passed
Scripts/verify-bundle.sh: passed
```

The final bundle's non-system load names are all relative (`@rpath` or
`@loader_path`). The remaining load names are system frameworks and
`/usr/lib`/Swift runtime libraries supplied by macOS. `otool -L` on the final App
contains no `/opt/homebrew`, `/usr/local`, or project `build` absolute path.

The final bundled framework set is:

```text
libSvtAv1Enc.4.dylib
libX11-xcb.1.dylib
libX11.6.dylib
libXau.6.dylib
libXdmcp.6.dylib
libavcodec.63.dylib
libavfilter.12.dylib
libavformat.63.dylib
libavutil.61.dylib
libcrypto.3.dylib
libdav1d.7.dylib
libgio-2.0.0.dylib
libglib-2.0.0.dylib
libgmodule-2.0.0.dylib
libgobject-2.0.0.dylib
libgstapp-1.0.0.dylib
libgstapp.dylib
libgstapplemedia.dylib
libgstaudio-1.0.0.dylib
libgstautodetect.dylib
libgstbase-1.0.0.dylib
libgstcodecparsers-1.0.0.dylib
libgstcoreelements.dylib
libgstgl-1.0.0.dylib
libgstlibav.dylib
libgstpbutils-1.0.0.dylib
libgstplayback.dylib
libgstreamer-1.0.0.dylib
libgstrtp-1.0.0.dylib
libgstsdp-1.0.0.dylib
libgsttag-1.0.0.dylib
libgsttypefindfunctions.dylib
libgstvideo-1.0.0.dylib
libgstvideoconvertscale.dylib
libgstvideofilter.dylib
libgstvideoparsersbad.dylib
libintl.8.dylib
liblzma.5.dylib
libmp3lame.0.dylib
libmpg123.0.dylib
libopus.0.dylib
liborc-0.4.0.dylib
libpcre2-8.0.dylib
libssl.3.dylib
libswresample.7.dylib
libswscale.10.dylib
libvmaf.3.dylib
libvpx.12.dylib
libx264.165.dylib
libx265.217.dylib
libxcb.1.dylib
uxplay-core.dylib
```

## Phase 3B recovery build — 2026-09-13

This build contains the pause/resume first-frame PTS rebase in patch 0004 and the
diagnostic host geometry log. The normal launch configuration remains unchanged. The
following values are from the signed bundle generated after the four patches were
replayed from the pinned UxPlay checkout:

```text
FrameRelay.app/Contents/MacOS/FrameRelay:
8cf4e6e93e930a0ddf1ae352d7f2871e9daf724b263c712fe27edb3d2a9b908c

FrameRelay.app/Contents/Frameworks/uxplay-core.dylib:
fb76d6ba3d65e108ddf70e423f0e762a44af22f5e50ac3117c1e66f10464e7cb

FrameRelay-0.1.0-arm64.dmg:
231ce9d224c31c13f3e430ac40a7a6a60669c44c8692f41d7db03789020a73a4

App size: 61M class bundle; DMG size: 28,402,956 bytes
Contents/Frameworks files: 52
Contents/Resources/gstreamer-1.0 files: 11
swift test -c release: 13/13 passed
codesign --verify --deep --strict: passed
Scripts/verify-bundle.sh: passed
```

`Scripts/build-core.sh` verified the pinned SHA and compiled both `uxplay-core.dylib` and
standalone `uxplay` after patch 0004. `Scripts/bundle-gstreamer.sh` and
`Scripts/package-dmg.sh` completed successfully. The real iPhone lock/unlock regression
for this build is still pending; these hashes certify the artifact, not the device
acceptance result.

## Phase 3C recovery build — 2026-09-13

This build adds patch 0005 on top of patches 0001–0004. During resume, the AVLayer display
clock remains stopped until the first decoded frame arrives; that frame anchors the clock and
gets a one-shot readiness seed. The normal launch configuration, 1080p target, `-fps 60`,
default timestamp sync, fixed port, audio policy, and AppKit window behavior remain unchanged.
The following values are from the signed bundle generated from the pinned UxPlay checkout:

```text
FrameRelay.app/Contents/MacOS/FrameRelay:
6171029c83aec5007a94a8bdee6e66dfc7fffbd5654a943d450ca8743ea8d6a8

FrameRelay.app/Contents/Frameworks/uxplay-core.dylib:
978699d205a512c48b7203bab0802747743d10e8cace0435dab0ba939a1e68cb

FrameRelay-0.1.0-arm64.dmg:
08efbb01c0b360c3082c9f91c12ff99e25da2fa350715e0be3346efaa6cfaa24

App size: 61M class bundle; DMG size: 27M (`du -sh`); Contents/Frameworks files: 52;
Contents/Resources/gstreamer-1.0 files: 11
swift test -c release: 13/13 passed
codesign --verify --deep --strict: passed
Scripts/verify-bundle.sh: passed
clean-environment restart-loop: 2/2 passed
```

`Scripts/build-core.sh` verified the pinned SHA and compiled both `uxplay-core.dylib` and
standalone `uxplay` after patch 0005. Patch 0005 reverse-check, source `diff --check`,
`Scripts/bundle-gstreamer.sh`, `Scripts/verify-bundle.sh`, and `Scripts/package-dmg.sh` all
completed successfully. The real iPhone fast lock/wake/unlock regression is still pending;
these hashes certify the artifact, not the device acceptance result.

## Phase 3D source/core build — 2026-09-13

This source revision adds patch 0006 after patches 0001–0005. The local core, App bundle and
DMG builds have passed. The real-device result remains
open because the purpose of this revision is specifically to verify that the actual appsink
sample dimensions and AVSampleBufferDisplayLayer image change from the portrait lock-screen
stream back to the landscape game stream.

```text
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Applied patches: 0001–0006
Core build: build/uxplay/uxplay-core.dylib and build/uxplay/uxplay, arm64, passed
Static patch check: reverse-check and fresh sequential apply/diff check, passed
App build: dist/FrameRelay.app, signed and verified, passed
DMG build: dist/FrameRelay-0.1.0-arm64.dmg, passed
Real iPhone test: pending
FrameRelay executable SHA-256: 047f72449de9b5d2f6c14cb4f158308b08f9e2aa600f6ce6c8552842350723aa
uxplay-core.dylib SHA-256: 26f1ee9c6881f150a506ac8eb4523cf55275a019ca8770c8b5a10b6c42c2a613
DMG SHA-256: 17c202091745344bd605e9a0d8a278aa2df97c889ac623ed6798d0461b3192a3
App size: 61M class bundle; DMG size: 27M; Contents/Frameworks files: 52; Contents/Resources/gstreamer-1.0 files: 11
Clean-environment restart-loop: 2/2 passed
codesign --verify --deep --strict: passed
Scripts/verify-bundle.sh: passed
```

## Phase 3E live immediate presentation build — 2026-09-13

This source revision adds patch 0007 after patches 0001–0006. The preceding real-device run
showed that input, decode, format transition and AVLayer enqueue counters continued while the
visible image froze. The current live path therefore no longer schedules custom AVLayer samples
against sender PTS or a Core Media timebase: it uses invalid sample timing and
`kCMSampleAttachmentKey_DisplayImmediately`, while retaining the bounded queue and recovery
flushes. The real iPhone result for this revision remains pending.

```text
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Applied patches: 0001–0007
Core build: build/uxplay/uxplay-core.dylib and build/uxplay/uxplay, arm64, passed
Static patch check: reverse-check and fresh sequential apply/diff check, passed
Swift build/test: release arm64 build passed; Swift Testing 13/13 passed
App build: dist/FrameRelay.app, signed and verified, passed
Bundle check: verify-bundle passed; no Homebrew/project-build absolute dependency
DMG build: dist/FrameRelay-0.1.0-arm64.dmg, passed
Clean-environment restart-loop: 20/20 passed
Real iPhone test: pending
FrameRelay executable SHA-256: 7aaeaf02ed0b16a75939b4047b93d6bd0703978b2925faab247ab879edd9c877
uxplay-core.dylib SHA-256: 32f04ddc063f6e74b9be8789da811c0d0aa4bf9c16ec858595b0edad7fb52c3d
DMG SHA-256: 8a826977ffb7235989e4bd5d72b513d9dc863fecbce00bbf3687da073c48e2960
App size: 61M class bundle; DMG size: 27M; Contents/Frameworks files: 52; Contents/Resources/gstreamer-1.0 files: 11
codesign --verify --deep --strict: passed
Scripts/verify-bundle.sh: passed
```

## Phase 3F fast AVLayer resume build — 2026-09-13

This source revision adds patch 0008 after patches 0001–0007. It measures recovery from the
resume marker rather than the pause marker and avoids the synchronous 100 ms GStreamer state
wait on the live AVLayer resume path. The sender-side pause→resume no-packet interval remains
an AirPlay/iPhone behavior and is not hidden by retaining stale locked-screen content.

```text
Core commit: 587111368390479b7f65feb881c9257c02e508b5
Applied patches: 0001–0008
Core build: build/uxplay/uxplay-core.dylib and build/uxplay/uxplay, arm64, passed
Static patch check: 0008 reverse→forward→reverse-check, passed
Swift Testing: 13/13 passed
App build: dist/FrameRelay.app, signed and verified, passed
Bundle check: verify-bundle passed; no Homebrew/project-build absolute dependency
DMG build: dist/FrameRelay-0.1.0-arm64.dmg, passed
Clean-environment restart-loop: 2/2 passed
Real iPhone test: pending; must separately record pause→resume and resume→first accepted sample
FrameRelay executable SHA-256: cc6bea487ffa3d2a2d746ea847016504cef34c6a50f8fb088291023485ef0d90
uxplay-core.dylib SHA-256: d2a7527eb8744b261ebdf4531dfedf01dc35e325c1991fbc2b8250279ff4ba2e
DMG SHA-256: 2bdd37b6a4953ae4b0f14be684ee860dd5d4be0a026d56a49210f5b2cb351bbb
codesign --verify --deep --strict: passed
Scripts/verify-bundle.sh: passed
```

## License inventory

The repository and App bundle retain the following notices under
`Resources/LICENSES/`:

```text
GPL-3.0-or-later.txt  — UxPlay-derived engine
GStreamer.txt         — GStreamer runtime
OpenSSL.txt           — OpenSSL runtime
libplist.txt          — libplist runtime
llhttp-MIT.txt        — transitive runtime notice
playfair.md           — transitive runtime notice
NOTICE.txt            — FrameRelay/UxPlay notice aggregation
```
