import Foundation
import Network
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
        // Listening on this computer's loopback address only.
        var local = node
        local.listening = "\(IPv4Address.loopback):" + port
        #expect(local.localOnly)
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

    /// A background program that runs with its listener down (the engine's `send_only`, or one that
    /// does not answer) showed "Listening on your network." in green while the menu said Raven is not
    /// receiving; one on the IPv6 loopback address counted as listening on the network.
    @Test func aProgramThatDoesNotListenIsNotCalledListening() async throws {
        let (model, _) = await readyModel()
        let listening = try #require(model.node)
        #expect(Display.listening(listening).text == tr(.macNetworkListening))
        var node = listening
        node.listening = nil
        for state in ["send_only", "not_answering"] {
            node.state = state
            #expect(Display.listening(node).text == tr(.networkThisComputerNotListening))
            #expect(Display.listening(node).tone == .warning)
        }
        node.state = "starting"
        #expect(Display.listening(node).text == tr(.netStarting))
        // An engine without `state` (and the mock): running and receiving without a listener is starting.
        node.state = nil
        #expect(Display.listening(node).text == tr(.netStarting))

        node.listening = "[\(IPv6Address.loopback)]:7420"
        #expect(node.localOnly && Display.listening(node).text == tr(.macNetworkLocalOnly))
        node.listening = listening.listening
        node.state = "local_only"
        #expect(node.localOnly && Display.listening(node).text == tr(.macNetworkLocalOnly))
    }

    // MARK: Plain words

    /// An apostrophe, a hyphen or a dash, or a plain "no server" (owner rule: visible texts in plain
    /// English, and "No Raven server").
    static func plain(_ text: String) -> Bool {
        text.range(of: #"['’–—]|\w-\w"#, options: .regularExpression) == nil
            && text.range(of: "no server", options: .caseInsensitive) == nil
    }

    /// Raven-node's sentences said "isn't", "Raven's background program", "Peer-to-peer" and "NAT-PMP"
    /// on the Network screens.
    @Test func ravenNodesSentencesReadInPlainWords() {
        let said = [
            ("Raven's background program isn't running.", "The Raven background program is not running."),
            ("Running now: Raven's background program was started with this way on.",
             "Running now: the Raven background program was started with this way on."),
            ("On for testing only: a developer build's lab switch turned it on.",
             "On for testing only: a lab switch in a developer build turned it on."),
            ("Peer-to-peer isn't running, so only direct ways are used.", "Peer to peer is not running, so only direct ways are used."),
            ("Your router didn't answer NAT-PMP.", "Your router did not answer NAT\u{00A0}PMP."),
            ("Ready, but your onion service can't be reached right now.", "Ready, but your onion service cannot be reached right now."),
            ("Raven won't ask your router to open a port.", "Raven will not ask your router to open a port."),
            ("Reserved for relaying between Raven's own links. This version of Raven's background program doesn't use it.",
             "Reserved for relaying between Raven links. This version of the Raven background program does not use it."),
            ("Someone you don’t know tried to connect 3 times", "Someone you do not know tried to connect 3 times"),
            ("Same network (Wi-Fi, cable or hotspot)", "Same network (WiFi, cable or hotspot)"),
        ]
        for (engine, app) in said { #expect(Display.plainWords(engine) == app) }
        // Words that need nothing stay as they are.
        #expect(Display.plainWords("Ready: friends can reach you over Tor, and you them.") == "Ready: friends can reach you over Tor, and you them.")
    }

    /// The way names (and every reason, effect and line raven-node gives these screens) in plain words.
    @Test func theNetworkScreensSayRavenNodesWordsPlainly() async throws {
        for mode in [MockRaven.NetworkMode.release, .lab] {
            let (model, mock) = await readyModel(network: mode)
            await model.network.refresh()
            let status = try #require(model.network.status)
            let ways = status.carriers + (status.protections ?? [])
            #expect(!ways.isEmpty)
            for way in ways {
                #expect(Self.plain(Display.wayName(way)), "\(Display.wayName(way))")
                if let reason = way.reason { #expect(Self.plain(Display.plainWords(reason)), "\(reason)") }
            }
            #expect(Display.wayName(try #require(status.way("p2p"))) == "Peer to peer and relays")
            if let effects = status.help?.effects {
                for effect in [effects.store, effects.relay] { #expect(Self.plain(Display.plainWords(effect)), "\(effect)") }
            }
            let check = try await mock.checkNetwork(router: true)
            for line in CheckNetworkPage.plainLines(check.rows) + CheckNetworkPage.plainLines(check.router ?? []) {
                #expect(Self.plain(line), "\(line)")
            }
            let security = try await mock.securityStatus()
            for n in security.notices {
                for text in [n.headline, n.whatRavenDid, n.whatToDo].compactMap({ $0 }) {
                    #expect(Self.plain(Display.plainWords(text)), "\(text)")
                }
            }
        }
    }

    /// Check network named its rows "identity", "raven-node" and "contacts", and said "Next step: All
    /// set: Raven can send ...".
    @Test func checkNetworkNamesItsRowsAndSaysAllSetAsDone() async throws {
        let (_, mock) = await readyModel()
        let check = try await mock.checkNetwork()
        #expect(check.summary.map(Display.checkLabel) == [tr(.macNetworkCheckLabelIdentity), tr(.macNetworkCheckLabelNode),
                                                         tr(.macNetworkCheckLabelLan), tr(.macNetworkCheckLabelContacts)])
        #expect(check.summary.map(Display.checkValue) == ["OK", "Running; you can send and receive", "On", "3"])
        #expect(Display.checkLabel(CheckSummaryRow(key: "cannot_reach", label: "cannot reach", value: "1")) == "Cannot reach")
        let allSet = Display.checkNextStep(check.nextStep)
        #expect(allSet.done && allSet.text == check.nextStep && !allSet.text.contains("Next step"))
        let step = Display.checkNextStep("Raven's background program isn't running. Start it on the Network page.")
        #expect(!step.done && step.text == tr(.networkCheckNextStep, ["step": "The Raven background program is not running. Start it on the Network page."]))
    }

    /// With the desktop engine Check network's summary said "On - " with this computer's address and
    /// port, "This computer only (" with the loopback address, and "port 4001"; its next step named the
    /// loopback address. The doctor's own lines under Technical details keep them. While LAN was off
    /// the Same network row said nothing (the engine drops "off - raven lan on", a command).
    @Test func checkNetworkNamesNoAddressOrPort() {
        let any = "\(IPv4Address.any):7420", loopback = "\(IPv4Address.loopback):7420"
        let loopback6 = "[\(IPv6Address.loopback)]:7420"
        func row(_ key: String, _ value: String) -> CheckSummaryRow { CheckSummaryRow(key: key, label: key, value: value) }
        let said: [(CheckSummaryRow, String)] = [
            (row("lan", "on - \(any)"), "On"),
            (row("lan", "on - \(any), \(loopback6)"), "On"),
            (row("lan", "this computer only (\(loopback))"), "This computer only"),
            (row("lan", "this computer only (\(loopback6))"), "This computer only"),
            (row("lan", "on until 14:30 (local time) - \(any)"), "On until 14:30 (local time)"),
            (row("lan", "on - all networks of this computer, contacts only"), "On: all networks of this computer, contacts only"),
            (row("lan", "off in settings, but the running raven-node still listens on \(any) - restart raven-node to apply"),
             "Off in settings, but the Raven background program still listens: restart the Raven background program to apply"),
            (row("lan", ""), tr(.netWayOff)),
            (row("internet", "reachable through your router's port mapping (UPnP, port 4001); waiting for 2 independent checks to confirm it"),
             "Reachable through a port mapping on your router (UPnP); waiting for 2 independent checks to confirm it"),
            (row("internet", "behind NAT: contacts reach you through 1 relay; your router mapped port 4001, but the check could not reach it"),
             "Behind NAT: contacts reach you through 1 relay; your router mapped a port, but the check could not reach it"),
            (row("disk", "OK \u{2014} 120 GB free"), "OK: 120 GB free"),
            (row("contacts", "3"), "3"),
        ]
        for (r, want) in said {
            let got = Display.checkValue(r)
            #expect(got == want)
            // (14:30 is a time.)
            #expect(!Self.namesAnAddress(got.replacingOccurrences(of: "14:30", with: "")) && Self.plain(got), "\(got)")
        }
        let step = Display.checkNextStep("Friends cannot reach you: Raven's background program listens on this computer only (\(loopback)).")
        #expect(step.text == tr(.networkCheckNextStep, ["step": "Friends cannot reach you: the Raven background program listens on this computer only."]))

        // A row with nothing left to say is not listed; the next step has its own line.
        let check = NetworkCheck(summary: [row("identity", "OK"), row("updates", " - "), row("lan", "")],
                                 nextStep: "All set.", rows: [], router: nil, technical: nil)
        #expect(CheckNetworkPage.summaryRows(check).map(\.key) == ["identity", "lan"])
    }

    /// Every text the Network screens, Settings and the menu bar show, and the lock's, quit's and the
    /// locked window's, in plain words (and "No Raven server" in About).
    @Test func theseScreensSayItPlainly() throws {
        let files = ["Views/NetworkPage.swift", "Views/NetworkSheets.swift", "Views/CheckNetworkPage.swift", "Views/SecurityPages.swift",
                     "Views/SettingsView.swift", "Views/MenuBar.swift", "Views/FriendRoutesSheet.swift",
                     "State/Display+NetworkSettingsLock.swift"]
        let cases = Dictionary(Str.allCases.map { ("\($0)", $0) }, uniquingKeysWith: { a, _ in a })
        let pattern = try NSRegularExpression(pattern: #"(?:tr|options)\(\.([A-Za-z0-9]+)"#)
        var checked = 0
        for file in files {
            let url = packageRoot.appendingPathComponent("Sources/RavenUI").appendingPathComponent(file)
            let source = try String(contentsOf: url, encoding: .utf8)
            for m in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let name = String(source[Range(m.range(at: 1), in: source)!])
                let key = try #require(cases[name], "\(name) in \(file)")
                for text in [tr(key)] + Strings.shared.options(key) {
                    #expect(Self.plain(text), "\(file): \(name): \(text)")
                    checked += 1
                }
            }
        }
        #expect(checked > 100)
        var lock = LockState(available: true, supported: true, locked: false, hasPassphrase: false)
        var shown = ConfirmLockSheet.lines(lock) + ConfirmLockSheet.limits
        lock.hasPassphrase = true
        shown += ConfirmLockSheet.lines(lock)
        shown += [tr(.macQuitRunning), tr(.quitTitle), tr(.macLockLockedBody), tr(.macLockLockedPlainBody), tr(.macLockPassphraseNote),
                  Display.lockNote(nil), Display.passphraseLine, Display.menuMore(3), Display.menuMore(1),
                  // This computer's heartbeat line, as the Network page shows it.
                  Display.plainWords(Display.heartbeat(node: nil, lastOk: nil, now: testStart).text)]
        for text in shown { #expect(Self.plain(text), "\(text)") }
        #expect(tr(.macAboutTagline).contains("No Raven server"))
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

    /// Settings > Lock said "Your Raven keys on this computer open only with your Raven passphrase"
    /// beside the chip Not set up.
    @Test func thePassphraseRowSaysWhenThereIsNone() {
        let none = LockState(available: true, supported: true, locked: false, hasPassphrase: false)
        let set = LockState(available: true, supported: true, locked: false, hasPassphrase: true)
        #expect(Display.passphraseLine(none) == tr(.macLockPassphraseNotInApp))
        // The lock row above says what having none means.
        #expect(Display.lockNote(none) == tr(.lockNoPassphrase))
        for lock in [set, LockState(available: false, supported: false, locked: false), nil] {
            #expect(Display.passphraseLine(lock) == Display.passphraseLine)
        }
        #expect(Self.plain(Display.passphraseLine(none)))
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
