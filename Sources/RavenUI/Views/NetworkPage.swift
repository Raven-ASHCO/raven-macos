import SwiftUI

/// The main window's right side: the open chat, or a network page picked in the sidebar.
struct DetailArea: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.motionOff) private var motionOff

    var body: some View {
        VStack(spacing: 0) {
            let switches = NetworkModel.labSwitches(status: model.network.status, node: model.node)
            // The Network page shows the full banner itself.
            if !switches.isEmpty && model.page != .network {
                LabBanner(switches: switches, compact: true)
            }
            // A page or chat comes in (Calm `viewIn`: up from 6 points, fading in).
            ZStack {
                Group {
                    switch model.page {
                    case .chat: ChatArea()
                    case .group: GroupChatArea()
                    case .settings: SettingsView()
                    case .network: NetworkPage(net: model.network)
                    case .checkNetwork: CheckNetworkPage(net: model.network)
                    case .security: SecurityPage(net: model.network)
                    case .updates: UpdatesPage(net: model.network)
                    }
                }
                .id(viewKey)
                .transition(motionOff ? .identity : .asymmetric(insertion: .offset(y: 6).combined(with: .opacity),
                                                                removal: .identity))
            }
            .animation(motionOff ? nil : Theme.shared.curve("arrive", Theme.shared.motion.viewIn), value: viewKey)
        }
    }

    /// Which view is shown: the page, and for a chat which friend or group.
    private var viewKey: String {
        switch model.page {
        case .chat: return "chat-" + (model.selectedAddress ?? "")
        case .group: return "group-" + (model.selectedGroupID ?? "")
        default: return String(describing: model.page)
        }
    }
}

/// A page of the main window (Calm): the page title with its actions on the right, the intro, then
/// the content, 900 pt wide at most and centred.
struct PageFrame<Actions: View, Content: View>: View {
    let title: String
    let intro: String?
    let actions: Actions
    let content: Content
    @Environment(\.palette) private var p

    init(_ title: String, intro: String? = nil, @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content) {
        self.title = title
        self.intro = intro
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        RScroll {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(RFont.pageTitle).tracking(Theme.shared.type.pageTitle.tracking)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    actions
                }
                .padding(.bottom, 4)
                if let intro {
                    Text(intro).font(.system(size: 14)).foregroundColor(p.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.bottom, 20)
                }
                VStack(alignment: .leading, spacing: 22) { content }
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 40)
            .frame(maxWidth: Theme.shared.layout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(p.background)
    }
}

/// A group of rows on a page (Calm): the section label, then a card.
struct PageSection<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.palette) private var p

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title).padding(.leading, 2)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .calmCard()
        }
    }
}

/// "Technical details": the CLI's own lines and raw counters, one click away and never in the plain
/// words above them (E1: commands and log-like lines read as instructions).
struct TechnicalDetails: View {
    let lines: [String]
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    /// nil: as Settings > Appearance > Show technical details says.
    @ViewState private var toggled: Bool?
    private var shown: Bool { toggled ?? model.showTechnical }

