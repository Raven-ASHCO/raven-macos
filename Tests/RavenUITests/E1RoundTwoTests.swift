import Foundation
import SwiftUI
import Testing
@testable import RavenUI

/// The second round of E1 fixes in the Mac app (network state from one source, presence, privacy
/// words, plain Check network, outgoing messages from the terminal app, lock, friend actions).
@MainActor
@Suite struct E1RoundTwoTests {
    func readyModel(network: MockRaven.NetworkMode = .release) async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0, network: network)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        return (model, mock)
    }

    /// 1. Settings > Network shows the Network page's states (network.status), one state per row.
    @Test func settingsAndTheNetworkPageShareOneSource() async throws {
        let (model, _) = await readyModel(network: .lab)
        await model.network.refresh()
        let status = try #require(model.network.status)
        let ways = NetworkContent.ways(status)
        #expect(ways.map(\.id) == NetworkContent.shownWays.filter { status.way($0) != nil })
        for way in ways {
            #expect(way.state == status.way(way.id)?.state)
        }
        // "Off" beside "In use now" can't be drawn: only an on way says it isn't in use.
        #expect(Display.runningNote(state: .off, running: true) == nil)
        #expect(Display.runningNote(state: .on, running: true) == nil)
        #expect(Display.runningNote(state: .lab, running: false) == tr(.networkRunningNo))
    }

    /// 1. The Routes panel's mail-friend count is the list it shows.
    @Test func mailFriendCountIsTheListShown() throws {
        let json = #"{"address":"a","verified":true,"hide_ip":false,"routes":[],"learned":{"relays":0,"direct":0,"mail_friends":0,"peer_id_proven":false},"carriers":{"hints":"lab","told":[{"address":"b","name":"mac-b","takes_handoffs":false}],"told_unknown":0,"listed":[],"receipts_stranded":false}}"#
        let routes = try JSONValue.decoder.decode(ContactRoutes.self, from: Data(json.utf8))
        #expect(Display.mailFriendCount(routes) == 1)
    }

    /// 4. "Listening on your Wi-Fi" only on Wi-Fi.
    @Test func theQuietLineNamesWiFiOnlyOnWiFi() async throws {
        let (model, _) = await readyModel()
        let node = try #require(model.node)
        #expect(Display.quietTicker(node: node, friends: 2, wifi: false)?.contains("Wi-Fi") == false)
        #expect(Display.quietTicker(node: node, friends: 2, wifi: true)?.contains("Wi-Fi") == true)
    }

    /// 5. A friend whose messages are in the chat says when, not "No recent contact".
    @Test func aFriendWithMessagesSaysWhen() {
        var c = Contact(address: "a", name: "win-c", shortAddress: "a", verified: true, presence: .none)
        c.lastContactMs = testStart.addingTimeInterval(-3 * 3600).ms
        #expect(Display.statusLine(c, now: testStart).text == tr(.homeLastContact, ["when": TimeText.ago(since: 3 * 3600)]))
        c.lastContactMs = nil
        #expect(Display.statusLine(c, now: testStart).text == tr(.homeNoRecent))
    }

    /// 6. Settings > Privacy says what is and isn't encrypted, with no switch drawn on.
    @Test func privacySaysWhatIsEncrypted() throws {
        let sealed = try JSONValue.decoder.decode(PrivacyState.self, from: Data(#"{"available":false,"encrypted":true,"locked":false}"#.utf8))
        let lines = SettingsView.storedLines(sealed)
        #expect(lines == [tr(.settingsStoredEncrypted), tr(.settingsStoredPlain)])
        let plain = try JSONValue.decoder.decode(PrivacyState.self, from: Data(#"{"available":false,"encrypted":false,"locked":false}"#.utf8))
        #expect(SettingsView.storedLines(plain) == [tr(.settingsStoredNotEncrypted)])
    }

    /// 7. Check network: plain sentences; raw lines and the CLI's words only under Technical details.
    @Test func checkNetworkShowsPlainWords() async throws {
        let (model, mock) = await readyModel()
        let check = try await mock.checkNetwork()
        for command in ["`", "ash ", "raven ", "Ctrl-Z"] {
            #expect(!check.nextStep.contains(command))
            #expect(!check.summary.contains { $0.value.contains(command) })
        }
        #expect(!check.summary.contains { $0.key == "next_step" })
        let plain = CheckNetworkPage.plainLines(check.rows)
        #expect(!plain.isEmpty)
        #expect(!plain.contains { $0.contains("=") || $0.contains("reach_class") })
        let technical = CheckNetworkPage.technicalLines(check)
        #expect(technical.contains { $0.hasPrefix("reach_class: ") })
        #expect(technical.contains { $0.contains("ash send") })
        // Bluetooth nearby's raw rows ("turn on: raven nearby enable") go under Technical details.
        await model.network.refresh()
        let status = try #require(model.network.status)
        if let nearby = status.way("nearby") {
            let rows = (status.nearby?.rows ?? []).map { "\($0.label): \($0.value)" }
            #expect(rows.allSatisfy { WayRow.technical(nearby, status).contains($0) })
        }
    }

    /// 8. A message the terminal app sent on this profile shows up in the open chat, with its path.
    @Test func aMessageFromTheTerminalAppShowsUp() async throws {
        let (model, _) = await readyModel()
        let ali = MockRaven.aliAddress
        model.select(ali)
        let before = model.messages[ali]?.count ?? 0
        let m = Message(id: "abc123", address: ali, direction: .outgoing, text: "from the terminal",
                        atMs: testStart.ms, state: .delivered, path: "LAN direct", pathKind: "lan")
        await model.apply([RavenEvent(seq: 900, kind: .outgoing, atMs: testStart.ms, message: m)])
        let list = try #require(model.messages[ali])
        #expect(list.count == before + 1)
        #expect(list.last?.text == "from the terminal")
        #expect(Display.pathChip(kind: list.last?.pathKind, path: list.last?.path) == tr(.chipLan))
        #expect((model.unread[ali] ?? 0) == 0)
        // The same event again changes nothing.
        await model.apply([RavenEvent(seq: 901, kind: .outgoing, atMs: testStart.ms, message: m)])
        #expect(model.messages[ali]?.count == before + 1)
    }

    /// 9. Lock now asks first; Unlock comes back to the page that was open.
    @Test func lockAsksFirstAndUnlockReturnsToThePage() async throws {
        let (model, _) = await readyModel(network: .lab)
        await model.refreshLock()
        #expect(model.canLock)
        model.open(.security)
        model.requestLock()
        #expect(model.sheet == .confirmLock)
        #expect(model.phase == .ready)
        let lines = ConfirmLockSheet.lines(model.lockV2)
        #expect(lines.contains(tr(.lockConfirmDoes)) && lines.contains(tr(.lockConfirmDoesNot)))
        model.sheet = nil
        await model.lock()
        #expect(model.phase == .locked)
        await model.unlockLocked(passphrase: MockRaven.labPassphrase)
        #expect(model.phase == .ready)
        #expect(model.page == .security)
    }

    /// 11. "New message from mac-a · " with nothing after the separator.
    @Test func noDanglingSeparator() {
        #expect(Display.incomingTicker(name: "mac-a", path: "") == "New message from mac-a")
        #expect(Display.incomingTicker(name: "mac-a", path: nil) == "New message from mac-a")
        #expect(Display.incomingTicker(name: "mac-a", path: "LAN direct") == "New message from mac-a · LAN direct")
    }

    /// 12. Rename a friend, delete a message that wasn't sent, and the day line.
    @Test func renameDeleteAndDayLines() async throws {
        let (model, _) = await readyModel()
        let rena = MockRaven.renaAddress
        #expect(await model.renameContact(rena, to: "Rena B") == nil)
        #expect(model.contact(rena)?.name == "Rena B")

        model.select(rena)
        model.composerText = "hello?"
        await model.sendComposer()
        let sent = try #require(model.messages[rena]?.last)
        #expect(!Display.canDelete(sent) || sent.state != .sending)
        // A message that ended unsent offers Delete, and Delete takes it out.
        await model.stopTrying(sent.id)
        let stopped = try #require(model.message(sent.id))
        #expect(Display.canDelete(stopped))
        await model.deleteMessage(sent.id)
        #expect(model.message(sent.id) == nil)

        let cal = Calendar.current
        #expect(TimeText.day(ms: testStart.ms, now: testStart) == tr(.chatToday))
        let yesterday = try #require(cal.date(byAdding: .day, value: -1, to: testStart))
        #expect(TimeText.day(ms: yesterday.ms, now: testStart) == tr(.chatYesterday))
        let older = try #require(cal.date(byAdding: .day, value: -5, to: testStart))
        #expect(TimeText.day(ms: older.ms, now: testStart).contains("-"))
        #expect(TimeText.differentDays(older.ms, testStart.ms))
        #expect(!TimeText.differentDays(testStart.ms, testStart.ms))
    }
}
