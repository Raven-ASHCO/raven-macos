#if DEBUG
import SwiftUI
import AppKit

/// A debug build's snapshot hook for the running app: with `RAVEN_DEBUG_SNAPSHOT_DIR=<folder>` it
/// renders, from the live model and the engine it runs on, the Network page (light and dark), the
/// consent sheet for carrying mail for friends (light and dark) and the Check network page (light and
/// dark) into that folder with `ImageRenderer`, prints the files, and quits. It never asks the router
/// (no Local Network prompt), never sends `agreed`, and starts no raven-node.
///
/// A new profile stays on the welcome screen, unless `RAVEN_DEBUG_SNAPSHOT_SETUP=1` and the profile is
/// a throwaway one (`RAVEN_DATA_DIR` set, `RAVEN_ALLOW_EPHEMERAL_DATA_DIR=1`, file-backed identity
/// store): then it is set up first with receiving off and the name "max", as setup would.
/// Compiled only into debug builds.
@MainActor
public enum DebugSnapshotHook {
    private static var started = false

    public static func runIfAsked(_ model: AppModel, environment env: [String: String] = ProcessInfo.processInfo.environment) {
        guard !started, let dir = env["RAVEN_DEBUG_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        started = true
        Task { @MainActor in
            let files = await render(model, to: URL(fileURLWithPath: dir, isDirectory: true), env)
            for file in files { print(file.path) }
            print("\(files.count) snapshots of the running app written to \(dir)")
            NSApp.terminate(nil)
        }
    }

    static func throwaway(_ env: [String: String]) -> Bool {
        !(env["RAVEN_DATA_DIR"] ?? "").isEmpty && env["RAVEN_ALLOW_EPHEMERAL_DATA_DIR"] == "1"
            && env["RAVEN_IDENTITY_BACKEND"] == "locked-file"
    }

    static func render(_ model: AppModel, to directory: URL, _ env: [String: String]) async -> [URL] {
        for _ in 0..<400 where model.phase == .loading {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if model.phase == .welcome, env["RAVEN_DEBUG_SNAPSHOT_SETUP"] == "1", throwaway(env) {
            model.settings = (try? await model.engine.setSettings(["receive": false])) ?? model.settings
            _ = try? await model.engine.createIdentity(displayName: "max")
            await model.finishSetup()
        }
        guard model.phase == .ready else {
            print("RAVEN_DEBUG_SNAPSHOT_DIR: the profile isn't ready (\(model.phase)); nothing rendered")
            return []
        }
        await model.network.refresh()
        await model.refreshLock()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [URL] = []
        func shot(_ name: String, width: CGFloat, height: CGFloat?, _ view: AnyView) {
            let s = SnapshotCatalog.Shot(name: name, width: width, height: height, model: model, view: view)
            for scheme in [ColorScheme.light, .dark] {
                guard let image = SnapshotCatalog.render(s, scheme: scheme) else { continue }
                let url = directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                if (try? SnapshotCatalog.writePNG(image, to: url)) != nil { written.append(url) }
            }
        }

        model.open(.network)
        shot("app-network", width: 920, height: 2300, AnyView(RootView()))
        // The consent sheet as it opens before anything is sent (rendered on its own; no yes is given).
        shot("app-consent-carry-for-friends", width: 520, height: nil, AnyView(ConsentSheet(setting: "carry_for_friends")))
        await model.network.runCheck()
        model.open(.checkNetwork)
        shot("app-check-network", width: 920, height: 1000, AnyView(RootView()))
        return written
    }
}
#endif
