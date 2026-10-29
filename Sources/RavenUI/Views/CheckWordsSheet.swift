import SwiftUI

/// What the user has typed while a friend reads their words (or, for a friend with an older Raven,
/// their old code) aloud.
///
/// Typed words become neutral chips: there is never a per-word right/wrong mark. The field only says
/// whether a token is one of Raven's words (completion after 3 letters, from `verify.word_hint`).
/// Only `verify.check_words` decides, once all 10 are in: match, typo (the check word caught a
/// misheard or swapped word) or mismatch. The old code goes into one plain field, with no marks at
/// all, and only `verify.check_old_code` decides: match or mismatch. After three mismatches (words
/// and old code together) Check is withdrawn. The friend's words and code are never shown or requested.
@MainActor
public final class CheckWordsState: ObservableObject {
    public enum Mode: Equatable { case words, oldCode }
    /// Why the current token is not (yet) a word. Depends only on what was typed.
    public enum InputNote: Equatable { case notAWord, englishLetters, tooShort(Int) }

    /// Mismatches after which Check is no longer offered (security-words design, blind entry rule 4).
    public static let maxMismatches = 3

    public let address: String
    @Published public var mode: Mode
    @Published public var typed: [String] = []
    @Published public var field = ""
    @Published public var hint: String?
    @Published public var note: InputNote?
    @Published public var oldCode = ""
    @Published public var checking = false
    @Published public var result: VerifyResult?
    @Published public var mismatches = 0
    @Published public var error: RavenError?
    private var hintToken = ""

    public init(address: String, mode: Mode = .words, typed: [String] = [], field: String = "", hint: String? = nil,
                oldCode: String = "", result: VerifyResult? = nil, mismatches: Int = 0) {
        self.address = address
        self.mode = mode
        self.typed = typed
        self.field = field
        self.hint = hint
        self.oldCode = oldCode
        self.result = result
        self.mismatches = mismatches
    }

    public var complete: Bool { typed.count == 10 }
    public var matched: Bool { result == .match }
    /// Three mismatches: stop here and check another way.
    public var stopped: Bool { !matched && mismatches >= CheckWordsState.maxMismatches }

    public var canCheck: Bool {
        guard !checking, !matched, !stopped else { return false }
        switch mode {
        case .words: return complete
        case .oldCode: return !oldCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Switches between the 10 words and the old code; the previous result goes away.
    public func switchMode(_ mode: Mode) {
        guard !matched, self.mode != mode else { return }
        self.mode = mode
        result = nil
        error = nil
    }

    /// Called on every edit. Finished tokens (followed by a separator, or pasted several at once)
    /// become chips; the unfinished rest stays in the field and gets a completion hint.
    func fieldChanged(_ model: AppModel) async {
        if result != nil && !matched { result = nil }
        error = nil
        let tokens = WordInput.tokens(field)
        let finished = WordInput.endsWithSeparator(field) ? tokens : Array(tokens.dropLast())
        let rest = WordInput.endsWithSeparator(field) ? "" : (tokens.last ?? "")
        if !finished.isEmpty {
            field = rest
            for token in finished {
                guard await accept(token, model) else {
                    field = ([token] + (rest.isEmpty ? [] : [rest])).joined(separator: " ")
                    return
                }
            }
        }
        await updateHint(rest, model)
    }

    /// Return in the field: accept the current token (completing it if possible).
    func submit(_ model: AppModel) async {
        let token = WordInput.tokens(field).first ?? ""
        guard !token.isEmpty else {
            if canCheck { await check(model) }
            return
        }
        // On failure the field keeps the token and the note from `accept` says why.
        if await accept(token, model) {
            field = ""
            await updateHint(field, model)
        }
    }

    /// Edits of the old-code field clear a mismatch shown for the previous text.
    func oldCodeChanged() {
        if result != nil && !matched { result = nil }
        error = nil
    }

    @discardableResult
    private func accept(_ token: String, _ model: AppModel) async -> Bool {
        guard typed.count < 10 else { return false }
        guard let folded = WordInput.foldLatin(token) else {
            note = .englishLetters
            return false
        }
        if let word = await model.wordHint(token) {
            typed.append(word)
            note = nil
            return true
        }
        note = folded.count < 3 ? .tooShort(typed.count + 1) : .notAWord
        return false
    }

    private func updateHint(_ token: String, _ model: AppModel) async {
        hintToken = token
        guard let folded = WordInput.foldLatin(token) else {
            hint = nil
            note = .englishLetters
            return
        }
        guard folded.count >= 3 else {
            hint = nil
            note = nil
            return
        }
        let word = await model.wordHint(folded)
        guard hintToken == token else { return }   // a newer edit arrived meanwhile
        hint = word
        note = word == nil ? .notAWord : nil
    }

    public func remove(at index: Int) {
        guard typed.indices.contains(index), !matched, !stopped else { return }
        typed.remove(at: index)
        result = nil
    }

    /// "Type again" after a typo or a mismatch: clears the typed words.
    public func typeAgain() {
        guard !matched else { return }
        typed = []
        field = ""
        hint = nil
        note = nil
        result = nil
    }

    func check(_ model: AppModel) async {
        guard canCheck else { return }
        checking = true
        error = nil
        defer { checking = false }
        do {
            switch mode {
            case .words: result = try await model.checkWords(address: address, words: typed)
            case .oldCode: result = try await model.checkOldCode(address: address, code: oldCode)
            }
            if result == .mismatch { mismatches += 1 }
        } catch {
            self.error = RavenError.from(error)
        }
    }
}

/// The body of the check: your words (read aloud), their words (typed), the field and the result;
/// or, in old-code mode, your old code and one field for theirs.
struct CheckWordsBody: View {
    @ObservedObject var state: CheckWordsState
    let name: String
    var highlight: Int?
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state.mode {
            case .words: wordsMode
            case .oldCode: oldCodeMode
            }
            resultRow
                .frame(minHeight: 40, alignment: .topLeading)
        }
        .onAppear { focused = true }
    }

