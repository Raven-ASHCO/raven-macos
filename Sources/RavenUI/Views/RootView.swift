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
/// raven-node keeps running without its keys). Calm: the lock scene (just locked, the night comes down
/// over the raven's day and it falls asleep; found locked, it already sleeps), "Raven is locked", what
/// that means, the Raven passphrase field when the profile has one (it goes only to raven-node),
/// Unlock; the card fades in (`lockedFade`) and shakes once when the passphrase is wrong. Once
/// unlocked the night rises and the raven wakes with a stretch (`RavenMotion.wake`) before the main
/// window shows; Reduce Motion: still frames, and the main window at once.
public struct LockedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var p
    @Environment(\.motionOff) private var motionOff
    @Environment(\.ravenSnapshot) private var snapshot
    @ViewState private var passphrase = ""
    @ViewState private var working = false
    @ViewState private var shake: CGFloat = 0
    @ViewState private var shown = false
    /// The lock scene: the night coming down, asleep, or rising once Unlock worked.
    @ViewState private var night: LockScene.Moment
    /// While Unlock works (and the night rises), the card keeps what it showed when Unlock was pressed.
    @ViewState private var held: Layout?
    private let frozen: Date?

    struct Layout: Equatable {
        var v2: Bool
        var askPassphrase: Bool
    }

    /// Snapshots: the scene as it is `lockedFor` seconds after Raven locked, or `wokeFor` seconds after
    /// Unlock worked.
    public init(lockedFor: TimeInterval? = nil, wokeFor: TimeInterval? = nil) {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        if let wokeFor {
            self._night = ViewState(wrappedValue: .waking(start))
            self.frozen = start.addingTimeInterval(wokeFor)
        } else if let lockedFor {
            self._night = ViewState(wrappedValue: .fallingAsleep(start))
            self.frozen = start.addingTimeInterval(lockedFor)
        } else {
            self._night = ViewState(wrappedValue: .asleep)
            self.frozen = nil
        }
    }

    private var layout: Layout {
        if let held { return held }
        let v2 = model.lockV2?.locked == true
        return Layout(v2: v2, askPassphrase: v2 && (model.lockV2?.hasPassphrase == true
                                                    || model.lockError?.code == ErrorCode.passphraseNeeded))
    }

    public var body: some View {
        let layout = self.layout
        let v2 = layout.v2
        let askPassphrase = layout.askPassphrase
        VStack(spacing: 8) {
            LockScene(moment: night, frozen: frozen)
                .frame(height: 190)
                .padding(.bottom, 10)
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
            // Just locked from this app: the night comes down now (found locked, it already sleeps).
            if !snapshot, frozen == nil, night == .asleep, let at = model.lockedAt, Date().timeIntervalSince(at) < 2 {
                night = .fallingAsleep(at)
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
        held = layout
        working = true
        let typed = passphrase
        let rise = !motionOff
        Task {
            await model.unlockLocked(passphrase: typed) {
                // Unlocked: the night rises and the raven wakes with a stretch, then the main window shows.
                guard rise else { return }
                night = .waking(Date())
                try? await Task.sleep(nanoseconds: UInt64(RavenMotion.wake * 1_000_000_000))
            }
            passphrase = ""
            working = false
            held = nil
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