    var body: some View {
        let lines = self.lines.map { Sanitizer.line($0, maxLength: 400) }.filter { !$0.isEmpty }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Button(tr(.messageTechnicalDetails)) { toggled = !shown }
                    .buttonStyle(RButtonStyle(.plain))
                    .font(RFont.small)
                    .accessibilityAddTraits(shown ? .isSelected : [])
                if shown {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(RFont.mono).foregroundColor(p.textSecondary).selectable()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A way's state chip (On, Off, Preview, Lab only, Not on this computer).
struct StateChip: View {
    let state: WayState

    var body: some View {
        let s = Display.wayState(state)
        Pill(text: s.text, tone: s.tone)
    }
}

/// "Lab switches on": shown in a developer build whose engine sees `RAVEN_LAB_*` switches; a release
/// engine reads none and lists none, so a release build never shows it.
struct LabBanner: View {
    let switches: [String]
    var compact = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let title = tr(.networkLabBanner, ["switches": switches.joined(separator: ", ")])
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "flask").foregroundColor(p.warning).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                let label = Text(title).font(RFont.smallish.weight(.semibold)).foregroundColor(p.warning)
                if compact {
                    // One line above every page but Network (which shows the whole list). A wrapping
                    // text here, outside a scroll view, made the split view's layout never settle:
                    // the whole window, sidebar included, stayed blank on the chat and other pages.
                    label.lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(switches.joined(separator: ", "))
                } else {
                    label.fixedSize(horizontal: false, vertical: true)
                }
                if !compact {
                    Text(tr(.networkLabBody)).font(RFont.small).foregroundColor(p.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if compact && model.page != .network {
                Button(tr(.networkTitle)) { model.open(.network) }
                    .buttonStyle(RButtonStyle(.plain))
                    .font(RFont.small)
            }
        }
        .padding(.horizontal, compact ? 12 : 10)
        .padding(.vertical, compact ? 5 : 8)
        .background(compact ? AnyView(p.surfaceMuted) : AnyView(
            RoundedRectangle(cornerRadius: Theme.shared.radius.control).fill(p.surfaceMuted)))
        .overlay(compact ? AnyView(Rule().frame(maxHeight: .infinity, alignment: .bottom)) : AnyView(
            RoundedRectangle(cornerRadius: Theme.shared.radius.control).stroke(p.warning.opacity(0.6), lineWidth: 0.5)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Network page

/// Every way from `network.status`: name, state chip, the plain reason, a switch where `network.set`
/// changes it, and Details; then ports, port mapping, relays, nearby, who carries mail, the
/// help-friends flags, hide my IP and the protections.
struct NetworkPage: View {
    @ObservedObject var net: NetworkModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        PageFrame(tr(.networkTitle), intro: tr(.networkPageIntro)) {
            Button(tr(.networkRefresh)) { Task { await net.refresh() } }
                .buttonStyle(RButtonStyle(.secondary, compact: true))
                .keyboardShortcut("r", modifiers: .command)
        } content: {
            let switches = NetworkModel.labSwitches(status: net.status, node: model.node)
            if !switches.isEmpty { LabBanner(switches: switches) }
            if let error = net.loadError { ErrorNote(error) }
            if !net.changes.isEmpty { ChangesNote(net: net) }
            if let status = net.status {
                ThisComputerSection(status: status)
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(tr(.netWays)).padding(.leading, 2)
                    WayGrid(ways: status.carriers, status: status, net: net)
                }
                CarrySection(status: status, net: net)
                HelpSection(status: status, net: net)
                if let protections = status.protections, !protections.isEmpty {
                    PageSection(tr(.networkProtections)) {
                        ForEach(Array(protections.enumerated()), id: \.element.id) { i, way in
                            if i > 0 { Rule() }
                            WayRow(way: way, status: status, net: net)
                        }
                    }
                }
                AboutLines()
            } else if net.loadError == nil {
                Spinner()
            }
        }
        .task { await net.refresh() }
    }
}

/// What the last change did, in the engine's words.
struct ChangesNote: View {
    @ObservedObject var net: NetworkModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tr(.networkChanged)).font(RFont.smallish.weight(.semibold))
                Spacer()
                Button(tr(.commonClose)) { net.dismissChanges() }
                    .buttonStyle(RButtonStyle(.plain))
                    .font(RFont.small)
            }
            ForEach(Array(net.changes.enumerated()), id: \.offset) { _, change in
                Text(change.effect).font(RFont.smallish).fixedSize(horizontal: false, vertical: true)
                if change.applies == "restart" {
                    Text(tr(.networkChangedRestart)).font(RFont.small).foregroundColor(p.warning)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.shared.radius.control).fill(p.accentSoft.opacity(0.5)))
        .accessibilityElement(children: .contain)
    }
}

/// This computer (Calm): the mark with its radar (two rings spread once per successful status check,
/// `status_ok`), the listening line, the background program, the port and addresses, the heartbeat,
/// and Check network.
struct ThisComputerSection: View {
    let status: NetworkStatus
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p

