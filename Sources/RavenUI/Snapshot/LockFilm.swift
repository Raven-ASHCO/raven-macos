#if DEBUG || RAVEN_MOCK
import SwiftUI

/// The lock scene's films, frame by frame (debug builds only): the scene's own frames rendered with
/// `ImageRenderer` at 30 a second on MockRaven, never a screen recording and never the running app.
/// scripts/make-lock-film.sh turns them into MP4s.
///
/// - lock: Lock's question by day (1 s), the sheet closes (0.2 s), then the locked screen: its card
///   fades in (`lockedFade`) while the night comes down (2 s), then the raven asleep (6 s).
/// - unlock: asleep (1 s), then Unlock worked: the night rises, the head turns back and the raven
///   stretches until the main window opens (`RavenMotion.wake`), then the main window (0.5 s).
@MainActor
public enum LockFilm {
    public static let fps = 30.0
    static let size = CGSize(width: 1200, height: 760)

    /// Renders every film in light and dark into `directory/<film>-<light|dark>/00001.png …`; returns
    /// the folders written.
    public static func renderFrames(to directory: URL) async throws -> [URL] {
        let (open, _) = await SnapshotCatalog.readyModel(after: 2, network: .lab)
        await open.refreshLock()
        let (locked, _) = await SnapshotCatalog.readyModel(after: 2, network: .lab)
        await locked.lockNow()
        var folders: [URL] = []
        for (name, frames) in [("lock", lockFrames(open: open, locked: locked)),
                               ("unlock", unlockFrames(open: open, locked: locked))] {
            for scheme in [ColorScheme.light, .dark] {
                let folder = directory.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light")")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for (i, frame) in frames.enumerated() {
                    let shot = SnapshotCatalog.Shot(name: name, width: size.width, height: size.height, model: frame.model,
                                                    view: frame.view, dark: true, scale: 1)
                    guard let image = SnapshotCatalog.render(shot, scheme: scheme) else {
                        throw RavenError.internalError("ImageRenderer returned no image for \(name) frame \(i)")
                    }
                    try SnapshotCatalog.writePNG(image, to: folder.appendingPathComponent(String(format: "%05d.png", i + 1)))
                }
                folders.append(folder)
            }
        }
        return folders
    }

    struct Frame {
        let model: AppModel
        let view: AnyView
    }

    static func frames(_ seconds: Double) -> Int { Int((seconds * fps).rounded()) }

    static func lockFrames(open: AppModel, locked: AppModel) -> [Frame] {
        var out: [Frame] = []
        for i in 0..<frames(1) {
            let t = Double(i) / fps
            out.append(Frame(model: open, view: AnyView(SheetOverWindow(sceneAt: t, closing: 0))))
        }
        let close = frames(0.2)
        for i in 0..<close {
            let t = 1 + Double(i) / fps
            out.append(Frame(model: open, view: AnyView(SheetOverWindow(sceneAt: t, closing: Double(i + 1) / Double(close)))))
        }
        for i in 0..<frames(LockScene.curtainDown + 6) {
            let x = Double(i) / fps
            out.append(Frame(model: locked, view: AnyView(LockedFrame(lockedFor: x, wokeFor: nil,
                                                                      fadeIn: min(1, x / Theme.shared.motion.lockedFade)))))
        }
        return out
    }

    static func unlockFrames(open: AppModel, locked: AppModel) -> [Frame] {
        var out: [Frame] = []
        // Asleep, a "z" rising (0.3 s into its third round).
        let asleepFrom = LockScene.curtainDown + 2 * RavenMotion.zEvery + 0.3
        for i in 0..<frames(1) {
            out.append(Frame(model: locked, view: AnyView(LockedFrame(lockedFor: asleepFrom + Double(i) / fps, wokeFor: nil, fadeIn: 1))))
        }
        for i in 0...frames(RavenMotion.wake) {
            out.append(Frame(model: locked, view: AnyView(LockedFrame(lockedFor: nil, wokeFor: Double(i) / fps, fadeIn: 1))))
        }
        for _ in 0..<frames(0.5) {
            out.append(Frame(model: open, view: AnyView(RootView())))
        }
        return out
    }
}

/// Lock's question as a sheet on the main window (ImageRenderer cannot draw a real sheet): hung from
/// the top over a light scrim; `closing` 0...1 slides it up and away.
private struct SheetOverWindow: View {
    let sceneAt: Double
    let closing: Double
    @Environment(\.palette) private var p

    var body: some View {
        let e = closing * closing
        ZStack(alignment: .top) {
            RootView()
            Color.black.opacity(0.18 * (1 - e))
            ConfirmLockSheet(sceneAt: sceneAt)
                .clipShape(RoundedRectangle(cornerRadius: Theme.shared.radius.window, style: .continuous))
                .ravenShadow(p.sheetShadow)
                .offset(y: -440 * e)
                .opacity(1 - e)
        }
    }
}

/// The locked screen at a moment of the night coming down or rising; `fadeIn` fades its card in over
/// the window background (`lockedFade`), as the app does.
private struct LockedFrame: View {
    let lockedFor: Double?
    let wokeFor: Double?
    let fadeIn: Double
    @Environment(\.palette) private var p

    var body: some View {
        let f = 1 - pow(1 - fadeIn, 3)
        LockedView(lockedFor: lockedFor, wokeFor: wokeFor)
            .overlay(p.background.opacity(1 - f))
    }
}
#endif
