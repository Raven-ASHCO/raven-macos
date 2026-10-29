import SwiftUI

/// Settings (Calm), in the main window: seven sections in a list on the left, whose selection glides
/// to the chosen one; the section's content slides in from the direction of travel. Each change is
/// saved as it is made (`settings.set`, `network.set`); a switch shows the engine's answer, never a
/// guess. Features this build lacks say so instead of pretending to work: Erase follows
/// `privacy.state`, Lock follows `lock.state`, the ways follow `network.status`.
public struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    /// +1 when the new section is below the old one, -1 above (for the slide).
    @ViewState private var direction: CGFloat = 1

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            SettingsNav(select: select)
                .frame(width: Theme.shared.layout.settingsNavWidth)
            VRule()
            RScroll {
                SettingsSectionBody(section: model.settingsSection)
                    .id(model.settingsSection)
                    .transition(motionOff ? .identity : .asymmetric(
                        insertion: .offset(y: 16 * direction).combined(with: .opacity)
                            .animation(Theme.shared.curve("section", Theme.shared.motion.sectionIn)
                                .delay(Theme.shared.motion.sectionOut)),
                        removal: .offset(y: -10 * direction).combined(with: .opacity)
                            .animation(.easeIn(duration: Theme.shared.motion.sectionOut))))
                    .frame(maxWidth: Theme.shared.layout.settingsMaxWidth, alignment: .leading)
                    .padding(.horizontal, 34)
                    .padding(.top, 26)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(p.background)
        .task { await model.refreshPrivacy() }
    }

    private func select(_ section: AppModel.SettingsSection) {
        guard section != model.settingsSection else { return }
        let all = AppModel.SettingsSection.allCases
        let from = all.firstIndex(of: model.settingsSection) ?? 0
        let to = all.firstIndex(of: section) ?? 0
        direction = to >= from ? 1 : -1
        if motionOff { model.settingsSection = section } else {
            withAnimation(Theme.shared.curve("glide", Theme.shared.motion.settingsGlide)) { model.settingsSection = section }
        }
    }

    /// Settings > Privacy's honest lines about what this computer stores encrypted.
    static func storedLines(_ privacy: PrivacyState) -> [String] {
        privacy.encrypted ? [tr(.settingsStoredEncrypted), tr(.settingsStoredPlain)] : [tr(.settingsStoredNotEncrypted)]
    }

    /// A section's title, its icon (SF Symbol) and the colour of the icon's square.
    static func info(_ s: AppModel.SettingsSection) -> (title: String, icon: String, color: String) {
        switch s {
        case .general: return (tr(.settingsGeneral), "gearshape", "sectionGeneral")
        case .appearance: return (tr(.settingsAppearance), "circle.lefthalf.filled", "sectionAppearance")
        case .privacy: return (tr(.settingsPrivacy), "shield", "sectionPrivacy")
        case .lock: return (tr(.lockSection), "lock", "sectionLock")
        case .network: return (tr(.settingsNetwork), "point.3.connected.trianglepath.dotted", "sectionNetwork")
        case .updates: return (tr(.updatesTitle), "arrow.down.circle", "sectionUpdates")
        case .about: return (tr(.netAbout), "info.circle", "sectionAbout")
        }
    }
}

/// The section list: "Settings", then one button per section with its coloured square; the
/// selection (a card) glides between them.
struct SettingsNav: View {
    let select: (AppModel.SettingsSection) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Namespace private var glider

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tr(.settingsTitle)).font(.system(size: 22, weight: .semibold)).tracking(-0.2)
                .padding(.horizontal, 10).padding(.bottom, 14)
                .accessibilityAddTraits(.isHeader)
            ForEach(AppModel.SettingsSection.allCases, id: \.self) { section in
                let info = SettingsView.info(section)
                let on = model.settingsSection == section
                Button { select(section) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: info.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.named(info.color)))
                            .accessibilityHidden(true)
                        Text(info.title).font(.system(size: 13.5, weight: on ? .semibold : .regular))
                            .foregroundColor(on ? p.textPrimary : p.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: Theme.shared.radius.row, style: .continuous)
                                .fill(p.surface)
                                .ravenShadow(p.cardShadow)
                                .overlay(RoundedRectangle(cornerRadius: Theme.shared.radius.row, style: .continuous)
                                    .strokeBorder(p.border, lineWidth: 1))
                                .matchedGeometryEffect(id: "glider", in: glider)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 22)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// One section's content.