    var body: some View {
        let chip = Display.listening(model.node)
        let hb = Display.heartbeat(node: model.node, lastOk: model.lastStatusOk, now: clock.now)
        HStack(alignment: .center, spacing: 18) {
            Radar(pulse: model.heartbeatPulse)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(.netThisComputer)).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    if chip.busy { Spinner(size: 11) }
                    Text(chip.text).foregroundColor(chip.tone == .success ? p.textSecondary : p.tone(chip.tone))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 13))
                if model.node?.running == true {
                    Text(Display.process(model.node)).font(.system(size: 13)).foregroundColor(p.textSecondary)
                } else {
                    // The line above already says it isn't running.
                    Button(tr(.netStart)) { Task { await model.startNode(); await model.network.refresh() } }
                        .buttonStyle(RButtonStyle(.secondary, compact: true))
                }
                // While raven-node runs, the listening line already gives the port it really uses; the
                // profile's port is said only while nothing listens.
                if let port = NetworkModel.profilePortLine(status: status, node: model.node) {
                    small(tr(.networkThisComputerPort, ["port": String(port)]))
                }
                let listening = (status.listening ?? []).map { Sanitizer.line($0, maxLength: 64) }
                small(listening.isEmpty ? tr(.networkThisComputerNotListening)
                      : tr(.networkThisComputerListening, ["addr": listening.joined(separator: ", ")]))
                if let addr = model.node?.address { small(tr(.netAddress, ["addr": addr])) }
                if status.policyUnreadable == true {
                    Text(tr(.networkThisComputerPolicyUnreadable)).font(.system(size: 12)).foregroundColor(p.warning)
                }
                HStack(spacing: 6) {
                    Circle().fill(hb.ok ? p.successFill : p.dangerFill).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(hb.text).foregroundColor(hb.ok ? p.success : p.danger)
                }
                .font(.system(size: 12))
                .padding(.top, 3)
            }
            Spacer(minLength: 8)
            Button(tr(.networkCheckTitle) + "…") { model.open(.checkNetwork) }
                .buttonStyle(RButtonStyle(.secondary))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .calmCard()
        .accessibilityElement(children: .contain)
    }

    private func small(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundColor(p.textSecondary).selectable()
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The mark with two rings that spread once per successful status check (honest motion).
struct Radar: View {
    let pulse: Int
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @ViewState private var spread: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle().strokeBorder(p.successFill, lineWidth: 1.5)
                    .scaleEffect(0.4 + 0.75 * spread)
                    .opacity(spread >= 1 ? 0 : 0.8 * Double(1 - spread))
                    .animation(motionOff ? nil : .easeOut(duration: Theme.shared.motion.radarPulse).delay(Double(i) * 0.35), value: spread)
            }
            RavenMark(size: 30, color: p.textPrimary)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
        .onChange(of: pulse) { _ in
            guard !motionOff else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { spread = 0 }
            DispatchQueue.main.async { spread = 1 }
        }
    }
}

/// The ways as cards, two side by side where the page is wide enough.
struct WayGrid: View {
    let ways: [NetworkWay]
    let status: NetworkStatus
    @ObservedObject var net: NetworkModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top),
                                GridItem(.flexible(), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                cards
            }
            .frame(minWidth: 620)
            VStack(spacing: 12) { cards }
        }
    }

    private var cards: some View {
        ForEach(ways) { way in
            WayRow(way: way, status: status, net: net, card: true)
        }
    }
}

