import Foundation
import Testing
import FrameRelayCoreBridge
@testable import FrameRelayApp

struct FrameRelayTests {
    @Test("live configuration enables the Mac audio output")
    func liveConfiguration() {
        #expect(AirPlayConfiguration.liveVideo.deviceName == "FrameRelay")
        #expect(AirPlayConfiguration.liveVideo.options == "-p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080")
        #expect(!AirPlayConfiguration.liveVideo.options.split(separator: " ").contains("-a"))
        #expect(AirPlayConfiguration.liveVideo.options.contains("-as osxaudiosink"))
    }

    @Test("diagnostic profiles are opt-in and preserve the fixed AirPlay path")
    func diagnosticProfiles() {
        #expect(AirPlayConfiguration.diagnostic1080p.options == "-p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080 -FPSdata")
        #expect(AirPlayConfiguration.diagnostic1080pNoSync.options == "-p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1920x1080 -vsync no -FPSdata")
        #expect(AirPlayConfiguration.diagnostic720p.options == "-p 47000 -nh -as osxaudiosink -vs avlayer -fps 60 -reset 8 -nofreeze -nohold -s 1280x720 -FPSdata")
        #expect(!FrameRelayLaunchProfile(arguments: ["FrameRelay"]).isDiagnostic)
        #expect(FrameRelayLaunchProfile(arguments: ["FrameRelay", "--diagnostic-1080p"]) == .diagnostic1080p)
        #expect(FrameRelayLaunchProfile(arguments: ["FrameRelay", "--diagnostic-1080p-nosync"]) == .diagnostic1080pNoSync)
        #expect(FrameRelayLaunchProfile(arguments: ["FrameRelay", "--diagnostic-720p"]) == .diagnostic720p)
    }

    @Test("video geometry log is parsed")
    func videoGeometryLog() {
        let parser = EngineLogParser()
        let event = parser.parse(
            level: 2,
            message: "begin video stream wxh = 1920x1080; source 1920x884 (rot=0x04)"
        )

        #expect(event == .videoStarted(VideoGeometry(width: 1920, height: 1080, rotationHint: 4)))

        let portrait = parser.parse(
            level: 2,
            message: "begin video stream wxh = 1920x884; source 884x1920 (rot=0x01)"
        )
        #expect(portrait == .videoStarted(VideoGeometry(width: 1920, height: 884, rotationHint: 1)))
    }

    @Test("disconnect and reset markers are parsed")
    func disconnectMarkers() {
        let parser = EngineLogParser()
        #expect(parser.parse(level: 2, message: "Open connections: 0") == .clientDisconnected)
        #expect(parser.parse(level: 2, message: "connection reset by peer") == .clientReset)
        #expect(parser.parse(level: 2, message: "*** ERROR lost connection with client (network problem?)") == .clientReset)
        #expect(parser.parse(level: 2, message: "video_reset: type = NoHold") == .clientReset)
        #expect(parser.parse(level: 2, message: "Stopping RAOP Server...") == .engineStopped)
    }

    @Test("real UxPlay connection and server markers are parsed")
    func upstreamMarkers() {
        let parser = EngineLogParser()
        #expect(parser.parse(level: 2, message: "Initialized server socket(s)") == .serverReady)
        #expect(parser.parse(level: 2, message: "register_dnssd: advertised AirPlay service with Features code") == .serverReady)
        #expect(parser.parse(level: 2, message: "connection request from iPhone (iPhone15,5) with deviceID = example") == .clientConnected)
        #expect(parser.parse(level: 2, message: "Open connections: 1") == .clientConnected)
        #expect(parser.parse(level: 2, message: "Begin streaming") == .clientConnected)
        #expect(parser.parse(level: 2, message: "Begin streaming to GStreamer video pipeline") == nil)
    }

    @Test("empty and corrupted logs do not create events")
    func malformedLogs() {
        let parser = EngineLogParser()
        #expect(parser.parse(level: 2, message: "") == nil)
        #expect(parser.parse(level: 2, message: "begin video stream wxh = nope") == nil)
        #expect(parser.parse(level: 2, message: "begin video stream wxh = 0x0; source broken") == nil)
        #expect(parser.parse(level: 2, message: "unrelated informational text") == nil)
    }