struct SettingsSectionBody: View {
    let section: AppModel.SettingsSection
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(SettingsView.info(section).title).font(RFont.pageTitle).tracking(Theme.shared.type.pageTitle.tracking)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            switch section {
            case .general: GeneralSection()
            case .appearance: AppearanceSection()
            case .privacy: PrivacySection()
            case .lock: LockSettingsSection()
            case .network: NetworkSettingsSection()
            case .updates: UpdatesSettingsSection()
            case .about: AboutSection()
            }
        }
    }
}

/// The lead paragraph under a section's title.
struct Lead: View {
    let text: String
    @Environment(\.palette) private var p
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundColor(p.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.bottom, 20)
    }
}

extension View {
    /// A binding that shows the new value at once and sends `settings.set` with the wire name.
    @MainActor
    func settingBinding<T>(_ model: AppModel, _ keyPath: WritableKeyPath<RavenSettings, T>, _ wire: String,
                           _ encode: @escaping (T) -> JSONValue) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in
                model.settings[keyPath: keyPath] = value
                Task { await model.updateSettings([wire: encode(value)]) }
            }
        )
    }
}

// MARK: General

struct GeneralSection: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var nameDraft: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Lead(tr(.settingsGeneralLead)).padding(.bottom, -22)
            CalmGroup {
                CalmItem(tr(.settingsName), tr(.settingsNameBody)) {
                    RField(tr(.setupNamePlaceholder), text: Binding(
                        get: { nameDraft ?? model.settings.displayName ?? "" },
                        set: { nameDraft = $0 }
                    )) { saveName() }
                    .frame(width: 220)
                    .onDisappear { saveName() }
                    .accessibilityLabel(tr(.settingsName))
                }
                CalmItem(tr(.settingsReceive), tr(.setupReceiveBody)) {
                    RSwitch(tr(.settingsReceive), isOn: settingBinding(model, \.receive, "receive") { .bool($0) })
                }
            }
            CalmGroup {
                VStack(alignment: .leading, spacing: 8) {
                    CalmItem(tr(.settingsWhenQuit), tr(.quitRunning)).padding(.bottom, -14)
                    RRadioGroup(tr(.settingsWhenQuit),
                                options: Array(zip(RavenSettings.whenQuitValues, Strings.shared.options(.settingsWhenQuitOptions)))
                                    .map { (value: $0.0, label: $0.1) },
                                selection: settingBinding(model, \.whenQuit, "when_quit") { .string($0) })
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private func saveName() {
        guard let draft = nameDraft else { return }
        let clean = Sanitizer.line(draft, maxLength: 64)
        nameDraft = nil
        guard clean != (model.settings.displayName ?? "") else { return }
        Task { await model.updateSettings(["display_name": .opt(clean.isEmpty ? nil : clean)]) }
    }
}

// MARK: Appearance

struct AppearanceSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Lead(tr(.settingsAppearanceLead)).padding(.bottom, -22)
            CalmGroup {
                CalmItem(tr(.settingsTheme), tr(.settingsThemeBody)) {
                    RSegmented(tr(.settingsTheme),
                               options: Array(zip(AppModel.ThemeChoice.allCases, Strings.shared.options(.settingsThemeOptions)))
                                   .map { (value: $0.0, label: $0.1) },
                               selection: $model.themeChoice)
                }
                CalmItem(tr(.settingsReducedMotion), tr(.settingsReducedMotionBody)) {
                    RSwitch(tr(.settingsReducedMotion), isOn: settingBinding(model, \.reducedMotion, "reduced_motion") { .bool($0) })
                }
                CalmItem(tr(.settingsDetails), tr(.settingsDetailsBody)) {
                    RSwitch(tr(.settingsDetails), isOn: $model.showTechnical)
                }
            }
            CalmGroup(tr(.settingsPreview)) {
                SendPreview()
            }
        }
    }
}