    // MARK: Words

    @ViewBuilder private var wordsMode: some View {
        SectionLabel(tr(.checkYours, ["name": name]))
        ReadAloudWords(words: model.identity?.words ?? [], fixedHighlight: highlight)
        HStack {
            SectionLabel(tr(.checkTheirs, ["name": name]))
            Spacer()
            Text(tr(.checkProgress, ["n": String(state.typed.count)]))
                .font(RFont.smallish)
                .foregroundColor(p.textSecondary)
        }
        .padding(.top, 6)
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(state.typed.enumerated()), id: \.offset) { i, word in
                Button { state.remove(at: i) } label: { Chip(word, removable: !state.matched && !state.stopped) }
                    .buttonStyle(.plain)
                    .disabled(state.matched || state.stopped)
            }
        }
        .frame(minHeight: 26, alignment: .topLeading)
        if !state.matched && !state.complete && !state.stopped {
            RField("", text: $state.field, focused: $focused) { Task { await state.submit(model) } }
                .onChange(of: state.field) { _ in Task { await state.fieldChanged(model) } }
            hintRow
        }
        if !state.matched && !state.stopped {
            Button(tr(.checkOldCodeLink)) { state.switchMode(.oldCode) }
                .buttonStyle(RButtonStyle(.plain))
                .font(RFont.smallish)
        }
    }

    @ViewBuilder private var hintRow: some View {
        let token = WordInput.tokens(state.field).last ?? ""
        if let hint = state.hint, let folded = WordInput.foldLatin(token), hint.hasPrefix(folded), !folded.isEmpty {
            (Text(folded).foregroundColor(p.textPrimary)
                + Text(String(hint.dropFirst(folded.count))).foregroundColor(p.textSecondary)
                + Text("  ·  " + tr(.checkRavenWord)).foregroundColor(p.textSecondary))
                .font(RFont.smallish)
        } else if let note = state.note {
            Text(noteText(note)).font(RFont.smallish).foregroundColor(p.warning)
        } else {
            Text(" ").font(RFont.smallish)
        }
    }

    private func noteText(_ note: CheckWordsState.InputNote) -> String {
        switch note {
        case .notAWord: return tr(.checkNotARavenWord, ["name": name])
        case .englishLetters: return tr(.checkEnglishLetters)
        case .tooShort(let n): return tr(.checkTooShort, ["n": String(n)])
        }
    }

    // MARK: Old code

    @ViewBuilder private var oldCodeMode: some View {
        SectionLabel(tr(.checkOldCodeYours, ["name": name]))
        Text(WordInput.oldCodeGroups(model.identity?.oldCode ?? ""))
            .font(RFont.mono)
            .selectable()
        SectionLabel(tr(.checkOldCodeTheirs, ["name": name]))
            .padding(.top, 6)
        if state.matched {
            Text(state.oldCode).font(RFont.mono).foregroundColor(p.textSecondary)
        } else {
            RField(tr(.checkOldCodeField), text: $state.oldCode, mono: true, focused: $focused) {
                Task { await state.check(model) }
            }
            .frame(maxWidth: 280)
            .onChange(of: state.oldCode) { _ in state.oldCodeChanged() }
            .disabled(state.stopped)
            Button(tr(.checkOldCodeUseWords)) { state.switchMode(.words) }
                .buttonStyle(RButtonStyle(.plain))
                .font(RFont.smallish)
        }
    }

    // MARK: Result

    @ViewBuilder private var resultRow: some View {
        if state.checking {
            HStack(spacing: 6) {
                Spinner(size: 12)
                Text(tr(.checkChecking)).foregroundColor(p.textSecondary)
            }
        } else if let error = state.error {
            ErrorNote(error)
        } else if let result = state.result {
            VStack(alignment: .leading, spacing: 2) {
                switch result {
                case .match:
                    Text("✓ " + tr(.checkMatch, ["name": name])).font(RFont.bodyBold).foregroundColor(p.success)
                    Text(tr(.checkMatchSave, ["name": name])).foregroundColor(p.textSecondary)
                case .typo:
                    Text(tr(.checkTypo)).font(RFont.bodyBold).foregroundColor(p.warning)
                    Text(tr(.checkTypoAction, ["name": name])).foregroundColor(p.textSecondary)
                case .mismatch:
                    Text(state.mode == .oldCode ? tr(.checkOldCodeMismatch, ["name": name]) : tr(.checkMismatch, ["name": name]))
                        .font(RFont.bodyBold).foregroundColor(p.danger)
                }
                if state.stopped {
                    Text(tr(.checkStop, ["name": name])).foregroundColor(p.textSecondary).padding(.top, 2)
                } else if state.mode == .words && result != .match {
                    Button(tr(.checkAgain)) { state.typeAgain() }
                        .buttonStyle(RButtonStyle(.plain))
                        .padding(.top, 2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
        }
    }
}

/// The intro above the check: how to compare the words, or, in old-code mode, the old code.
struct CheckWordsIntro: View {
    @ObservedObject var state: CheckWordsState
    let name: String

    var body: some View {
        Text(CheckWordsIntro.text(mode: state.mode, name: name))
    }

    static func text(mode: CheckWordsState.Mode, name: String) -> String {
        switch mode {
        case .words: return tr(.checkBody, ["name": name])
        case .oldCode: return tr(.checkOldCodeIntro, ["name": name])
        }
    }
}

/// Later (not verified) / Check, or Done after a match. After three mismatches only Later remains.
struct CheckWordsButtons: View {
    @ObservedObject var state: CheckWordsState
    let close: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if state.matched {
            Button(tr(.commonDone), action: close)
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        } else {
            Button(tr(.checkLater), action: close)
                .buttonStyle(RButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            if !state.stopped {
                Button(tr(.checkVerify)) { Task { await state.check(model) } }
                    .buttonStyle(RButtonStyle(.primary))
                    .disabled(!state.canCheck)
            }
        }
    }
}

public struct CheckWordsSheet: View {
    let address: String
    var highlight: Int?
    @EnvironmentObject private var model: AppModel
    @StateObject private var state: CheckWordsState

    public init(address: String, state: CheckWordsState? = nil, highlight: Int? = nil) {
        self.address = address
        self.highlight = highlight
        self._state = StateObject(wrappedValue: state ?? CheckWordsState(address: address))
    }

    public var body: some View {
        let name = model.contact(address)?.name ?? Fallback.short(address)
        SheetFrame(tr(.checkTitle, ["name": name]), subtitle: CheckWordsIntro.text(mode: state.mode, name: name), width: 560) {
            CheckWordsBody(state: state, name: name, highlight: highlight)
        } footer: {
            CheckWordsButtons(state: state) { model.sheet = nil }
        }
    }
}
