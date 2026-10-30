import Foundation

/// The app's identity (desktop/README.md, "App identity": one id, three spellings). macOS uses the
/// bundle-id spelling, the same as Windows; Linux uses `io.github.raven_ashco.Raven`.
/// scripts/make-app.sh writes this value into Info.plist (`AppIdentityTests` checks they agree).
public enum AppIdentity {
    public static let bundleID = "io.github.raven-ashco.Raven"

    /// This app's version from its bundle (`CFBundleShortVersionString`, which scripts/make-app.sh
    /// writes from the file VERSION); nil outside a bundle (`swift run`, snapshots).
    public static var bundleVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The version the app shows (About, Settings > Updates): the app's own, else the engine's
    /// (`app.info`). They differ when only the app changed, e.g. app 0.1.1 on raven-core 0.1.0.
    public static func shownVersion(bundle: String?, engine: String?) -> String? {
        if let own = bundle?.trimmingCharacters(in: .whitespaces), !own.isEmpty { return own }
        return engine
    }
}
