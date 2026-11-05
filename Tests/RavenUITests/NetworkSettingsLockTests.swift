import Foundation
import Testing
@testable import RavenUI

/// The Mac app's UI pass on the Network screens, Settings, the lock (the Night curtain) and the menu
/// bar: privacy, plain words, and the states the stills showed broken.
@MainActor
@Suite struct NetworkSettingsLockTests {
    func readyModel(network: MockRaven.NetworkMode = .release) async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0, network: network)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        return (model, mock)
    }

    /// An IP address, a port after a colon, or a process number.
    static func namesAnAddress(_ text: String) -> Bool {
        text.range(of: #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|/ip[46]/|:\d{2,5}\b|\bport \d|process \d"#,
                   options: .regularExpression) != nil
    }

    // MARK: Privacy

    /// Owner rule: addresses and ports only under Details. The This computer card, the Network sheet
    /// and Settings > General named the port, the listening and network addresses and the process; the
    /// peer to peer card its port, its relays and its addresses. Technical details keep every one.
    @Test func portsAndAddressesOnlyUnderTechnicalDetails() async throws {
        let (model, _) = await readyModel(network: .lab)
        await model.network.refresh()
        let status = try #require(model.network.status)
        let node = try #require(model.node)
        let port = try #require(node.port)

        for text in [Display.listening(node).text, Display.process(node), tr(.macSettingsReceiveBody)] {
            #expect(!Self.namesAnAddress(text), "\(text)")
        }
        var local = node
        local.listening = "127.0.0.1:" + port
        #expect(Display.listening(local).text == tr(.macNetworkLocalOnly))
        #expect(!Self.namesAnAddress(Display.listening(local).text))

        let details = Display.thisComputerDetails(status: status, node: node)
        #expect(details.contains(tr(.macNetworkDetailPort, ["port": port])))
        #expect(details.contains { $0.contains(node.listening ?? "?") })
        #expect(details.contains(tr(.macNetworkDetailProcess, ["pid": String(node.pid ?? 0)])))
        if let addr = node.address { #expect(details.contains(tr(.macNetworkDetailAddress, ["addr": addr]))) }

        // While nothing runs, the profile's port.
        var stopped = node
        stopped.running = false
        var idle = status
        idle.node = "not_running"
        #expect(Display.thisComputerDetails(status: idle, node: stopped).first == tr(.macNetworkDetailPort, ["port": String(status.port ?? 0)]))

        // The peer to peer card: where it listens, its relays and every address, under Technical details.
        let p2p = try #require(status.way("p2p"))
        let technical = WayRow.technical(p2p, status)
        let listen = try #require(status.p2pListen)
        #expect(technical.contains(tr(.macNetworkDetailP2pListen, ["addr": listen])))
        let relays = try #require(status.relays)
        #expect(!relays.isEmpty)
        for relay in relays { #expect(technical.contains(tr(.macNetworkDetailRelay, ["relay": relay.relay]))) }
        for a in status.p2pAddresses ?? [] { #expect(technical.contains(tr(.macNetworkDetailP2pAddress, ["addr": a]))) }
        #expect(!Self.namesAnAddress(tr(.macNetworkP2pAddressCount, ["n": "2"])))
    }

    // MARK: Lock (the Night curtain)

    /// Lock now's question said "until you wake it with your passphrase" above "This profile has no
    /// Raven passphrase", and for the plain lock, which asks for no passphrase either.
    @Test func theLockQuestionNamesAPassphraseOnlyWhereWakingAsksForOne() {
        let with = LockState(available: true, supported: true, locked: false, hasPassphrase: true)
        let without = LockState(available: true, supported: true, locked: false, hasPassphrase: false)
        let unknown = LockState(available: true, supported: true, locked: false)
        let plain = LockState(available: false, supported: false, locked: false)
        #expect(ConfirmLockSheet.lines(with) == [tr(.macLockConfirmDoes)])
        #expect(ConfirmLockSheet.lines(without) == [tr(.macLockConfirmDoesNoPassphrase), tr(.lockNoPassphrase)])
        for lock in [unknown, plain, nil] {
            #expect(ConfirmLockSheet.lines(lock) == [tr(.macLockConfirmDoesNoPassphrase)])
        }
        #expect(tr(.macLockConfirmDoes).contains("passphrase"))
        #expect(!tr(.macLockConfirmDoesNoPassphrase).contains("passphrase"))
        #expect(ConfirmLockSheet.limits == [tr(.macLockConfirmDoesNot)])
    }

    // MARK: Menu bar

    /// The menu listed every friend: with many, it grew taller than the screen and Quit was out of
    /// reach. It lists eight, new messages first, and says how many more there are.
    @Test func theMenuListsAtMostEightFriendsNewMessagesFirst() {
        let contacts = (0..<20).map { Contact(address: "a\($0)", name: "Friend \($0)", shortAddress: "a\($0)", verified: true,
                                              presence: .inTouch) }
        let few = Display.menuFriends(Array(contacts.prefix(MenuBarContent.maxFriends)), unread: ["a3": 1],
                                      limit: MenuBarContent.maxFriends)
        #expect(few.shown.map(\.address) == contacts.prefix(MenuBarContent.maxFriends).map(\.address) && few.more == 0)
        let many = Display.menuFriends(contacts, unread: ["a15": 2], limit: MenuBarContent.maxFriends)
        #expect(many.shown.count == MenuBarContent.maxFriends && many.more == 20 - MenuBarContent.maxFriends)
        #expect(many.shown.first?.address == "a15")
        #expect(Display.menuMore(12) == "12 more friends" && Display.menuMore(1) == "1 more friend")
    }

    /// "Neighbour · 1 waiting · until Wed 12:05 (UTC…" was cut in the menu: where the whole line does
    /// not fit it says "Neighbour · 1 waiting" (the chat says until when).
    @Test func aLongMenuLineHasAShortForm() {
        var waiting = Contact(address: "w", name: "Neighbour", shortAddress: "w", verified: true, presence: .waiting)
        waiting.waiting = Waiting(count: 1, untilMs: testStart.addingTimeInterval(3600).ms)
        #expect(Display.menuLine(waiting, unread: 0, now: testStart).hasPrefix("Neighbour · 1 waiting · "))
        #expect(Display.menuLineShort(waiting, unread: 0, now: testStart) == "Neighbour · 1 waiting")
        #expect(Display.menuLineShort(waiting, unread: 2, now: testStart) == "2 new from Neighbour")
        let quiet = Contact(address: "q", name: "Teacher", shortAddress: "q", verified: true, presence: .none)
        #expect(Display.menuLineShort(quiet, unread: 0, now: testStart) == Display.menuLine(quiet, unread: 0, now: testStart))
    }
}