/// One way (or protection). As a card (Calm Network page): the way's icon on a tint of its path
/// colour, its name and state chip, its switch, the plain reason, whether it is in use now, its extras.
struct WayRow: View {
    let way: NetworkWay
    let status: NetworkStatus
    @ObservedObject var net: NetworkModel
    var card = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let setting = NetworkModel.setting(forWay: way.id)
        let toggle = NetworkModel.toggle(for: way)
        let name = way.id == "tor" ? tr(.networkTorName) : (way.name.map { Sanitizer.line($0, maxLength: 80) } ?? way.id)
        let family = PathFamily.of(way: way.id)
        let dim = card && [.off, .preview, .notOnThisOs].contains(way.state)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                if card {
                    PathIcon(family: family, size: 18)
                        .foregroundColor(family.color(p))
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(family.color(p).opacity(0.12)))
                        .saturation(dim ? 0.2 : 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    if let reason = way.reason, !reason.isEmpty {
                        Text(reason).font(.system(size: 12.5)).foregroundColor(p.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // One state per row: the chip says it; "Not in use now" only under a way that is on;
                    // the green dot while raven-node says it is in use.
                    HStack(spacing: 6) {
                        if way.running == true && Display.runningNote(state: way.state, running: way.running) == nil {
                            Circle().fill(p.successFill).frame(width: 7, height: 7).accessibilityHidden(true)
                        }
                        StateChip(state: way.state)
                        // Tor: its own state, as raven-node reports it, in the Tor colour.
                        if way.id == "tor", let tor = status.tor {
                            let phase = Display.torPhase(tor)
                            Text(phase.text).font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(phase.tone == .warning ? p.warning : family.color(p))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(family.color(p).opacity(0.12)))
                                .accessibilityLabel(tr(.networkTorName) + ": " + phase.text)
                        }
                        if let note = Display.runningNote(state: way.state, running: way.running) {
                            Text(note).font(.system(size: 12)).foregroundColor(p.textSecondary)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 8)
                if toggle.shown, let setting {
                    RSwitch(name, isOn: Binding(
                        get: { NetworkModel.isOn(way) },
                        set: { on in Task { await net.toggle(setting, on: on) } }
                    ))
                    .disabled(!toggle.enabled || net.busy.contains(setting))
                }
            }
            .opacity(dim ? 0.7 : 1)
            VStack(alignment: .leading, spacing: 4) {
                WayExtras(way: way, status: status, net: net)
                TechnicalDetails(lines: WayRow.technical(way, status))
                if let setting, let rowError = net.rowError, rowError.setting == setting {
                    ErrorNote(rowError.error)
                }
            }
            .padding(.leading, card ? 48 : 0)
        }
        .padding(.horizontal, card ? 18 : 0)
        .padding(.vertical, card ? 16 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(OptionalCard(on: card))
        .accessibilityElement(children: .contain)
    }

    /// What goes under Technical details for a way: the CLI's row, and Bluetooth nearby's raw rows.
    static func technical(_ way: NetworkWay, _ status: NetworkStatus) -> [String] {
        var lines: [String] = []
        if way.id == "nearby" {
            lines += (status.nearby?.rows ?? []).map { "\($0.label): \($0.value)" }
        }
        if let detail = way.detail, !detail.isEmpty, !lines.contains(detail) { lines.append(detail) }
        if way.id == "proxy" { lines += status.proxy?.lines ?? [] }
        if way.id == "p2p" { lines += status.p2pAddresses ?? [] }
        return lines
    }
}

private struct OptionalCard: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.calmCard() } else { content }
    }
}

/// What a way adds below its reason: LAN for a while, ports, the router's answer, relays, the proxy
/// and Bluetooth nearby.
struct WayExtras: View {
    let way: NetworkWay
    let status: NetworkStatus
    @ObservedObject var net: NetworkModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @ViewState private var proxyDraft = ""

    static let lanSpans = ["30m", "1h", "2h", "8h", "24h"]

