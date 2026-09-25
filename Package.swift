// swift-tools-version: 6.2
import PackageDescription

/// WebRTC's AEC3, built by `mise run engine:aec` with its abseil folded in.
let aec = Context.packageDirectory + "/.deps/webrtc-audio-processing"

let package = Package(
    name: "Earshot",
    platforms: [.macOS("26.4")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "EarshotKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "CEchoCanceller",
            cxxSettings: [
                .unsafeFlags(["-I", aec + "/include/webrtc-audio-processing-2"]),
                .define("WEBRTC_LIBRARY_IMPL"), .define("WEBRTC_POSIX"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L", aec + "/lib"]), .linkedLibrary("webrtc-audio-processing-2"),
            ]
        ),
        .target(
            name: "EarshotCapture", dependencies: ["EarshotKit", "CEchoCanceller"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "Earshot",
            dependencies: [
                "EarshotKit", "EarshotCapture", .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)],
            // Sparkle.framework ships in Contents/Frameworks of the bundle.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "EarshotKitTests",
            dependencies: ["EarshotKit", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EarshotCaptureTests",
            dependencies: ["EarshotCapture", "EarshotKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