    @Test("unrelated informational log does not change state")
    func unrelatedLog() {
        let parser = EngineLogParser()
        #expect(parser.parse(level: 2, message: "using system MAC address") == nil)
    }

    @Test("window sizing follows landscape and portrait geometry")
    func windowSizing() {
        let available = VideoWindowSize(width: 1432, height: 862)
        let landscape = VideoWindowSizer.contentSize(
            for: VideoGeometry(width: 1920, height: 884, rotationHint: 4),
            available: available
        )
        let portrait = VideoWindowSizer.contentSize(
            for: VideoGeometry(width: 498, height: 1080, rotationHint: 0),
            available: available
        )

        #expect(landscape.width == 1280)
        #expect(landscape.height > 589 && landscape.height < 590)
        #expect(portrait.height == 720)
        #expect(portrait.width > 331 && portrait.width < 333)
        #expect(abs((landscape.width / landscape.height) - (1920.0 / 884.0)) < 0.001)
        #expect(abs((portrait.width / portrait.height) - (498.0 / 1080.0)) < 0.001)
    }

    @Test("unexpected embedded worker exit is retained as an engine error")
    func unexpectedWorkerExit() {
        let parser = EngineLogParser()
        #expect(
            parser.parse(level: 3, message: "FrameRelay worker exited unexpectedly") ==
                .engineError("FrameRelay worker exited unexpectedly")
        )
    }

    @Test("AVLayer readiness watchdog requests a controlled restart")
    func avlayerWatchdogRestart() {
        let parser = EngineLogParser()
        let message = "FrameRelay avlayer watchdog: action=restart reason=ready-stuck flushes=2 escalations=1"
        #expect(parser.parse(level: 3, message: message) == .displayStalled(message))
    }

    @Test("restart policy uses the fixed 0.5/1/2 second backoff and three-attempt window")
    func restartPolicy() {
        var policy = RestartPolicy()
        let start = Date(timeIntervalSince1970: 10_000)
        #expect(policy.nextDelayNanoseconds(now: start) == 500_000_000)
        #expect(policy.nextDelayNanoseconds(now: start.addingTimeInterval(1)) == 1_000_000_000)
        #expect(policy.nextDelayNanoseconds(now: start.addingTimeInterval(2)) == 2_000_000_000)
        #expect(policy.nextDelayNanoseconds(now: start.addingTimeInterval(3)) == nil)

        policy.reset()
        #expect(policy.nextDelayNanoseconds(now: start.addingTimeInterval(61)) == 500_000_000)
    }

    @Test("C bridge rejects a missing dylib and always terminates its error buffer")
    func cBridgeMissingDylibAndErrorBuffer() {
        var buffer = [CChar](repeating: 65, count: 1)
        let handle = "/private/var/tmp/FrameRelay-no-such-core.dylib".withCString { path in
            buffer.withUnsafeMutableBufferPointer { contents in
                fr_core_open(path, contents.baseAddress, contents.count)
            }
        }

        #expect(handle == nil)
        #expect(buffer[0] == 0)

        var noCapacity = [CChar](repeating: 65, count: 1)
        let noCapacityHandle = "".withCString { path in
            noCapacity.withUnsafeMutableBufferPointer { contents in
                fr_core_open(path, contents.baseAddress, 0)
            }
        }
        #expect(noCapacityHandle == nil)
        #expect(noCapacity[0] == 65)
    }

    @Test("C bridge reports missing symbols without crashing")
    func cBridgeMissingSymbol() throws {
        let fixture = try DynamicLibraryFixture(source: #"""
        int unrelated_symbol(void) { return 0; }
        """#)
        defer { fixture.remove() }

        var buffer = [CChar](repeating: 0, count: 256)
        let handle = fixture.libraryURL.path.withCString { path in
            buffer.withUnsafeMutableBufferPointer { contents in
                fr_core_open(path, contents.baseAddress, contents.count)
            }
        }

        #expect(handle == nil)
        let message = String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        #expect(message.contains("airplay_core_create"))
    }

    @Test("C bridge enforces create start already-running stop and destroy order")
    func cBridgeLifecycle() throws {
        let fixture = try DynamicLibraryFixture(source: #"""
        #include <stdint.h>
        #include <stdio.h>
        #include <stdlib.h>

        typedef struct fake_core { int running; int started; } fake_core_t;
        typedef void (*log_callback)(int32_t, const char *, void *);
        static const char *marker_path = "\#(DynamicLibraryFixture.currentMarkerPath)";

        static void mark(const char *value) {
            FILE *file = fopen(marker_path, "a");
            if (file) { fputs(value, file); fputc('\n', file); fclose(file); }
        }

        fake_core_t *airplay_core_create(void) {
            return (fake_core_t *)calloc(1, sizeof(fake_core_t));
        }
        int airplay_core_set_window(fake_core_t *core, void *view) {
            if (!view && core->started) mark("window-clear"); return 0;
        }
        int airplay_core_set_device_name(fake_core_t *core, const char *name) {
            (void)core; (void)name; return 0;
        }
        void airplay_core_set_log_callback(fake_core_t *core, log_callback callback, void *user) {
            (void)core; (void)user; if (!callback) mark("log-clear");
        }
        int airplay_core_set_options(fake_core_t *core, const char *options) {
            (void)core; (void)options; return 0;
        }
        int airplay_core_start(fake_core_t *core) {
            if (core->running) return -2; core->running = 1; core->started = 1; mark("start"); return 0;
        }
        void airplay_core_stop(fake_core_t *core) {
            if (core->running) { core->running = 0; mark("stop"); }
        }
        void airplay_core_destroy(fake_core_t *core) {
            mark("destroy"); free(core);
        }
        """#)
        try? FileManager.default.removeItem(at: DynamicLibraryFixture.markerURL)
        defer {
            fixture.remove()
            try? FileManager.default.removeItem(at: DynamicLibraryFixture.markerURL)
        }

        var expectedSequence: [String] = []
        for _ in 0..<20 {
            var error = [CChar](repeating: 0, count: 256)
            let handle = fixture.libraryURL.path.withCString { path in
                error.withUnsafeMutableBufferPointer { contents in
                    fr_core_open(path, contents.baseAddress, contents.count)
                }
            }
            #expect(handle != nil)
            guard let handle else { continue }

            #expect(fr_core_set_window(handle, nil) == FRCoreStatusOK)
            #expect("FrameRelay".withCString { fr_core_set_device_name(handle, $0) } == FRCoreStatusOK)
            #expect("-a".withCString { fr_core_set_options(handle, $0) } == FRCoreStatusOK)
            #expect(fr_core_start(handle) == FRCoreStatusOK)
            #expect(fr_core_start(handle) == FRCoreStatusAlreadyRunning)
            fr_core_stop(handle)
            fr_core_stop(handle)
            fr_core_close(handle)
            expectedSequence.append(contentsOf: [
                "start", "stop", "log-clear", "window-clear", "destroy"
            ])
        }

        let sequence = try String(contentsOf: DynamicLibraryFixture.markerURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        #expect(sequence == expectedSequence)
    }
}

private final class DynamicLibraryFixture {
    private let directoryURL: URL
    let libraryURL: URL
    static let markerURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FrameRelayCoreBridgeTests-marker-\(UUID().uuidString)")
    static var currentMarkerPath: String {
        markerURL.path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    init(source: String) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameRelayCoreBridgeTests-\(UUID().uuidString)", isDirectory: true)
        libraryURL = directoryURL.appendingPathComponent("fixture.dylib")
        let sourceURL = directoryURL.appendingPathComponent("fixture.c")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: sourceURL, options: .atomic)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
        process.arguments = ["-dynamiclib", "-O0", "-o", libraryURL.path, sourceURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: output, encoding: .utf8) ?? "unknown compiler error"
            throw FixtureError.compilerFailed(message)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private enum FixtureError: Error {
    case compilerFailed(String)
}
