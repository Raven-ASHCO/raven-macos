import SwiftUI

/// Message details: status, why, what you can do; Try now / Stop trying / Send again; Details.
public struct MessageDetailsSheet: View {
    let id: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p
    @ViewState private var details: MessageDetails?
    @ViewState private var error: RavenError?
    @ViewState private var showDetail = false
    @ViewState private var showTechnical = false

    public init(id: String, preset: MessageDetails? = nil, showDetail: Bool = false) {
        self.id = id
        self._details = ViewState(wrappedValue: preset)
        self._showDetail = ViewState(wrappedValue: showDetail)
    }

    public var body: some View {
        let message = details?.message ?? model.message(id)
        let name = message.map { model.contact($0.address)?.name ?? Fallback.short($0.address) } ?? ""
        let when = message.map { TimeText.ago(since: clock.now.timeIntervalSince(Date(ms: $0.atMs))) } ?? ""
        SheetFrame(tr(.messageTitle, ["name": name, "when": when]), width: 480) {
            VStack(alignment: .leading, spacing: 10) {
                if let message {
                    Text(message.text)
                        .foregroundColor(p.textSecondary)
                        .lineLimit(3)
                        .padding(.leading, 10)
                        .overlay(Rectangle().fill(p.borderStrong).frame(width: 2), alignment: .leading)
                }
                if let d = details {
                    Text(d.statusText).font(RFont.bodyBold).fixedSize(horizontal: false, vertical: true)
                    if !d.whyText.isEmpty { Text(d.whyText).fixedSize(horizontal: false, vertical: true) }
                    if !d.actionText.isEmpty {
                        Text(d.actionText).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if !d.detail.isEmpty {
                        Button(tr(.messageDetails)) { showDetail.toggle() }.buttonStyle(RButtonStyle(.plain))
                    }
                    if showDetail {
                        detailBox(d.detail)
                        // The developer fields (ids, raven-node's own words), one more step away.
                        if let technical = d.technical, !technical.isEmpty {
                            Button(tr(.messageTechnicalDetails)) { showTechnical.toggle() }
                                .buttonStyle(RButtonStyle(.plain))
                                .font(RFont.small)
                            if showTechnical { detailBox(technical) }
                        }
                    }
                } else if let error {
                    ErrorNote(error)
                } else {
                    Spinner()
                }
            }
        } footer: {
            actionButtons(message)
            Button(tr(.commonClose)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
        }
        .task { await load() }
    }

    @ViewBuilder private func actionButtons(_ message: Message?) -> some View {
        switch message?.state {
        case .waiting?, .sent?:
            Button(tr(.messageStopTrying)) { Task { await model.stopTrying(id); await load() } }
                .buttonStyle(RButtonStyle(.secondary))
            Button(tr(.messageTryNow)) { Task { await model.retry(id); await load() } }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        case .timeRanOut?, .failed?, .notSentMeetFirst?:
            // The same message again (messages.retry), never a second copy beside the failed one.
            Button(tr(.messageSendAgain)) {
                Task {
                    await model.retry(id)
                    model.sheet = nil
                }
            }
            .buttonStyle(RButtonStyle(.primary))
        default:
            EmptyView()
        }
    }

    private func detailBox(_ text: String) -> some View {
        Text(text)
            .font(RFont.mono)
            .foregroundColor(p.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .selectable()
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.shared.radius.control).fill(p.surfaceMuted))
    }

    private func load() async {
        switch await model.details(id) {
        case .success(let d): details = d
        case .failure(let e): error = e
        }
    }
}

/// You: your name, fingerprint, security words and card (to send to a friend).
public struct YouSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @ViewState private var copied = false

    public init() {}

