import SwiftUI

/// Steps of Add a friend: share yours, paste theirs, check words.
@MainActor
public final class AddFriendState: ObservableObject {
    @Published public var step = 1
    @Published public var includeAddress = false
    @Published public var card: ShareCard?
    @Published public var pasteText = ""
    @Published public var summary: CardSummary?
    @Published public var pasteError: RavenError?
    @Published public var name = ""
    @Published public var addError: RavenError?
    @Published public var added: Contact?
    @Published public var copied = false
    @Published public var busy = false
    public var check: CheckWordsState?

    public init(step: Int = 1, includeAddress: Bool = false, card: ShareCard? = nil, summary: CardSummary? = nil,
                name: String = "", added: Contact? = nil, check: CheckWordsState? = nil) {
        self.step = step
        self.includeAddress = includeAddress
        self.card = card
        self.summary = summary
        self.name = name
        self.added = added
        self.check = check
    }

    func loadCard(_ model: AppModel) async {
        do { card = try await model.makeCard(includeAddress: includeAddress) } catch { card = nil }
    }

    /// Parses whatever was pasted. On success the raw text leaves the screen and only a summary
    /// remains: the card holds the friend's code, which must not be shown.
    func pasted(_ model: AppModel) async {
        let text = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { pasteError = nil; return }
        do {
            summary = try await model.parseCard(text)
            pasteError = nil
        } catch {
            summary = nil
            pasteError = RavenError.from(error)
        }
    }

    func clearPaste() {
        summary = nil
        pasteText = ""
        pasteError = nil
        addError = nil
    }

    /// Saves the friend (not verified). Returns false and shows the reason on failure.
    func add(_ model: AppModel) async -> Bool {
        guard added == nil else { return true }
        busy = true
        defer { busy = false }
        do {
            let contact = try await model.addContact(text: pasteText, name: Sanitizer.line(name, maxLength: 64))
            added = contact
            check = CheckWordsState(address: contact.address)
            addError = nil
            return true
        } catch {
            addError = RavenError.from(error)
            return false
        }
    }
}

