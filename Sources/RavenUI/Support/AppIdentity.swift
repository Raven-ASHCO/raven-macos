import Foundation

/// The app's identity (desktop/README.md, "App identity": one id, three spellings). macOS uses the
/// bundle-id spelling, the same as Windows; Linux uses `io.github.raven_ashco.Raven`.
/// scripts/make-app.sh writes this value into Info.plist (`AppIdentityTests` checks they agree).
public enum AppIdentity {
    public static let bundleID = "io.github.raven-ashco.Raven"
}
