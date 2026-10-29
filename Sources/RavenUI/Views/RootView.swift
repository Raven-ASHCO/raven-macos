import SwiftUI

/// The main window's content: picks the screen for the profile state and hosts the sheets.
public struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ravenSnapshot) private var snapshot

    public init() {}

    public var body: some View {
        RootContent()
            .ravenTheme(reducedMotion: model.settings.reducedMotion)
            .onAppear {
                model.windowVisible = true
                model.systemReduceMotion = reduceMotion
                if !snapshot { model.start() }
            }
            .onDisappear { model.windowVisible = false }
            .onChange(of: reduceMotion) { model.systemReduceMotion = $0 }
    }
}

struct RootContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var clock: ClockModel
    @Environment(\.palette) private var p

    var body: some View {
        Group {
            switch model.phase {
            case .loading: Color.clear
            case .welcome: WelcomeView()
            case .setup: SetupView()
            case .ready: MainView()
            case .locked: LockedView()
            case .failed(let error): FailureView(error: error)
            }
        }
        .frame(minWidth: Theme.shared.layout.minWidth, minHeight: Theme.shared.layout.minHeight)
        .background(p.background)
        .sheet(item: $model.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environmentObject(model)
                .environmentObject(clock)
                .ravenTheme(reducedMotion: model.settings.reducedMotion)
        }
    }
}

/// Picks the sheet's view.
public struct SheetHost: View {
    let sheet: AppModel.Sheet
    @EnvironmentObject private var model: AppModel

    public init(sheet: AppModel.Sheet) { self.sheet = sheet }

    public var body: some View {
        switch sheet {
        case .addFriend: AddFriendSheet()
        case .checkWords(let address): CheckWordsSheet(address: address)
        case .messageDetails(let id): MessageDetailsSheet(id: id)
        case .network: NetworkSheet()
        case .quit: QuitDialog()
        case .you: YouSheet()
        case .consent(let setting): ConsentSheet(setting: setting)
        case .restartNode: RestartSheet()
        case .friendRoutes(let address): FriendRoutesSheet(address: address)
        case .confirmLock: ConfirmLockSheet()
        case .rename(let address): RenameSheet(address: address)
        case .newGroup: NewGroupSheet()
        case .groupMembers(let id): GroupMembersSheet(groupID: id)
        case .leaveGroup(let id): LeaveGroupSheet(groupID: id)
        }
    }
}

/// Shown when Raven is locked: by `raven lock` (the privacy pack) or by Lock while running (Lock v2:
/// raven-node keeps running without its keys). Calm: the mark, "Raven is locked", what that means,
/// the Raven passphrase field when the profile has one (it goes only to raven-node), Unlock; the card
/// fades in (`lockedFade`) and shakes once when the passphrase is wrong.
public struct LockedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @ViewState private var passphrase = ""
    @ViewState private var working = false
    @ViewState private var shake: CGFloat = 0
    @ViewState private var shown = false

    public init() {}

    public var body: some View {
        let v2 = model.lockV2?.locked == true
        let askPassphrase = v2 && (model.lockV2?.hasPassphrase == true || model.lockError?.code == ErrorCode.passphraseNeeded)
        VStack(spacing: 8) {
            RavenMark(size: 76, color: p.textPrimary).padding(.bottom, 6)
            Text(tr(.lockTitle)).font(.system(size: 20, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if v2 {
                Text(tr(.lockBody)).font(.system(size: 13)).foregroundColor(p.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }
            if askPassphrase {
                RField(tr(.lockPassphrase), text: $passphrase, secure: true) { unlock() }
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(tr(.lockPassphrase))
            }
            Button { unlock() } label: { Text(tr(.lockUnlock)).frame(maxWidth: .infinity) }
                .buttonStyle(RButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(working)
            if let error = v2 ? model.lockError : model.actionError { ErrorNote(error) }
            if askPassphrase {
                Text(tr(.lockPassphraseNote)).font(.system(size: 11.5)).foregroundColor(p.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .frame(width: 360)
        .modifier(ShakeEffect(amount: shake))
        .opacity(shown || motionOff ? 1 : 0)
        .offset(y: shown || motionOff ? 0 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.background)
        .onAppear {
            if motionOff { shown = true } else {
                withAnimation(Theme.shared.curve("sheet", Theme.shared.motion.lockedFade)) { shown = true }
            }
        }
        .onChange(of: model.lockError?.code) { code in
            guard !motionOff, code == ErrorCode.passphraseWrong || code == ErrorCode.passphraseNeeded else { return }
            shake = 0
            withAnimation(.easeInOut(duration: Theme.shared.motion.shake)) { shake = 1 }
        }
    }

    private func unlock() {
        guard !working else { return }
        working = true
        let typed = passphrase
        Task {
            await model.unlockLocked(passphrase: typed)
            passphrase = ""
            working = false
        }
    }
}

/// Two quick moves left and right (8 points), as the prototype's wrong-passphrase shake.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}

/// The profile could not be opened, or the engine is missing: what happened, one next step, Details.
struct FailureView: View {
    let error: RavenError

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RavenMark(size: 56)
            ErrorNote(error)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
