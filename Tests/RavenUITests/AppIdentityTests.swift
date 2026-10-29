import Foundation
import Testing
@testable import RavenUI

/// One app id (desktop/README.md, "App identity"): the macOS spelling is io.github.raven-ashco.Raven,
/// and the bundle built by scripts/make-app.sh uses it.
@Suite struct AppIdentityTests {
    @Test func bundleIDFollowsTheSharedTable() throws {
        #expect(AppIdentity.bundleID == "io.github.raven-ashco.Raven")
        let readme = try String(contentsOf: designRoot.deletingLastPathComponent().appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains("`\(AppIdentity.bundleID)`"))
    }

    @Test func makeAppWritesTheBundleID() throws {
        let script = try String(contentsOf: packageRoot.appendingPathComponent("scripts/make-app.sh"), encoding: .utf8)
        #expect(script.contains("<key>CFBundleIdentifier</key><string>\(AppIdentity.bundleID)</string>"))
        #expect(!script.contains("app.raven.desktop"))
    }
}