    var body: some View {
        switch way.id {
        case "lan":
            if let until = status.lanUntilMs {
                Text(tr(.networkThisComputerLanUntil, ["time": TimeText.deadline(ms: until, now: model.now)])).font(RFont.small).foregroundColor(p.warning)
            }
            if way.setting == false {
                let labels = Strings.shared.options(.networkLanForOptions)
                RMenu(tr(.networkLanFor), items: zip(WayExtras.lanSpans, labels).map { span, label in
                    (label: label, action: { Task { await net.lanFor(span) } })
                })
            }
        case "internet":
            if let at = status.internetListen {
                small(tr(.networkThisComputerInternet, ["addr": at]))
            }
        case "port_mapping":
            if let pm = status.portMapping {
                if let router = pm.router, !router.isEmpty { small(tr(.networkPortMappingRouter, ["result": router])) }
                // v4 and v6 are raven-node's words (upnp, none, open, ...); v4_port is the port the router forwards.
                if let v4 = pm.v4, !v4.isEmpty {
                    if let port = pm.v4Port, port > 0 {
                        small(tr(.networkPortMappingV4Port, ["how": v4, "port": String(port)]))
                    } else {
                        small(tr(.networkPortMappingV4, ["how": v4]))
                    }
                }
                if let v6 = pm.v6, !v6.isEmpty { small(tr(.networkPortMappingV6, ["how": v6])) }
                if let state = pm.natPmpPcp { small(tr(.networkPortMappingNatPmpPcp, ["state": Display.wayState(state).text])) }
            }
        case "p2p":
            if let at = status.p2pListen { small(tr(.networkThisComputerP2p, ["addr": at])) }
            relays
            // Addresses friends can use; this computer's own (loopback, link-local) only under Technical
            // details (E1: six rows, loopback ones among them).
            let addrs = Display.p2pAddressesShown(status.p2pAddresses ?? [])
            if !addrs.isEmpty {
                small(tr(.networkP2pAddresses))
                ForEach(addrs, id: \.self) { a in
                    Text(a).font(RFont.mono).foregroundColor(p.textSecondary).lineLimit(1).truncationMode(.middle).selectable()
                }
            }
        case "tor":
            small(tr(.networkWayTor))
            if let tor = status.tor {
                ForEach(Display.torLines(tor), id: \.self) { small($0) }
            }
        case "friend_relay":
            // No consent sheet (the engine asks none): what lending a relay costs, beside its switch.
            small(tr(.networkRelayForFriendsEffect))
        case "proxy":
            if way.state != .preview, let proxy = status.proxy { proxyControls(proxy) }
        default:
            EmptyView()
        }
    }

