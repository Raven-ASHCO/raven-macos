#if DEBUG || RAVEN_MOCK
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Renders every main screen to PNG with `ImageRenderer`, in light and dark, without opening a
/// window. Each picture comes from a MockRaven on a stopped clock, moved forward through the demo
/// event stream, so the pictures show exactly what the events produce.
@MainActor
public enum SnapshotCatalog {
    public struct Shot {
        public let name: String
        let width: CGFloat
        let height: CGFloat?
        let model: AppModel
        let view: AnyView
        var dark = true
        var scale: CGFloat = 2
    }

    /// Tuesday 2026-10-20 14:05 local time: a fixed moment, so the pictures never change.
    static var baseDate: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 20; c.hour = 14; c.minute = 5
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 1_792_500_000)
    }

    static let window = CGSize(width: 1200, height: 760)

    /// A ready profile, advanced `seconds` into the demo event stream with one clock tick and one
    /// poll per second.
    static func readyModel(after seconds: Int, start: MockRaven.Start = .ready,
                           network: MockRaven.NetworkMode = .release) async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: baseDate)
        let mock = MockRaven(start: start, demo: true, clock: clock, identityDelay: 0, network: network)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        if model.phase == .ready { await model.pollNow() }
        for _ in 0..<seconds {
            clock.advance(1)
            model.tick()
            await model.pollNow()
        }
        model.routeQueue = []
        return (model, mock)
    }

    static func newModel() async -> AppModel {
        let clock = MockClock(fixed: baseDate)
        let model = AppModel(engine: MockRaven(start: .new, demo: true, clock: clock, identityDelay: 0), now: { clock.now })
        await model.bootstrap()
        return model
    }

    static func windowShot(_ name: String, _ model: AppModel, height: CGFloat? = nil) -> Shot {
        Shot(name: name, width: window.width, height: height ?? window.height, model: model, view: AnyView(RootView()))
    }

    /// A ready model on a network page, with what the page reads loaded first (ImageRenderer runs no
    /// `.task`).
    static func pageModel(_ page: AppModel.Page, network: MockRaven.NetworkMode, after seconds: Int = 2) async -> AppModel {
        let (model, _) = await readyModel(after: seconds, network: network)
        await model.network.refresh()
        switch page {
        case .checkNetwork: await model.network.runCheck(router: true)
        case .security: await model.network.loadSecurity()
        case .updates: await model.network.loadUpdates()
        default: break
        }
        model.open(page)
        return model
    }

    /// The Network screens (desktop/api/NETWORK_PARITY.md), a release build's and a lab build's.
    static func networkShots() async -> [Shot] {
        var shots: [Shot] = []
        shots.append(windowShot("31-network-release", await pageModel(.network, network: .release), height: 1900))
        shots.append(windowShot("32-network-lab", await pageModel(.network, network: .lab), height: 2250))
        let consent = await pageModel(.network, network: .lab)
        await consent.network.toggle("carry_for_friends", on: true)
        shots.append(sheetShot("33-consent-carry-for-friends", consent, width: 520, ConsentSheet(setting: "carry_for_friends")))
        let restart = await pageModel(.network, network: .lab)
        await restart.network.toggle("internet", on: true)
        shots.append(sheetShot("34-restart-prompt", restart, width: 480, RestartSheet()))
        shots.append(windowShot("35-check-network", await pageModel(.checkNetwork, network: .release), height: 860))
        let routes = await pageModel(.network, network: .lab)
        await routes.network.loadRoutes(MockRaven.aliAddress)
        shots.append(sheetShot("36-friend-routes", routes, width: 580, FriendRoutesSheet(address: MockRaven.aliAddress)))
        shots.append(windowShot("37-security-lab", await pageModel(.security, network: .lab), height: 760))
        shots.append(windowShot("38-updates-lab", await pageModel(.updates, network: .lab)))
        let (lockSheet, _) = await readyModel(after: 2, network: .lab)
        await lockSheet.refreshLock()
        shots.append(sheetShot("51-lock-sheet", lockSheet, width: 460, ConfirmLockSheet()))
        let (locked, _) = await readyModel(after: 2, network: .lab)
        await locked.lockNow()
        shots.append(windowShot("39-locked-while-running", locked))
        let (paths, _) = await readyModel(after: 2, network: .lab)
        shots.append(windowShot("40-main-lab-paths", paths))
        // The smallest window (tokens.json minWindow): the chat header still shows Routes (E1).
        let (narrow, _) = await readyModel(after: 12, network: .lab)
        shots.append(Shot(name: "41-main-smallest-window", width: Theme.shared.layout.minWidth,
                          height: Theme.shared.layout.minHeight, model: narrow, view: AnyView(RootView())))
        return shots
    }

    /// A ready model on a Settings section, with what the section reads loaded first.
    static func settingsModel(_ section: AppModel.SettingsSection, network: MockRaven.NetworkMode = .release) async -> AppModel {
        let (model, _) = await readyModel(after: 2, network: network)
        await model.network.refresh()
        await model.network.loadUpdates()
        await model.refreshLock()
        model.openSettings(section)
        return model
    }

    /// Groups (lab in a real build; the demo engine has them): the group chat with a message's
    /// receipts open, a new group, the members.
    static func groupShots() async -> [Shot] {
        var shots: [Shot] = []
        let (group, _) = await readyModel(after: 3)
        group.selectGroup(MockRaven.bookClubID)
        if let mine = group.groupMessages[MockRaven.bookClubID]?.last(where: { $0.mine }) {
            group.groupDetailsOpen.insert(mine.id)
        }
        shots.append(windowShot("46-group-chat", group))
        let (after, _) = await readyModel(after: 9)
        after.selectGroup(MockRaven.bookClubID)
        shots.append(windowShot("47-group-all-delivered", after))
        let (create, _) = await readyModel(after: 2)
        shots.append(sheetShot("48-group-new", create, width: 480,
                               NewGroupSheet(name: "Weekend trip", chosen: [MockRaven.aliAddress, MockRaven.minaAddress])))
        let (members, _) = await readyModel(after: 2)
        shots.append(sheetShot("49-group-members", members, width: 460, GroupMembersSheet(groupID: MockRaven.bookClubID)))
        // A friend away whose message waits with a friend (lab paths), in the Calm away card.
        let (away, _) = await readyModel(after: 2, network: .lab)
        away.select(MockRaven.minaAddress)
        shots.append(windowShot("50-chat-away-held", away))
        return shots
    }

    static func sheetShot<V: View>(_ name: String, _ model: AppModel, width: CGFloat, _ view: V) -> Shot {
        Shot(name: name, width: width, height: nil, model: model, view: AnyView(view))
    }

    public static func shots() async -> [Shot] {
        var shots: [Shot] = []

        // Welcome and setup.
        shots.append(windowShot("01-welcome", await newModel()))
        let name = await newModel()
        name.beginSetup()
        shots.append(windowShot("02-setup-name", name))
        let receive = await newModel()
        receive.beginSetup()
        receive.setupStep = .receive
        shots.append(windowShot("03-setup-receive", receive))
        let creating = await newModel()
        creating.beginSetup()
        creating.setupStep = .creating
        shots.append(windowShot("04-setup-creating", creating))
        let words = await newModel()
        words.beginSetup()
        await words.chooseReceive(true)
        shots.append(windowShot("05-setup-words", words))

        // Main window at moments of the demo stream.
        let (waiting, _) = await readyModel(after: 2)
        waiting.select(MockRaven.minaAddress)
        shots.append(windowShot("06-main-mina-waiting", waiting))

        let (sending, _) = await readyModel(after: 5)
        sending.snapshotRoute = AppModel.PinnedRoute(kind: .out, progress: 0.45)
        shots.append(windowShot("07-main-packet-out", sending))

        let (receipt, _) = await readyModel(after: 6)
        receipt.snapshotRoute = AppModel.PinnedRoute(kind: .back, progress: 0.4)
        shots.append(windowShot("08-main-receipt-back", receipt))

        let (main, _) = await readyModel(after: 12)
        shots.append(windowShot("09-main-mina-back", main))

        let (rena, _) = await readyModel(after: 12)
        rena.select(MockRaven.renaAddress)
        shots.append(windowShot("10-main-rena-not-verified", rena))

        // Sheets.
        let (details, _) = await readyModel(after: 2)
        if case .success(let d) = await details.details("m3") {
            shots.append(sheetShot("11-message-details", details, width: 480,
                                   MessageDetailsSheet(id: "m3", preset: d, showDetail: true)))
        }

        let (share, mock) = await readyModel(after: 2)
        let card = try? await mock.makeCard(includeAddress: true)
        shots.append(sheetShot("12-add-friend-share", share, width: 560,
                               AddFriendSheet(state: AddFriendState(step: 1, includeAddress: true, card: card))))

        let (paste, pasteMock) = await readyModel(after: 2)
        let sample = "raven-card/1 address=rvn1qz8m4c7hj2kd9wl0a6vrsx5qtyn3pfe8gu7c2hla pub_hex=00 fingerprint=Ab3d-Ef56-Gh78 lan=192.168.1.42:7420"
        let summary = try? await pasteMock.parseCard(sample)
        shots.append(sheetShot("13-add-friend-paste", paste, width: 560,
                               AddFriendSheet(state: AddFriendState(step: 2, summary: summary, name: "Sam"))))

        let (typing, _) = await readyModel(after: 2)
        let renaTyped = Array(MockRaven.renaWords.prefix(6))
        shots.append(sheetShot("14-check-words-typing", typing, width: 560,
                               CheckWordsSheet(address: MockRaven.renaAddress,
                                               state: CheckWordsState(address: MockRaven.renaAddress, typed: renaTyped,
                                                                      field: "bab", hint: "baby"),
                                               highlight: 3)))

        for (label, address, typed) in [
            ("15-check-words-match", MockRaven.aliAddress, MockRaven.aliWords),
            ("16-check-words-typo", MockRaven.aliAddress, MockRaven.aliWords.enumerated().map { $0.offset == 4 ? "gold" : $0.element }),
            ("17-check-words-mismatch", MockRaven.renaAddress, MockRaven.minaWords),
        ] {
            let (m, _) = await readyModel(after: 2)
            let state = CheckWordsState(address: address, typed: typed)
            state.result = try? await m.checkWords(address: address, words: typed)
            shots.append(sheetShot(label, m, width: 560, CheckWordsSheet(address: address, state: state, highlight: 0)))
        }

        // Old code, for a friend with an older Raven: one plain field, the result only at the end.
        let (oldCode, _) = await readyModel(after: 2)
        shots.append(sheetShot("26-check-old-code", oldCode, width: 560,
                               CheckWordsSheet(address: MockRaven.renaAddress,
                                               state: CheckWordsState(address: MockRaven.renaAddress, mode: .oldCode,
                                                                      oldCode: "Tq7m 29Xa"))))
        let (oldMismatch, _) = await readyModel(after: 2)
        let oldMismatchState = CheckWordsState(address: MockRaven.renaAddress, mode: .oldCode, oldCode: "Tq7m-29Xa-hKe5")
        await oldMismatchState.check(oldMismatch)
        shots.append(sheetShot("27-check-old-code-mismatch", oldMismatch, width: 560,
                               CheckWordsSheet(address: MockRaven.renaAddress, state: oldMismatchState)))
        let (oldMatch, _) = await readyModel(after: 2)
        let oldMatchState = CheckWordsState(address: MockRaven.renaAddress, mode: .oldCode, oldCode: MockRaven.renaOldCode)
        await oldMatchState.check(oldMatch)
        shots.append(sheetShot("28-check-old-code-match", oldMatch, width: 560,
                               CheckWordsSheet(address: MockRaven.renaAddress, state: oldMatchState)))

        // Three mismatches: Check is withdrawn.
        let (stop, _) = await readyModel(after: 2)
        let stopState = CheckWordsState(address: MockRaven.renaAddress, typed: MockRaven.minaWords, mismatches: 2)
        await stopState.check(stop)
        shots.append(sheetShot("29-check-words-stop", stop, width: 560,
                               CheckWordsSheet(address: MockRaven.renaAddress, state: stopState, highlight: 0)))

        let (net, _) = await readyModel(after: 2)
        shots.append(sheetShot("18-network", net, width: 440, NetworkSheet()))

        // Settings in the main window (Calm): one picture per section.
        for (name, section) in [("19-settings-general", AppModel.SettingsSection.general), ("20-settings-privacy", .privacy),
                                ("21-settings-network", .network), ("42-settings-appearance", .appearance),
                                ("43-settings-lock", .lock), ("44-settings-updates", .updates), ("45-settings-about", .about)] {
            shots.append(windowShot(name, await settingsModel(section)))
        }

        let (menu, _) = await readyModel(after: 3)
        shots.append(sheetShot("22-menu-bar", menu, width: 310, MenuBarContent(openMain: {})))

        let (quit, _) = await readyModel(after: 2)
        shots.append(sheetShot("23-quit", quit, width: 460, QuitDialog()))
        // Erase (shown only once privacy.state says available; not in this release).
        shots.append(sheetShot("30-erase-confirm", quit, width: 460, EraseSheet(typed: "erase", close: {})))

        let (locked, _) = await readyModel(after: 0, start: .locked)
        shots.append(windowShot("24-locked", locked))

        let missing = AppModel(engine: MissingEngine())
        await missing.bootstrap()
        shots.append(windowShot("25-release-without-engine", missing))

        shots += await networkShots()
        shots += await groupShots()

        var dmg = sheetShot("dmg-background", main, width: 600, DmgBackground())
        dmg.dark = false
        dmg.scale = 1   // Finder shows a window background at its pixel size
        shots.append(dmg)
        return shots
    }

    /// Renders every shot (light and dark) into `directory`; returns the files written.
    public static func renderAll(to directory: URL) async throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for shot in await shots() {
            for scheme in shot.dark ? [ColorScheme.light, .dark] : [.light] {
                guard let image = render(shot, scheme: scheme) else {
                    throw RavenError.internalError("ImageRenderer returned no image for \(shot.name)")
                }
                let suffix = shot.dark ? (scheme == .dark ? "-dark" : "-light") : ""
                let url = directory.appendingPathComponent("\(shot.name)\(suffix).png")
                try writePNG(image, to: url)
                written.append(url)
            }
        }
        return written
    }

    static func render(_ shot: Shot, scheme: ColorScheme) -> CGImage? {
        let content = shot.view
            .frame(width: shot.width, height: shot.height)
            .environmentObject(shot.model)
            .environmentObject(shot.model.clock)
            .ravenTheme(reducedMotion: false)
            .environment(\.ravenSnapshot, true)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = shot.scale
        renderer.proposedSize = ProposedViewSize(width: shot.width, height: shot.height)
        return renderer.cgImage
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RavenError.internalError("cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw RavenError.internalError("cannot finish \(url.path)") }
    }
}
#endif

import SwiftUI

/// The DMG window background used by scripts/make-dmg.sh --layout: Finder places the Raven icon
/// at (150, 170) and Applications at (450, 170); this draws the arrow and the instruction.
public struct DmgBackground: View {
    @Environment(\.palette) private var p

    public init() {}

    public var body: some View {
        ZStack {
            p.background
            Path { path in
                path.move(to: CGPoint(x: 230, y: 170))
                path.addLine(to: CGPoint(x: 362, y: 170))
            }
            .stroke(p.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(p.textSecondary)
                .position(x: 368, y: 170)
            Text(tr(.installDmgInstruction))
                .font(RFont.body)
                .foregroundColor(p.textSecondary)
                .position(x: 300, y: 300)
        }
        .frame(width: 600, height: 380)
    }
}
