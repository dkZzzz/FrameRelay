// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FrameRelay",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "FrameRelay", targets: ["FrameRelayApp"])
    ],
    targets: [
        .target(
            name: "FrameRelayCoreBridge",
            path: "Sources/FrameRelayCoreBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-std=c11"])
            ]
        ),
        .executableTarget(
            name: "FrameRelayApp",
            dependencies: ["FrameRelayCoreBridge"],
            path: "Sources/FrameRelayApp",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "FrameRelayTests",
            dependencies: ["FrameRelayApp", "FrameRelayCoreBridge"],
            path: "Tests/FrameRelayTests",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