    public var body: some View {
        let you = Display.you(model.identity, name: model.settings.displayName)
        SheetFrame(you.title, width: 620) {
            VStack(alignment: .leading, spacing: 10) {
                if let fingerprint = you.fingerprint {
                    Text(fingerprint).font(RFont.bodyBold).selectable()
                }
                if let words = model.identity?.words, !words.isEmpty {
                    Text(tr(.youWords)).font(RFont.smallish).foregroundColor(p.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ReadAloudWords(words: words)
                }
                if let card = model.identity?.card, !card.isEmpty {
                    Text(tr(.youCard)).font(RFont.smallish).foregroundColor(p.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card).font(RFont.mono).lineLimit(4).selectable()
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.shared.radius.control).fill(p.surfaceMuted))
                }
            }
        } footer: {
            if let card = model.identity?.card, !card.isEmpty {
                Button {
                    Clipboard.copy(card)
                    copied = true
                } label: {
                    Label(copied ? tr(.addShareCopied) : tr(.addShareCopy), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(RButtonStyle(.secondary))
            }
            Button(tr(.commonClose)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// "This computer" (listening chip, background program), "Ways to reach friends" (Preview labels),
/// "About". Shared by the Network panel and Settings > Network.
public struct NetworkContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p

    public init() {}

    public var body: some View {
        let node = model.node
        let chip = Display.listening(node)
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(tr(.netThisComputer))
            HStack(spacing: 6) {
                if chip.busy { Spinner(size: 11) } else {
                    Circle().fill(p.tone(chip.tone)).frame(width: 7, height: 7)
                }
                Text(chip.text).font(RFont.smallish).foregroundColor(chip.tone == .success ? p.textPrimary : p.tone(chip.tone))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(p.borderStrong, lineWidth: 0.5))
            Text(Display.process(node)).font(RFont.smallish)
            if let addr = node?.address {
                Text(tr(.netAddress, ["addr": addr])).font(RFont.smallish).selectable()
            }

            SectionLabel(tr(.netWays)).padding(.top, 8)
            // The same states as the Network page (`network.status`, read from the running raven-node):
            // one source for every screen (E1: "Preview" here while the node ran them).
            VStack(spacing: 6) {
                ForEach(NetworkContent.ways(model.network.status), id: \.id) { way in
                    wayRow(way)
                }
            }
            Text(tr(.settingsNetworkNote)).font(RFont.small).foregroundColor(p.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SectionLabel(tr(.netAbout)).padding(.top, 8)
            Text((node?.build ?? model.appInfo?.build) == "release" ? tr(.netBuildRelease) : tr(.netBuildDev))
                .font(RFont.smallish)
            if let version = model.appInfo?.version {
                Text(tr(.appName) + " · " + tr(.netVersion, ["version": version]))
                    .font(RFont.smallish)
                    .foregroundColor(p.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.network.refresh() }
    }

    /// The ways this summary shows, in the Network page's order and words.
    static let shownWays = ["lan", "internet", "p2p", "custody", "nearby"]

    static func ways(_ status: NetworkStatus?) -> [NetworkWay] {
        shownWays.compactMap { status?.way($0) }
    }

    private func wayRow(_ way: NetworkWay) -> some View {
        let state = Display.wayState(way.state)
        return HStack {
            Text(way.name.map { Sanitizer.line($0, maxLength: 80) } ?? way.id).font(RFont.smallish)
            Spacer(minLength: 8)
            Text(state.text).font(RFont.smallish).foregroundColor(p.tone(state.tone))
        }
        .accessibilityElement(children: .combine)
    }
}

public struct NetworkSheet: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    public var body: some View {
        SheetFrame(tr(.netTitle), width: 440) {
            NetworkContent()
        } footer: {
            Button(tr(.networkPageOpen)) { model.open(.network) }
                .buttonStyle(RButtonStyle(.secondary))
            Button(tr(.commonClose)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Quit: explains what keeps running. Shown when Settings > When I quit is "Ask me".
public struct QuitDialog: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    public var body: some View {
        SheetFrame(tr(.quitTitle), width: 460) {
            Text(tr(.quitRunning)).fixedSize(horizontal: false, vertical: true)
        } footer: {
            Button(tr(.quitStay)) { Task { await model.answerQuit(.stay) } }
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(tr(.quitQuitAndStop)) { Task { await model.answerQuit(.quitAndStop) } }
                .buttonStyle(RButtonStyle(.secondary))
            Button(tr(.quitQuit)) { Task { await model.answerQuit(.quit) } }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Lock now's question (Calm): the lock tile, what Lock does and doesn't protect, then Lock: the
/// shackle closes (`lockShackle`) and Raven locks (E1).
public struct ConfirmLockSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @ViewState private var closing = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockIcon(closed: closing)
                .foregroundColor(p.accent)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.accentSoft))
                .animation(motionOff ? nil : Theme.shared.curve("shackle", Theme.shared.motion.lockShackle), value: closing)
                .padding(.bottom, 12)
            Text(tr(.lockConfirmTitle)).font(.system(size: 17, weight: .semibold)).padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ConfirmLockSheet.lines(model.lockV2), id: \.self) { line in
                    Text(line).font(.system(size: 13)).foregroundColor(p.textSecondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(tr(.commonCancel)) { model.sheet = nil }
                    .buttonStyle(RButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(tr(.lockConfirmLock)) { lock() }
                    .buttonStyle(RButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(closing)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(width: 460, alignment: .leading)
        .background(p.surface)
    }

    private func lock() {
        closing = true
        let wait = motionOff ? 0 : Theme.shared.motion.lockShackle + 0.07
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            model.sheet = nil
            Task { await model.lock() }
        }
    }

    /// What it does, what it doesn't protect, and who can unlock it.
    static func lines(_ lock: LockState?) -> [String] {
        var lines = [tr(.lockConfirmDoes), tr(.lockConfirmDoesNot)]
        if lock?.hasPassphrase == true {
            lines.append(tr(.lockV2PassphraseNote))
        } else if lock?.hasPassphrase == false {
            lines.append(tr(.lockNoPassphrase))
        }
        return lines
    }
}

/// Rename a friend: the name only this computer shows (`contacts.rename`).
public struct RenameSheet: View {
    let address: String
    @EnvironmentObject private var model: AppModel
    @ViewState private var name: String?
    @ViewState private var error: RavenError?
    @ViewState private var busy = false

    public init(address: String) { self.address = address }

    public var body: some View {
        let current = model.contact(address)?.name ?? Fallback.short(address)
        SheetFrame(tr(.contactRenameTitle, ["name": current]), width: 420) {
            VStack(alignment: .leading, spacing: 8) {
                RField(tr(.setupNamePlaceholder), text: Binding(get: { name ?? current }, set: { name = $0 })) { save() }
                    .accessibilityLabel(tr(.contactRenameTitle, ["name": current]))
                Text(tr(.contactRenameNote, ["name": current])).font(RFont.small)
                    .fixedSize(horizontal: false, vertical: true)
                if let error { ErrorNote(error) }
            }
        } footer: {
            Button(tr(.commonCancel)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(tr(.contactRenameSave)) { save() }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(busy || RenameSheet.clean(name ?? current).isEmpty)
        }
    }

    static func clean(_ text: String) -> String { Sanitizer.line(text, maxLength: 64) }

    private func save() {
        let clean = RenameSheet.clean(name ?? "")
        guard !busy, !clean.isEmpty else { return }
        guard clean != model.contact(address)?.name else { model.sheet = nil; return }
        busy = true
        Task {
            error = await model.renameContact(address, to: clean)
            busy = false
            if error == nil { model.sheet = nil }
        }
    }
}