    private func small(_ text: String) -> some View {
        Text(text).font(RFont.small).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true).selectable()
    }

    @ViewBuilder private var relays: some View {
        let list = status.relays ?? []
        if way.state == .on || way.state == .lab || !list.isEmpty {
            Text(tr(.networkRelaysTitle)).font(RFont.small.weight(.semibold)).padding(.top, 2)
            if list.isEmpty {
                small(tr(.networkRelaysNone))
            }
            ForEach(Array(list.enumerated()), id: \.offset) { _, relay in
                VStack(alignment: .leading, spacing: 0) {
                    Text(relay.relay).font(RFont.mono).lineLimit(1).truncationMode(.middle).selectable()
                    small([relay.state, Display.relaySource(relay, name: { model.contact($0)?.name })]
                        .compactMap { $0 }.joined(separator: " · "))
                }
            }
        }
    }

    @ViewBuilder private func proxyControls(_ proxy: ProxyState) -> some View {
        let current = proxy.setting ?? "auto"
        let options: [(value: String, label: String)] = {
            var o: [(value: String, label: String)] = [("auto", tr(.networkProxyAuto)), ("off", tr(.networkProxyOff))]
            if current != "auto" && current != "off" { o.append((current, current)) }
            return o
        }()
        HStack(spacing: 8) {
            RPicker(options: options, selection: Binding(get: { current }, set: { v in Task { await net.setProxy(v) } }))
            RField(tr(.networkProxyPlaceholder), text: $proxyDraft, mono: true) { save() }
                .frame(maxWidth: 220)
            Button(tr(.networkSave)) { save() }
                .buttonStyle(RButtonStyle(.secondary, compact: true))
                .disabled(proxyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        small(tr(.networkProxyNote))
        if let inUse = proxy.inUse, !inUse.isEmpty { small(tr(.networkProxyInUse, ["proxy": inUse])) }
    }

    private func save() {
        let value = proxyDraft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        proxyDraft = ""
        Task { await net.setProxy(value) }
    }
}

/// Who carries mail: friends who carry yours, carrying for friends (consent first), letters and the
/// relay this computer lends.
struct CarrySection: View {
    let status: NetworkStatus
    @ObservedObject var net: NetworkModel
    @Environment(\.palette) private var p

    var body: some View {
        let carry = status.carry
        PageSection(tr(.networkCarryTitle)) {
            VStack(alignment: .leading, spacing: 4) {
                if let mine = carry?.friendsCarryMine {
                    switch mine.setting {
                    case "on": line(tr(.networkMailMineOn, ["n": String(mine.mailFriends ?? 0)]))
                    case "off": line(tr(.networkMailMineOff))
                    default: line(tr(.networkMailMineNotDecided))
                    }
                    if let offering = mine.offering, offering > 0 {
                        line(tr(.networkCarryOffering, ["n": String(offering), "internet": String(mine.offeringOverInternet ?? 0),
                                                        "reachable": String(mine.offeringReachable ?? 0)]))
                    }
                }
                let forFriends = carry?.carryForFriends
                let custody = status.way("custody")
                let held = custody?.state == .preview && forFriends?.on != true
                Toggle(isOn: Binding(
                    get: { forFriends?.on == true },
                    set: { on in Task { await net.toggle("carry_for_friends", on: on) } }
                )) {
                    Text(tr(.networkCarryForFriends)).font(RFont.bodyBold)
                }
                .toggleStyle(RSwitchStyle())
                .disabled(held || net.busy.contains("carry_for_friends"))
                .padding(.top, 4)
                if held { Text(tr(.netPreview)).font(RFont.small).foregroundColor(p.warning) }
                if let f = forFriends, f.on {
                    line(tr(.networkCarryHeld, ["n": String(f.heldMessages ?? 0), "size": Display.bytes(f.heldBytes ?? 0)]))
                    TechnicalDetails(lines: f.handoffLines ?? [])
                }
                if let rowError = net.rowError, rowError.setting == "carry_for_friends" { ErrorNote(rowError.error) }
                if let letters = carry?.lettersLeft, !letters.isEmpty {
                    Text(tr(.networkCarryLetters)).font(RFont.small.weight(.semibold)).padding(.top, 2)
                    ForEach(Array(letters.enumerated()), id: \.offset) { _, l in line(l) }
                }
                if let relay = carry?.relayForFriends, relay.offering == true {
                    line(tr(.networkCarryRelayOffered, ["n": String(relay.offeredTo ?? 0)]))
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(RFont.smallish).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// The node policy flags (`bridge`, `store`, `relay`) with what each really does, and hide my IP.
struct HelpSection: View {
    let status: NetworkStatus
    @ObservedObject var net: NetworkModel
    @Environment(\.palette) private var p

    var body: some View {
        PageSection(tr(.networkHelpTitle)) {
            VStack(alignment: .leading, spacing: 0) {
                if let help = status.help {
                    flag("bridge", tr(.networkHelpBridge), help.bridge, tr(.networkHelpBridgePlain),
                         technical: help.effects?.bridge)
                    Rule()
                    // Store and Relay change nothing in this version of raven-node: their switches
                    // show only while one is on (so it can be turned off), E1.
                    if help.store {
                        flag("store", tr(.networkHelpStore), help.store, help.effects?.store)
                        Rule()
                    }
                    if help.relay {
                        flag("relay", tr(.networkHelpRelay), help.relay, help.effects?.relay)
                        Rule()
                    }
                    if help.automatic == true {
                        Text(tr(.networkHelpAutomatic)).font(RFont.small).foregroundColor(p.textSecondary).padding(.bottom, 6)
                        Rule()
                    }
                }
                flag("hide_ip", tr(.networkHideIp), status.hideIp == true, tr(.networkHideIpBody))
            }
        }
    }

    private func flag(_ setting: String, _ title: String, _ on: Bool, _ effect: String?,
                      technical: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(get: { on }, set: { v in Task { await net.toggle(setting, on: v) } })) {
                Text(title).font(RFont.bodyBold)
            }
            .toggleStyle(RSwitchStyle())
            .disabled(net.busy.contains(setting))
            if let effect, !effect.isEmpty {
                Text(effect).font(RFont.smallish).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if let technical { TechnicalDetails(lines: [technical]) }
            if let rowError = net.rowError, rowError.setting == setting { ErrorNote(rowError.error) }
        }
        .padding(.vertical, 8)
    }
}

/// The build and version lines.
struct AboutLines: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((model.network.status?.build ?? model.appInfo?.build) == "release" ? tr(.netBuildRelease) : tr(.netBuildDev))
            if let version = model.appInfo?.version {
                Text(tr(.appName) + " · " + tr(.netVersion, ["version": version])).foregroundColor(p.textSecondary)
            }
        }
        .font(RFont.small)
    }
}
