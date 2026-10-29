import SwiftUI

/// Sidebar (the mark and heartbeat, You, search, friends, groups, Add a friend, the pages) and the
/// right side: the open chat, a group, a network page or Settings.
public struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.ravenSnapshot) private var snapshot

    public init() {}

    public var body: some View {
        if snapshot {
            // ImageRenderer cannot draw NSSplitView; the same two columns side by side.
            HStack(spacing: 0) {
                SidebarView().frame(width: Theme.shared.layout.sidebarWidth)
                VRule()
                DetailArea()
            }
        } else {
            NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: Theme.shared.layout.sidebarMinWidth,
                                                    ideal: Theme.shared.layout.sidebarWidth, max: 340)
            } detail: {
                DetailArea()
            }
            .navigationTitle(model.windowTitle)
        }
    }
}

extension AppModel {
    /// The window's title: the open chat's name, or the page (Calm: "Alex", "Network", "Settings").
    public var windowTitle: String {
        switch page {
        case .chat: return selectedContact?.name ?? tr(.appName)
        case .group: return selectedGroup?.name ?? tr(.appName)
        case .network: return tr(.networkTitle)
        case .checkNetwork: return tr(.networkCheckTitle)
        case .security: return tr(.securityTitle)
        case .updates: return tr(.updatesTitle)
        case .settings: return tr(.settingsTitle)
        }
    }

    /// How many ways to reach friends are on now (`network.status`; nil until it was read).
    public var waysOn: Int? {
        guard let carriers = network.status?.carriers else { return nil }
        return carriers.filter { $0.state == .on || $0.state == .lab }.count
    }

