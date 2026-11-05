import Foundation
import Testing
@testable import RavenUI

/// One app id (desktop/README.md, "App identity"): the macOS spelling is io.github.raven-ashco.Raven,
/// and the bundle built by scripts/make-app.sh uses it.
@Suite struct AppIdentityTests {
    @Test(.enabled(if: coreCheckedOut, "needs the raven-core submodule")) func bundleIDFollowsTheSharedTable() throws {
        #expect(AppIdentity.bundleID == "io.github.raven-ashco.Raven")
        let readme = try String(contentsOf: designRoot.deletingLastPathComponent().appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains("`\(AppIdentity.bundleID)`"))
    }

    /// The app's own version (VERSION, written into Info.plist by make-app.sh) is the one shown; the
    /// engine's is shown only where the app has none (`swift run`).
    @Test func theAppShowsItsOwnVersion() throws {
        #expect(AppIdentity.shownVersion(bundle: "0.1.1", engine: "0.1.0") == "0.1.1")
        #expect(AppIdentity.shownVersion(bundle: nil, engine: "0.1.0") == "0.1.0")
        #expect(AppIdentity.shownVersion(bundle: " ", engine: "0.1.0") == "0.1.0")
        #expect(AppIdentity.shownVersion(bundle: nil, engine: nil) == nil)
        let version = try String(contentsOf: packageRoot.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil, "VERSION: \(version)")
        let script = try String(contentsOf: packageRoot.appendingPathComponent("scripts/make-app.sh"), encoding: .utf8)
        #expect(script.contains("\"$HERE/VERSION\""))
    }

    @Test func makeAppWritesTheBundleID() throws {
        let script = try String(contentsOf: packageRoot.appendingPathComponent("scripts/make-app.sh"), encoding: .utf8)
        #expect(script.contains("<key>CFBundleIdentifier</key><string>\(AppIdentity.bundleID)</string>"))
        #expect(!script.contains("app.raven.desktop"))
    }
}
