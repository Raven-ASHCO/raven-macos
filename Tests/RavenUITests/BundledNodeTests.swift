import Foundation
import Testing
@testable import RavenUI

/// The app bundle's own raven-node (BundledNode): used unless RAVEN_NODE_BIN is set, and only from an
/// .app that has it where scripts/make-app.sh puts it.
@Suite struct BundledNodeTests {
    let app = URL(fileURLWithPath: "/Applications/Raven.app")

    @Test func anAppWithItsNodeUsesIt() {
        var asked: [String] = []
        let path = BundledNode.path(bundleURL: app, environment: [:]) { asked.append($0); return true }
        #expect(path == "/Applications/Raven.app/Contents/Helpers/raven-node")
        #expect(asked == ["/Applications/Raven.app/Contents/Helpers/raven-node"])
    }

    @Test func aSetVariableWins() {
        #expect(BundledNode.path(bundleURL: app, environment: ["RAVEN_NODE_BIN": "/opt/raven-node"]) { _ in true } == nil)
        // An empty variable counts as unset, as in the engine.
        #expect(BundledNode.path(bundleURL: app, environment: ["RAVEN_NODE_BIN": ""]) { _ in true } != nil)
    }

    @Test func noNodeOrNoBundleChangesNothing() {
        #expect(BundledNode.path(bundleURL: app, environment: [:]) { _ in false } == nil)
        let swiftRun = URL(fileURLWithPath: "/tmp/raven/.build/arm64-apple-macosx/debug")
        #expect(BundledNode.path(bundleURL: swiftRun, environment: [:]) { _ in true } == nil)
    }

    @Test func makeAppPutsTheHelpersWhereTheEngineLooks() throws {
        let script = try String(contentsOf: packageRoot.appendingPathComponent("scripts/make-app.sh"), encoding: .utf8)
        // raven-node in Contents/Helpers, and its two helpers next to it (raven-node finds them there).
        #expect(BundledNode.relativePath == "Contents/Helpers/raven-node")
        #expect(script.contains("HELPERS=\"$APP/Contents/Helpers\""))
        #expect(script.contains("\"$HELPERS/raven-node\""))
        #expect(script.contains("\"$HELPERS/raven-tor-helper\""))
        #expect(script.contains("NEARBY=\"$HELPERS/RavenNearby.app\""))
    }
}