    /// The path kind of the newest message with a path in a friend's chat (the sidebar's path icon).
    public func lastPathKind(_ address: String) -> String? {
        messages[address]?.last(where: { ($0.pathKind ?? "").isEmpty == false })?.pathKind
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BrandRow()
            YouRow()
            SearchField()
            RScroll {
                VStack(alignment: .leading, spacing: 1) {
                    SectionLabel(tr(.homeFriends)).padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                    if model.contacts.isEmpty {
                        Text(tr(.homeNoFriends)).font(RFont.caption).foregroundColor(p.textSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    ForEach(model.filteredContacts) { contact in
                        FriendRow(contact: contact)
                    }
                    GroupsSidebarSection()
                }
            }
            SidebarAddButtons()
            BottomNav()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(p.sidebar)
    }
}

/// The mark and "Raven", with the heartbeat: the dot beats once on each successful status check
/// (`status_ok`) and the text says how long ago that was. Opens the Network panel.
struct BrandRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @ViewState private var beat: CGFloat = 0

    var body: some View {
        let hb = Display.heartbeat(node: model.node, lastOk: model.lastStatusOk, now: clock.now)
        HStack(spacing: 10) {
            RavenMark(size: 26, color: p.textPrimary)
            Text(tr(.appName)).font(RFont.brand).tracking(0.3)
            Spacer(minLength: 4)
            Button { model.presentNetwork() } label: {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().stroke((hb.ok ? p.successFill : p.dangerFill).opacity(0.55), lineWidth: 1.5)
                            .scaleEffect(1 + beat * 1.3).opacity(Double(1 - beat) * (beat > 0 ? 1 : 0))
                        Circle().fill(hb.ok ? p.successFill : p.dangerFill)
                            .scaleEffect(1 + (beat > 0 && beat < 0.5 ? 0.35 : 0))
                    }
                    .frame(width: 7, height: 7)
                    Text(hb.text).font(.system(size: 11)).foregroundColor(hb.ok ? p.textSecondary : p.danger)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .buttonStyle(.plain)
            .help(tr(.netTitle))
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .onChange(of: model.heartbeatPulse) { _ in
            pulse(motionOff: motionOff, .easeOut(duration: Theme.shared.motion.heartbeatPulse),
                  start: { beat = 0.01 }, end: { beat = 1 })
        }
    }
}

/// You: your initial, "You" (or "You · name") and your fingerprint; opens your security words and card.
struct YouRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let you = Display.you(model.identity, name: model.settings.displayName)
        SidebarRowButton(selected: false, action: { model.presentYou() }) {
            HStack(spacing: 10) {
                InitialAvatar(initial: String(tr(.youTitle).prefix(1)),
                              colors: AvatarColors(background: p.accentSoft, foreground: p.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(you.title).font(RFont.label).lineLimit(1)
                    if let fingerprint = you.fingerprint {
                        Text(fingerprint).font(.system(size: 12)).foregroundColor(p.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .help(tr(.youTitle))
        .accessibilityElement(children: .combine)
    }
}

struct SearchField: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.ravenSnapshot) private var snapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(p.textSecondary)
                .accessibilityHidden(true)
            if snapshot {
                Text(model.searchText.isEmpty ? tr(.homeSearch) : model.searchText)
                    .foregroundColor(model.searchText.isEmpty ? p.textSecondary : p.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(tr(.homeSearch), text: $model.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel(tr(.homeSearch))
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.textPrimary.opacity(0.06)))
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}

/// A sidebar row: rounded, a light tint on hover, and the selected row on a card (`surface` with
/// the card shadow), as in the Calm sidebar.
struct SidebarRowButton<Label: View>: View {
    let selected: Bool
    var padding: EdgeInsets = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
    let action: () -> Void
    let label: Label
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @ViewState private var hover = false

    init(selected: Bool, padding: EdgeInsets = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
         action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.selected = selected
        self.padding = padding
        self.action = action
        self.label = label()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.shared.radius.row, style: .continuous)
        Button(action: action) {
            label
                .padding(padding)
                .background {
                    if selected {
                        shape.fill(p.surface).ravenShadow(p.cardShadow)
                    } else if hover {
                        shape.fill(p.textPrimary.opacity(0.05))
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { h in
            if motionOff { hover = h } else { withAnimation(.easeOut(duration: Theme.shared.motion.hover)) { hover = h } }
        }
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

struct FriendRow: View {
    let contact: Contact
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let selected = model.page == .chat && model.selectedAddress == contact.address
        let unread = model.unread[contact.address] ?? 0
        SidebarRowButton(selected: selected, action: { model.select(contact.address) }) {
            HStack(spacing: 10) {
                Avatar(contact, blink: model.presenceBlinks[contact.address] ?? 0,
                       retry: model.retryPulses[contact.address] ?? 0, ring: selected ? p.surface : p.sidebar)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(contact.name).font(RFont.label).lineLimit(1)
                        if !contact.verified {
                            Text(tr(.homeNotVerified)).font(.system(size: 10.5, weight: .semibold)).foregroundColor(p.warning)
                                .lineLimit(1)
                        }
                    }
                    ContactStatusText(contact: contact)
                }
                Spacer(minLength: 0)
                if unread > 0 {
                    UnreadBadge(n: unread)
                        .accessibilityLabel(tr(.homeNewFrom, ["n": String(unread), "name": contact.name]))
                } else if contact.presence == .inTouch, let kind = model.lastPathKind(contact.address) {
                    // How the last message travelled, while the friend is in touch.
                    PathIcon(family: PathFamily.of(kind: kind), size: 13).foregroundColor(p.textTertiary)
                        .help(Display.pathChip(kind: kind, path: nil) ?? "")
                }
            }
        }
        .accessibilityElement(children: .combine)
        // Right-click: rename, check words, routes (E1; the terminal app's friend page has them).
        .contextMenu {
            Button(tr(.contactRename)) { model.presentRename(contact.address) }
            Button(tr(.homeBannerNotVerifiedAction)) { model.presentCheckWords(contact.address) }
            Button(tr(.networkRoutesTitle, ["name": contact.name])) { model.presentRoutes(contact.address) }
        }
    }
}

struct UnreadBadge: View {
    let n: Int
    @Environment(\.palette) private var p

    var body: some View {
        Text("\(n)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(p.onAccent)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(p.accentFill))
    }
}

/// The status line under a friend's name; follows the 1-second clock for "In touch 5 min ago".
struct ContactStatusText: View {
    let contact: Contact
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p

    var body: some View {
        // The row shows "Not verified" beside the name; the line says when you were last in touch.
        let line = Display.statusLine(contact, now: clock.now, verifiedShown: true)
        Text(line.text)
            .font(.system(size: 12))
            .foregroundColor(p.tone(line.tone))
            .lineLimit(1)
    }
}

/// "+ Add a friend" (and "New group…" where groups are available) under the lists.
struct SidebarAddButtons: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            addButton(tr(.homeAddFriend)) { model.presentAddFriend() }
            if model.groupsAvailable {
                addButton(tr(.groupsNew)) { model.presentNewGroup() }
            }
        }
    }

    private func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        SidebarRowButton(selected: false, padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8), action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundColor(p.accent)
        }
    }
}

/// The pages at the bottom of the sidebar: Network ("n ways on"), Security words, Security, Settings.
struct BottomNav: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 1) {
            NavRow(icon: "point.3.connected.trianglepath.dotted", title: tr(.networkTitle),
                   meta: model.waysOn.map { $0 == 1 ? tr(.homeNavWayOn) : tr(.homeNavWaysOn, ["n": String($0)]) },
                   selected: model.page == .network || model.page == .checkNetwork) { model.open(.network) }
            NavRow(icon: "text.alignleft", title: tr(.homeNavWords), selected: false) { model.presentYou() }
            NavRow(icon: "lock", title: tr(.securityTitle), selected: model.page == .security) { model.open(.security) }
            NavRow(icon: "gearshape", title: tr(.settingsTitle), selected: model.page == .settings) { model.openSettings() }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rule() }
    }
}

struct NavRow: View {
    let icon: String
    let title: String
    var meta: String?
    let selected: Bool
    let action: () -> Void
    @Environment(\.palette) private var p

    init(icon: String, title: String, meta: String? = nil, selected: Bool, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.meta = meta
        self.selected = selected
        self.action = action
    }

    var body: some View {
        SidebarRowButton(selected: selected, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8), action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 16)
                    .foregroundColor(selected ? p.accent : p.textSecondary)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 4)
                if let meta { Text(meta).font(.system(size: 11)).foregroundColor(p.textTertiary).lineLimit(1) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
