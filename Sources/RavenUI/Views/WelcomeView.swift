import SwiftUI

/// First launch. The only decorative motion in the app: the mark fades and scales in once
/// (logoReveal, 600 ms) and the tagline is revealed left to right after it. Reduced motion: static.
public struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @Environment(\.ravenSnapshot) private var snapshot
    @ViewState private var revealed = false
    @ViewState private var tagline: CGFloat = 0

    public init() {}

    private var still: Bool { motionOff || snapshot }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            RavenMark(size: 96, color: p.textPrimary)
                .opacity(still || revealed ? 1 : 0)
                .scaleEffect(still || revealed ? 1 : 0.9)
            Text(tr(.appName).uppercased())
                .font(RFont.display)
                .tracking(Theme.shared.type.displayTracking)
                .padding(.top, 8)
                .opacity(still || revealed ? 1 : 0)
                .accessibilityHidden(true)
            Text(tr(.appTagline))
                .foregroundColor(p.textSecondary)
                .padding(.top, 2)
                .mask(Rectangle().scaleEffect(x: still ? 1 : tagline, y: 1, anchor: .leading))
            VStack(alignment: .leading, spacing: 8) {
                Text(tr(.welcomeTitle)).font(RFont.title)
                Text(tr(.welcomeBody1)).fixedSize(horizontal: false, vertical: true)
                Text(tr(.welcomeBody2)).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    step(1, tr(.welcomeStep1))
                    step(2, tr(.welcomeStep2))
                    step(3, tr(.welcomeStep3))
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.top, 22)
            Button(tr(.welcomeStart)) { model.beginSetup() }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 22)
            Spacer(minLength: 16)
        }
        .padding(.horizontal, Theme.shared.spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !still, !revealed else { return }
            let reveal = Theme.shared.motion.logoReveal
            withAnimation(.easeOut(duration: reveal)) { revealed = true }
            withAnimation(.linear(duration: 1.2).delay(reveal)) { tagline = 1 }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(RFont.bodyBold).foregroundColor(p.accent)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Name -> receive messages (with the macOS Local Network sentence) -> creating identity -> words.
public struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @FocusState private var nameFocused: Bool

    public init() {}

    public var body: some View {
        // Calm: each step on a sheet-like card (22 pt corners, the sheet shadow).
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 16)
            content
                .frame(maxWidth: model.setupStep == .words ? 612 : 470, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
                .background(RoundedRectangle(cornerRadius: Theme.shared.radius.sheet, style: .continuous)
                    .fill(p.surface).ravenShadow(p.sheetShadow))
                .overlay(RoundedRectangle(cornerRadius: Theme.shared.radius.sheet, style: .continuous)
                    .strokeBorder(p.border, lineWidth: 1))
            Spacer(minLength: 16)
        }
        .padding(.horizontal, Theme.shared.spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch model.setupStep {
        case .name: nameStep
        case .receive: receiveStep
        case .creating: creatingStep
        case .words: wordsStep
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr(.setupNameTitle)).font(RFont.title)
            Text(tr(.setupNameBody)).foregroundColor(p.textSecondary).fixedSize(horizontal: false, vertical: true)
            RField(tr(.setupNamePlaceholder), text: $model.setupName, focused: $nameFocused) { model.submitName() }
                .frame(maxWidth: 320)
            HStack {
                Spacer()
                Button(tr(.commonContinue)) { model.submitName() }
                    .buttonStyle(RButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { nameFocused = true }
    }

    private var receiveStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr(.setupReceiveTitle)).font(RFont.title)
            Text(tr(.setupReceiveBody)).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "network").foregroundColor(p.accent).accessibilityHidden(true)
                Text(tr(.setupReceiveMacos)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.shared.radius.card).fill(p.accentSoft.opacity(0.6)))
            if let error = model.actionError { ErrorNote(error) }
            HStack(spacing: 8) {
                Spacer()
                Button(tr(.setupReceiveNo)) { Task { await model.chooseReceive(false) } }
                    .buttonStyle(RButtonStyle(.secondary))
                Button(tr(.setupReceiveYes)) { Task { await model.chooseReceive(true) } }
                    .buttonStyle(RButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var creatingStep: some View {
        VStack(spacing: 12) {
            Spinner(size: 22)
            Text(tr(.setupCreating)).font(RFont.title)
            Text(tr(.setupCreatingBody)).foregroundColor(p.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var wordsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr(.wordsTitle)).font(RFont.title)
            Text(tr(.wordsBody)).fixedSize(horizontal: false, vertical: true)
            ReadAloudWords(words: model.identity?.words ?? [])
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(.wordsCheck))
                Text(tr(.wordsNever))
            }
            .font(RFont.smallish)
            .foregroundColor(p.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            OldCodeLine(code: model.identity?.oldCode ?? "")
            HStack {
                Spacer()
                Button(tr(.commonDone)) { Task { await model.finishSetup() } }
                    .buttonStyle(RButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// "Old code (still accepted): {code}" with only the code in the monospaced face, in groups of 4.
struct OldCodeLine: View {
    let code: String
    @Environment(\.palette) private var p

    var body: some View {
        let template = Strings.shared.text(.wordsOldCode)
        let parts = template.components(separatedBy: "{code}")
        let before = parts.first ?? ""
        let after = parts.count > 1 ? parts[1] : ""
        (Text(before) + Text(WordInput.oldCodeGroups(code)).font(RFont.mono).foregroundColor(p.textPrimary) + Text(after))
            .font(RFont.smallish)
            .foregroundColor(p.textSecondary)
            .selectable()
    }
}
