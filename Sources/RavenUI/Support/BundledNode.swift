import Foundation

/// The raven-node an app bundle carries (scripts/make-app.sh): `Contents/Helpers/raven-node`, next to
/// `raven-tor-helper` and `RavenNearby.app`, which raven-node finds next to itself.
///
/// The engine starts the program `RAVEN_NODE_BIN` names, else the `raven-node` next to the app's
/// executable (`Contents/MacOS`). So before the engine's first call the app sets `RAVEN_NODE_BIN` to
/// the bundled one, unless the variable is already set (a developer's own raven-node wins) or the app
/// is not a bundle with one (`swift run`, tests): then nothing changes.
public enum BundledNode {
    public static let environmentKey = "RAVEN_NODE_BIN"
    /// Inside the .app; scripts/make-app.sh copies raven-node here (`BundledNodeTests` checks they agree).
    public static let relativePath = "Contents/Helpers/raven-node"

    /// The bundled raven-node of the app at `bundleURL`, or nil when the variable is set, the app is
    /// not an .app bundle or the bundle has no executable raven-node.
    public static func path(bundleURL: URL, environment: [String: String],
                            isExecutable: (String) -> Bool) -> String? {
        if let set = environment[environmentKey], !set.isEmpty { return nil }
        guard bundleURL.pathExtension == "app" else { return nil }
        let node = bundleURL.appendingPathComponent(relativePath).path
        return isExecutable(node) ? node : nil
    }

    /// Sets `RAVEN_NODE_BIN` to this app's bundled raven-node (see above) and returns it, or nil when
    /// nothing was set. Call it before the engine's first call: the engine reads the variable when it
    /// starts raven-node, and no engine thread runs yet.
    @discardableResult
    public static func useBundledNode(bundle: Bundle = .main,
                                      environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let node = path(bundleURL: bundle.bundleURL, environment: environment,
                              isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        setenv(environmentKey, node, 0)
        return node
    }
}