public struct AddFriendSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @StateObject private var state: AddFriendState
    var highlight: Int?

    public init(state: AddFriendState? = nil, highlight: Int? = nil) {
        self._state = StateObject(wrappedValue: state ?? AddFriendState())
        self.highlight = highlight
    }

    public var body: some View {
        SheetFrame(tr(.addTitle), width: 560) {
            VStack(alignment: .leading, spacing: 14) {
                StepStrip(step: state.step, canGoTo: { $0 < 3 && state.added == nil }) { state.step = $0 }
                switch state.step {
                case 1: shareStep
                case 2: pasteStep
                default: checkStep
                }
            }
        } footer: {
            footer
        }
        .task { if state.card == nil { await state.loadCard(model) } }
    }

    // MARK: Step 1

    private var shareStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr(.addShareBody)).fixedSize(horizontal: false, vertical: true)
            Text(state.card?.card ?? " ")
                .font(RFont.mono)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .selectable()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.shared.radius.control).fill(p.surfaceMuted))
                .overlay(RoundedRectangle(cornerRadius: Theme.shared.radius.control).stroke(p.border, lineWidth: 0.5))
            Toggle(isOn: Binding(get: { state.includeAddress }, set: { v in
                state.includeAddress = v
                state.copied = false
                Task { await state.loadCard(model) }
            })) {
                Text(tr(.addShareIncludeAddress, ["addr": shareAddress]))
                    .font(RFont.smallish)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(RSwitchStyle())
            Text(tr(.addSharePublic)).font(RFont.smallish).foregroundColor(p.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shareAddress: String {
        state.card?.addressIncluded ?? "\(model.node?.address ?? "–"):\(model.node?.port ?? "7420")"
    }

    // MARK: Step 2

    private var pasteStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr(.addPasteBody))
            if let summary = state.summary {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark").foregroundColor(p.accent)
                        .accessibilityHidden(true)
                    Text(summary.hasAddress ? tr(.addPasteSummary, ["short": summary.shortAddress])
                                            : tr(.addPasteSummaryNoAddress, ["short": summary.shortAddress]))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(tr(.addPasteChange)) { state.clearPaste() }
                        .buttonStyle(RButtonStyle(.plain))
                        .disabled(state.added != nil)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Theme.shared.radius.control).fill(p.surfaceMuted))
                .overlay(RoundedRectangle(cornerRadius: Theme.shared.radius.control).stroke(p.border, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 6) {
                    Text(tr(.addNameTitle)).font(RFont.bodyBold)
                    RField(tr(.addNameTitle), text: $state.name)
                        .frame(maxWidth: 280)
                        .onChange(of: state.name) { _ in state.addError = nil }
                    Text(tr(.addNameNote)).font(RFont.smallish).foregroundColor(p.textSecondary)
                    if let clash = nameClash {
                        Text(clash).font(RFont.smallish).foregroundColor(p.warning)
                    }
                }
                .padding(.top, 4)
            } else {
                RField(tr(.addStep2), text: $state.pasteText, mono: true)
                    .onChange(of: state.pasteText) { _ in Task { await state.pasted(model) } }
            }
            if let error = state.pasteError { ErrorNote(error) }
            if let error = state.addError, error.code != "NAME_CLASH" { ErrorNote(error) }
        }
    }

    /// Checked here as the user types; the engine checks again on save (NAME_CLASH).
    private var nameClash: String? {
        if let error = state.addError, error.code == "NAME_CLASH" { return error.message }
        let n = Sanitizer.line(state.name, maxLength: 64)
        guard !n.isEmpty, model.contacts.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { return nil }
        return tr(.addNameClash, ["name": n])
    }

    private var canSave: Bool {
        state.summary != nil && !Sanitizer.line(state.name).isEmpty && nameClash == nil && !state.busy
    }

    // MARK: Step 3

    @ViewBuilder private var checkStep: some View {
        if let added = state.added, let check = state.check {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr(.addMustAddBack, ["name": added.name]))
                    .font(RFont.smallish)
                    .foregroundColor(p.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                CheckWordsIntro(state: check, name: added.name)
                    .fixedSize(horizontal: false, vertical: true)
                CheckWordsBody(state: check, name: added.name, highlight: highlight)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        switch state.step {
        case 1:
            Button(tr(.commonCancel)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button {
                if let card = state.card { Clipboard.copy(card.card) }
                state.copied = true
            } label: {
                Label(state.copied ? tr(.addShareCopied) : tr(.addShareCopy), systemImage: state.copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(RButtonStyle(.secondary))
            .disabled(state.card == nil)
            Button(tr(.addStep2)) { state.step = 2 }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        case 2:
            Button(tr(.commonCancel)) { model.sheet = nil }
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(tr(.checkLater)) {
                Task { if await state.add(model) { model.sheet = nil } }
            }
            .buttonStyle(RButtonStyle(.secondary))
            .disabled(!canSave)
            Button(tr(.addStep3)) {
                Task { if await state.add(model) { state.step = 3 } }
            }
            .buttonStyle(RButtonStyle(.primary))
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        default:
            if let check = state.check {
                CheckWordsButtons(state: check) { model.sheet = nil }
            }
        }
    }
}

/// "1 Share yours · 2 Paste theirs · 3 Check words".
struct StepStrip: View {
    let step: Int
    let canGoTo: (Int) -> Bool
    let go: (Int) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 6) {
            item(1, tr(.addStep1))
            separator
            item(2, tr(.addStep2))
            separator
            item(3, tr(.addStep3))
        }
    }

    private var separator: some View {
        Rectangle().fill(p.border).frame(width: 18, height: 0.5).accessibilityHidden(true)
    }

    private func item(_ n: Int, _ title: String) -> some View {
        let current = n == step
        let done = n < step
        return Button { if canGoTo(n) && n != step { go(n) } } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(current ? p.accentFill : (done ? p.accentSoft : Color.clear))
                    Circle().stroke(current || done ? Color.clear : p.borderStrong, lineWidth: 0.5)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(p.accent)
                    } else {
                        Text("\(n)").font(.system(size: 11, weight: .semibold)).foregroundColor(current ? p.onAccent : p.textSecondary)
                    }
                }
                .frame(width: 18, height: 18)
                Text(title)
                    .font(RFont.smallish)
                    .fontWeight(current ? .semibold : .regular)
                    .foregroundColor(current ? p.textPrimary : p.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
