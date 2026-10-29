import SwiftUI
import AppKit

/// The menu bar extra's label: the Raven mark (a template image, so it follows the menu bar). While
/// Raven listens it breathes in four soft steps driven by the 1-second clock (no extra timer);
/// with reduced motion it stays still.
public struct MenuBarLabel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel

    public init() {}

    public var body: some View {
        let listening = model.node?.listening != nil && model.node?.running == true
        let still = model.settings.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let steps: [Double] = [1.0, 0.8, 0.6, 0.8]
        Image(nsImage: RavenResources.mark(size: 18, template: true))
            .opacity(listening && !still ? steps[clock.tick % steps.count] : 1)
            .accessibilityLabel(tr(.appName))
            .onAppear { model.start() }
    }
}

/// The menu: status, friends, Open, Add a friend, Lock, and the two ways to quit.
public struct MenuBarContent: View {
    let openMain: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @ViewState private var beat: CGFloat = 1

    public init(openMain: @escaping () -> Void) { self.openMain = openMain }

    public var body: some View {
        let node = model.node
        let listening = node?.running == true && node?.listening != nil && node?.localOnly == false
        let heartbeat = Display.heartbeat(node: node, lastOk: model.lastStatusOk, now: clock.now)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                RavenMark(size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(listening ? tr(NetworkKind.shared.isWiFi ? .trayListening : .trayListeningNetwork) : tr(.trayNotListening)).font(RFont.bodyBold)
                    HStack(spacing: 4) {
                        Text("♥").foregroundColor(heartbeat.ok ? p.success : p.danger).scaleEffect(beat)
                        Text(heartbeat.ok ? tr(.trayBackground) : tr(.homeHeartbeatDown))
                            .foregroundColor(p.textSecondary)
                    }
                    .font(RFont.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            separator
            if model.phase == .ready {
                ForEach(model.contacts) { c in
                    MenuRow(action: { model.select(c.address); openMain() }) {
                        HStack(spacing: 8) {
                            PresenceDot(presence: c.presence)
                            Text(Display.menuLine(c, unread: model.unread[c.address] ?? 0, now: clock.now)).lineLimit(1)
                        }
                    }
                }
                if !model.contacts.isEmpty { separator }
            }
            MenuRow(icon: "macwindow", title: tr(.trayOpen), action: openMain)
            MenuRow(icon: "person.badge.plus", title: tr(.trayAddFriend)) {
                openMain()
                model.presentAddFriend()
            }
            .disabled(model.phase != .ready)
            // Locking needs Lock while running (Lock v2) or the privacy pack (`privacy.state` available).
            MenuRow(icon: "lock", title: tr(.trayLock)) {
                // The question shows in the main window.
                openMain()
                model.requestLock()
            }
                .disabled(model.phase != .ready || !model.canLock)
            separator
            MenuRow(title: tr(.trayQuitWindow)) { Task { await model.quitFromMenu(stopNode: false) } }
            MenuRow(title: tr(.trayQuitAll), secondary: true) { Task { await model.quitFromMenu(stopNode: true) } }
        }
        .padding(6)
        .frame(width: 310)
        .background(p.surface)
        .onChange(of: model.heartbeatPulse) { _ in
            pulse(motionOff: motionOff, .easeOut(duration: Theme.shared.motion.heartbeatPulse),
                  start: { beat = 1.5 }, end: { beat = 1 })
        }
    }

    private var separator: some View {
        Rule().padding(.vertical, 4).padding(.horizontal, 2)
    }
}

/// One row of the menu, highlighted under the pointer.
struct MenuRow<Label: View>: View {
    let action: () -> Void
    let label: Label
    var secondary = false
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hover = false

    init(action: @escaping () -> Void, secondary: Bool = false, @ViewBuilder label: () -> Label) {
        self.action = action
        self.secondary = secondary
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(RFont.body)
                .foregroundColor(secondary ? p.textSecondary : p.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover && enabled ? p.accentSoft : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hover = $0 }
    }
}

extension MenuRow where Label == MenuRowLabel {
    init(icon: String? = nil, title: String, secondary: Bool = false, action: @escaping () -> Void) {
        self.init(action: action, secondary: secondary) { MenuRowLabel(icon: icon, title: title) }
    }
}

struct MenuRowLabel: View {
    let icon: String?
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).frame(width: 16).accessibilityHidden(true)
            }
            Text(title)
        }
    }
}