/// Settings > Appearance's preview: one of your messages as it looks, and "Play a send" (the user's
/// own action) plays its motion: lift, sent, delivered with the check popping and the chip sliding in.
/// It sends nothing.
struct SendPreview: View {
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @ViewState private var step = 2
    @ViewState private var lift: CGFloat = 0
    @ViewState private var pop = 0

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr(.settingsPreviewText))
                    .font(RFont.bubble)
                    .foregroundColor(p.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(BubbleShape(outgoing: true)
                        .fill(LinearGradient(colors: [p.accentFillTop, p.accentFill], startPoint: .top, endPoint: .bottom))
                        .ravenShadow(p.bubbleShadow))
                    .offset(y: lift * 26)
                    .scaleEffect(1 - lift * 0.06)
                    .opacity(1 - Double(lift) * 0.8)
                HStack(spacing: 8) {
                    switch step {
                    case 0:
                        StatusIcon(kind: .sending)
                        Text(tr(.tickSending)).foregroundColor(p.textSecondary)
                    case 1:
                        StatusIcon(kind: .sent)
                        Text(tr(.tickSent)).foregroundColor(p.textSecondary)
                    default:
                        HStack(spacing: 5) {
                            StatusIcon(kind: .delivered, pop: pop)
                            Text(tr(.tickDelivered))
                        }
                        .foregroundColor(p.success)
                        SlidingChip(pop: pop) { PathPill(label: tr(.chipLan), family: .lan) }
                    }
                }
                .font(.system(size: 11.5))
                .frame(minHeight: 20)
                .padding(.top, 5)
                .padding(.horizontal, 4)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(tr(.settingsPreviewPlay)) { play() }.buttonStyle(RButtonStyle(.secondary))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func play() {
        step = 0
        if !motionOff {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { lift = 1 }
            DispatchQueue.main.async {
                withAnimation(Theme.shared.curve("lift", Theme.shared.motion.bubbleLift)) { lift = 0 }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { step = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            step = 2
            pop &+= 1
        }
    }
}

// MARK: Privacy

struct PrivacySection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @ViewState private var confirmErase = false

    var body: some View {
        let available = model.privacy.available
        VStack(alignment: .leading, spacing: 22) {
            Lead(tr(.settingsPrivacyLead)).padding(.bottom, -22)
            CalmGroup(tr(.settingsStoredTitle)) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(SettingsView.storedLines(model.privacy).enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: model.privacy.encrypted && i == 0 ? "lock" : "lock.open")
                                .font(.system(size: 14))
                                .foregroundColor(model.privacy.encrypted && i == 0 ? p.success : p.textTertiary)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            Text(line).font(.system(size: 13)).foregroundColor(p.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if available && !model.privacy.encrypted {
                        Button(tr(.settingsEncrypt)) { Task { await model.encrypt() } }
                            .buttonStyle(RButtonStyle(.secondary))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
            }
            CalmGroup {
                CalmItem(tr(.settingsKeepChats), tr(.settingsKeepChatsBody)) {
                    RSegmented(tr(.settingsKeepChats),
                               options: Array(zip(RavenSettings.keepChatsValues, Strings.shared.options(.settingsKeepChatsOptions)))
                                   .map { (value: $0.0, label: $0.1) },
                               selection: settingBinding(model, \.keepChatsDays, "keep_chats_days") { $0.map { .int($0) } ?? .null })
                }
                CalmItem(tr(.settingsForget), tr(.settingsForgetBody), disabled: true) {
                    // Always on in this version: setting it off is NOT_AVAILABLE_YET (API.md).
                    RSwitch(tr(.settingsForget), isOn: .constant(model.settings.forgetAddresses))
                        .disabled(true)
                }
            }
            CalmGroup {
                CalmItem(tr(.settingsErase), available ? tr(.settingsEraseBody) : tr(.netPreview)) {
                    Button(tr(.eraseConfirm) + "…") { confirmErase = true }
                        .buttonStyle(RButtonStyle(.danger))
                        .disabled(!available)
                }
            }
        }
        .sheet(isPresented: $confirmErase) {
            EraseSheet { confirmErase = false }
                .environmentObject(model)
                .ravenTheme(reducedMotion: model.settings.reducedMotion)
        }
    }
}

// MARK: Lock

struct LockSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let lock = model.lockV2
        VStack(alignment: .leading, spacing: 22) {
            Lead(tr(.lockV2Body)).padding(.bottom, -22)
            CalmGroup {
                HStack(spacing: 14) {
                    LockIcon(closed: lock?.locked == true)
                        .foregroundColor(p.success)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.successFill.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lock?.locked == true ? tr(.lockIsLocked) : tr(.lockIsOpen)).font(.system(size: 14, weight: .semibold))
                        Text(lockNote(lock)).font(.system(size: 12.5)).foregroundColor(p.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button(tr(.lockNowEllipsis)) { model.requestLock() }
                        .buttonStyle(RButtonStyle(.primary))
                        .disabled(!model.canLock || model.phase != .ready)
                }
                .padding(16)
            }
            CalmGroup {
                CalmItem(tr(.settingsLockOnSleep), tr(.settingsLockOnSleepBody)) {
                    RSwitch(tr(.settingsLockOnSleep), isOn: settingBinding(model, \.lockOnSleep, "lock_on_sleep") { .bool($0) })
                }
                CalmItem(tr(.lockPassphrase), tr(.settingsPassphraseBody) + " " + tr(.lockPassphraseTerminal)) {
                    if let has = lock?.hasPassphrase {
                        StatChip(text: has ? tr(.settingsPassphraseSet) : tr(.settingsPassphraseNotSet),
                                 tone: has ? .success : .warning)
                    }
                }
            }
            if let error = model.lockError { ErrorNote(error) }
        }
        .task { await model.refreshLock() }
    }

    private func lockNote(_ lock: LockState?) -> String {
        guard let lock, lock.available else { return tr(.lockNotAvailable) }
        guard lock.supported else { return tr(.lockNotSupported) }
        if lock.hasPassphrase == false { return tr(.lockNoPassphrase) }
        return tr(.lockReady)
    }
}

