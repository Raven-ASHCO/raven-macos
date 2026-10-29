// swift-tools-version: 5.9
// Raven for macOS: SwiftUI front end over the raven-client JSON contract (desktop/api/API.md).
// No third-party packages. Builds with the Swift toolchain alone (Command Line Tools are enough);
// the engine (Rust, built with cargo in core/node/) is linked only with RAVEN_ENGINE=1 (see below).
import Foundation
import PackageDescription

/// swift-testing with the Command Line Tools only (no Xcode): the default build system neither
/// searches host/plugins/testing for the `@Test` macro plugin nor adds the folder that holds
/// Testing.framework to the test bundle's run path. Both are fixed here, and only when the active
/// developer directory is the Command Line Tools; under Xcode nothing is added.
let clt = "/Library/Developer/CommandLineTools"
let cltTesting: (plugins: String, frameworks: String, libs: String)? = {
    let plugins = clt + "/usr/lib/swift/host/plugins/testing"
    let active = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")) ?? clt
    guard active.hasPrefix(clt), FileManager.default.fileExists(atPath: plugins) else { return nil }
    return (plugins, clt + "/Library/Developer/Frameworks", clt + "/Library/Developer/usr/lib")
}()
let testSwiftSettings: [SwiftSetting] = cltTesting.map { [.unsafeFlags(["-plugin-path", $0.plugins])] } ?? []
let testLinkerSettings: [LinkerSetting] = cltTesting.map {
    [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", $0.frameworks, "-Xlinker", "-rpath", "-Xlinker", $0.libs])]
} ?? []

/// The Raven engine (`raven-client`, a Rust static library; desktop/api/API.md) is linked only when
/// asked, so `swift build` and `swift test` work on a machine that has not built it:
///
///     scripts/build-engine.sh [release|dev]       # cargo build -p raven-client -p raven-node in core/node/
///     RAVEN_ENGINE=1 swift build | run            # link core/node/target/release/libraven_client.a
///     RAVEN_ENGINE=dev swift test                 # link core/node/target/debug/libraven_client.a
///
/// `dev` is the engine's debug build: unlike a release engine it accepts the file-backed secret stores
/// (`RAVEN_*_BACKEND=locked-file`) the engine tests and smoke runs use; it is never shipped.
/// `RAVEN_ENGINE_LIB=/path/to/libraven_client.a` links another copy. With the engine, `CRavenClient`
/// (a module map over core/node/crates/raven-client/include/raven_client.h) is a dependency of RavenUI and
/// `RAVEN_ENGINE` is defined; without it, RavenUI compiles `MissingEngine` (the engine-missing screen)
/// in its place. The static library is linked by its full path, so the `libraven_client.dylib` cargo
/// writes next to it is never picked up instead.
let environment = Context.environment
let engineLibrary: String? = {
    if let lib = environment["RAVEN_ENGINE_LIB"], !lib.isEmpty { return lib }
    let profile: String
    switch environment["RAVEN_ENGINE"] {
    case "1", "release": profile = "release"
    case "dev": profile = "debug"
    default: return nil
    }
    return URL(fileURLWithPath: Context.packageDirectory)
        .appendingPathComponent("core/node/target/\(profile)/libraven_client.a").standardizedFileURL.path
}()
/// What the engine needs from the system besides libSystem (`cargo rustc -p raven-client --release
/// --lib --crate-type staticlib -- --print native-static-libs`: Security, CoreFoundation, iconv).
let engineLinkerSettings: [LinkerSetting] = engineLibrary.map {
    [.unsafeFlags(["-Xlinker", $0]),
     .linkedFramework("Security"), .linkedFramework("CoreFoundation"), .linkedLibrary("iconv")]
} ?? []
let engineDependencies: [Target.Dependency] = engineLibrary == nil ? [] : ["CRavenClient"]
let engineSwiftSettings: [SwiftSetting] = engineLibrary == nil ? [] : [.define("RAVEN_ENGINE")]
let engineTargets: [Target] = engineLibrary == nil ? [] : [
    // raven_client.h as the Swift module `CRavenClient` (Sources/CRavenClient/module.modulemap).
    .systemLibrary(name: "CRavenClient"),
]

let package = Package(
    name: "Raven",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Raven", targets: ["Raven"]),
        .executable(name: "RavenSnapshots", targets: ["RavenSnapshots"]),
        .library(name: "RavenUI", targets: ["RavenUI"]),
    ],
    targets: engineTargets + [
        // Views, theme, models, engine protocol, MockRaven (debug only) and the bundled design files.
        .target(
            name: "RavenUI",
            dependencies: engineDependencies,
            resources: [.copy("Resources")],
            swiftSettings: engineSwiftSettings,
            linkerSettings: engineLinkerSettings
        ),
        // The SwiftUI app (main window, settings, menu bar extra).
        .executableTarget(name: "Raven", dependencies: ["RavenUI"]),
        // Renders every main screen to PNG with ImageRenderer; never opens a window.
        .executableTarget(name: "RavenSnapshots", dependencies: ["RavenUI"]),
        // swift-testing (the Command Line Tools ship Testing.framework, not XCTest).
        // With the engine, also tests that call raven_call through CRavenClient (EngineTests.swift).
        .testTarget(name: "RavenUITests", dependencies: ["RavenUI"] + engineDependencies,
                    swiftSettings: testSwiftSettings + engineSwiftSettings, linkerSettings: testLinkerSettings),
    ]
)
