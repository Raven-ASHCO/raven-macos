import SwiftUI
import AppKit
import RavenUI

/// Raven for macOS: the main window (with Settings in it, Calm design) and the menu bar extra.
///
/// The app runs on raven-client (RavenClientEngine) when the engine is linked (RAVEN_ENGINE, see
/// Package.swift), otherwise on MissingEngine (the engine-missing screen). The in-memory MockRaven
/// runs only in a demo build or a debug build started with RAVEN_DEMO=1 (EngineFactory).
@main
struct RavenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel(engine: EngineFactory.makeDefault(), preferences: .standard)

    var body: some Scene {
        Window(tr(.appName), id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.clock)
                .preferredColorScheme(model.themeChoice.scheme)
                .onAppear {
                    delegate.model = model
                    DispatchQueue.main.async { delegate.bringMainWindowForward() }
                    #if DEBUG
                    // RAVEN_DEBUG_SNAPSHOT_DIR: render the network screens of this run, then quit.
                    DebugSnapshotHook.runIfAsked(model)
                    #endif
                }
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            RavenCommands(model: model)
        }

        MenuBarExtra {
            MenuBarRoot(model: model)
        } label: {
            MenuBarLabel()
                .environmentObject(model)
                .environmentObject(model.clock)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Hosts the menu bar content and gives it a way to bring the main window forward.
struct MenuBarRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarContent(openMain: {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        })
        .environmentObject(model)
        .environmentObject(model.clock)
        .ravenTheme(reducedMotion: model.settings.reducedMotion)
        .preferredColorScheme(model.themeChoice.scheme)
    }
}

struct RavenCommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // View > Show Sidebar / Hide Sidebar, so a hidden sidebar always comes back (E1), titled by
        // what it does now (the system's item kept "Show Sidebar" while the sidebar was shown).
        CommandGroup(replacing: .sidebar) {
            Button(Display.sidebarMenuTitle(shown: model.sidebarShown)) { model.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(model.phase != .ready)
        }
        CommandGroup(replacing: .newItem) {
            Button(tr(.trayAddFriend)) { model.presentAddFriend() }
                .keyboardShortcut("n")
                .disabled(model.phase != .ready)
        }
        // Settings live in the main window (Calm): Cmd-, opens them there.
        CommandGroup(replacing: .appSettings) {
            Button(tr(.settingsTitle) + "…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                model.openSettings()
            }
            .keyboardShortcut(",")
            .disabled(model.phase != .ready)
        }
        CommandGroup(after: .appSettings) {
            Button(tr(.trayLock)) { model.requestLock() }
                .keyboardShortcut("l", modifiers: [.command, .control])
                .disabled(model.phase != .ready || !model.canLock)
        }
        // The network pages, also in the sidebar.
        CommandMenu(tr(.networkTitle)) {
            Button(tr(.networkTitle)) { model.open(.network) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button(tr(.networkCheckTitle)) { model.open(.checkNetwork) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button(tr(.securityTitle)) { model.open(.security) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button(tr(.updatesTitle)) { model.open(.updates) }
                .keyboardShortcut("4", modifiers: [.command, .option])
        }
    }
}

/// Quit follows Settings > When I quit (keep running, stop if this app started it, or ask).
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    /// Opened from the kit, a login item or the Finder, the window came up behind other windows,
    /// on another Space (E1): the app comes to the front with its main window on this Space.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NetworkKind.shared.start()
        DispatchQueue.main.async { self.bringMainWindowForward() }
    }

    private var broughtForward = false

    /// Once per launch: activate the app and bring the main window to the front on the active Space
    /// (only for that move: the window keeps its own Space afterwards).
    func bringMainWindowForward() {
        guard !broughtForward else { return }
        let windows = NSApp.windows.filter { $0.canBecomeMain && $0.isVisible }
        guard !windows.isEmpty else { return }
        broughtForward = true
        NSApp.activate(ignoringOtherApps: true)
        for window in windows {
            let had = window.collectionBehavior.contains(.moveToActiveSpace)
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            if !had {
                DispatchQueue.main.async { window.collectionBehavior.remove(.moveToActiveSpace) }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        return MainActor.assumeIsolated { model.quitReply() }
    }

    /// The menu bar extra keeps Raven reachable after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