/// A padlock whose shackle closes (Lock's question and the Lock section).
struct LockIcon: View {
    var closed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.8))
                .frame(width: 14, height: 10)
                .offset(y: 4)
            Shackle()
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 8, height: 7)
                .offset(y: closed ? -4 : -7.5)
            Circle().frame(width: 2.4, height: 2.4).offset(y: 4.2)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private struct Shackle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.width / 2))
            p.addArc(center: CGPoint(x: r.midX, y: r.minY + r.width / 2), radius: r.width / 2,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            return p
        }
    }
}

// MARK: Network

struct NetworkSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let net = model.network
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr(.settingsNetworkLead)).font(.system(size: 14)).foregroundColor(p.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr(.networkPageOpen)) { model.open(.network) }.buttonStyle(RButtonStyle(.plain))
            }
            if let error = net.loadError { ErrorNote(error) }
            if let status = net.status {
                CalmGroup(tr(.netWays)) {
                    ForEach(status.carriers) { way in WaySettingRow(way: way, net: net) }
                }
                if let protections = status.protections, !protections.isEmpty {
                    CalmGroup(tr(.networkProtections)) {
                        ForEach(protections) { way in WaySettingRow(way: way, net: net) }
                    }
                }
            } else if net.loadError == nil {
                Spinner()
            }
        }
        .task { await model.network.refresh() }
    }
}

/// One way in Settings > Network: its icon in the path colour, its name, its state in words, and the
/// switch where `network.set` changes it.
struct WaySettingRow: View {
    let way: NetworkWay
    @ObservedObject var net: NetworkModel
    @Environment(\.palette) private var p

    var body: some View {
        let family = PathFamily.of(way: way.id)
        let setting = NetworkModel.setting(forWay: way.id)
        let toggle = NetworkModel.toggle(for: way)
        let name = way.name.map { Sanitizer.line($0, maxLength: 80) } ?? way.id
        let state = Display.wayState(way.state)
        HStack(spacing: 12) {
            PathIcon(family: family, size: 15).foregroundColor(family.color(p)).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Text([state.text, Display.runningNote(state: way.state, running: way.running)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12.5)).foregroundColor(state.tone == .warning ? p.warning : p.textSecondary)
                if let setting, let rowError = net.rowError, rowError.setting == setting { ErrorNote(rowError.error) }
            }
            Spacer(minLength: 8)
            if toggle.shown, let setting {
                RSwitch(name, isOn: Binding(get: { NetworkModel.isOn(way) },
                                           set: { on in Task { await net.toggle(setting, on: on) } }))
                    .disabled(!toggle.enabled || net.busy.contains(setting))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}

// MARK: Updates

struct UpdatesSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let u = model.network.updates
        VStack(alignment: .leading, spacing: 22) {
            Lead(tr(.updatesIntro)).padding(.bottom, -22)
            CalmGroup {
                CalmItem(tr(.settingsUpdatesVersion), versionLine()) {
                    if let summary = u?.summary, !summary.isEmpty { StatChip(text: summary, tone: .success) }
                }
                CalmItem(tr(.updatesFromFriends), u?.available == true ? tr(.updatesAvailable) : tr(.updatesNotAvailable)) {
                    if let u {
                        StatChip(text: u.fromFriends == true ? (u.lab == true ? tr(.netLab) : tr(.netOn)) : tr(.netPreview),
                                 tone: u.fromFriends == true ? .success : .warning)
                    }
                }
                CalmItem(tr(.updatesTitle), tr(.updatesInstall)) {
                    StatChip(text: tr(.settingsUpdatesTerminal), tone: .secondary)
                }
            }
            if let error = model.network.updatesError { ErrorNote(error) }
            if let text = u?.installText, !text.isEmpty { TechnicalDetails(lines: [text]) }
        }
        .task { await model.network.loadUpdates() }
    }

    private func versionLine() -> String {
        let build = (model.network.status?.build ?? model.appInfo?.build) == "release" ? tr(.netBuildRelease) : tr(.netBuildDev)
        guard let version = model.appInfo?.version else { return build }
        return tr(.netVersion, ["version": version]) + " · " + build
    }
}

// MARK: About

struct AboutSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let you = Display.you(model.identity, name: model.settings.displayName)
        VStack(alignment: .leading, spacing: 22) {
            CalmGroup {
                VStack(spacing: 4) {
                    RavenMark(size: 74, color: p.textPrimary).padding(.bottom, 8)
                    Text(tr(.appName)).font(.system(size: 20, weight: .bold))
                    Text(tr(.appTagline)).font(.system(size: 13)).foregroundColor(p.textSecondary)
                    if let version = model.appInfo?.version {
                        Text(tr(.netVersion, ["version": version])).font(.system(size: 13)).foregroundColor(p.textSecondary)
                    }
                    Text(AppIdentity.bundleID).font(.system(size: 12)).foregroundColor(p.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
            }
            .padding(.top, 14)
            CalmGroup {
                CalmItem(tr(.settingsAboutFingerprint), you.fingerprint) {
                    Button(tr(.homeNavWords)) { model.presentYou() }.buttonStyle(RButtonStyle(.secondary))
                }
            }
        }
    }
}

/// Erase Raven from this computer: says what is removed, and enables Erase only after the user
/// typed "erase". Reached from Settings > Privacy when `privacy.state` says `available`.
public struct EraseSheet: View {
    let close: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @ViewState private var typed: String
    @ViewState private var busy = false
    @ViewState private var error: RavenError?

    public init(typed: String = "", close: @escaping () -> Void) {
        self.close = close
        self._typed = ViewState(wrappedValue: typed)
    }

    /// The confirmation word, compared without case and surrounding spaces.
    static func confirms(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "erase"
    }

    public var body: some View {
        SheetFrame(tr(.eraseTitle), width: 460) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr(.eraseBody)).fixedSize(horizontal: false, vertical: true)
                Text(tr(.eraseTypeToConfirm)).font(RFont.smallish).foregroundColor(p.textSecondary)
                RField(tr(.eraseTypeToConfirm), text: $typed) { Task { await erase() } }
                    .frame(maxWidth: 200)
                if let error { ErrorNote(error) }
            }
        } footer: {
            Button(tr(.commonCancel), action: close)
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(tr(.eraseConfirm)) { Task { await erase() } }
                .buttonStyle(RButtonStyle(.danger))
                .disabled(!EraseSheet.confirms(typed) || busy)
        }
    }

    private func erase() async {
        guard EraseSheet.confirms(typed), !busy else { return }
        busy = true
        defer { busy = false }
        error = await model.erase()
        if error == nil { close() }
    }
}
