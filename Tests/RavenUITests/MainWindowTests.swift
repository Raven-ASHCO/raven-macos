import Foundation
import Testing
@testable import RavenUI

/// The main window: what the composer keeps for each chat, and what the route line plays.
@MainActor
@Suite struct MainWindowTests {
    func readyModel(demo: Bool = true) async -> (AppModel, MockRaven) {
        let mock = readyMock(demo: demo)
        let model = AppModel(engine: mock, now: { mock.clock.now })
        await model.bootstrap()
        await model.pollNow()
        return (model, mock)
    }

    /// One clock tick and one poll per second.
    func advance(_ model: AppModel, _ mock: MockRaven, seconds: Int) async {
        for _ in 0..<seconds {
            mock.clock.advance(1)
            model.tick()
            await model.pollNow()
        }
    }

    /// The composer is one field for every chat and group. A text typed for a friend stayed in it when
    /// the group that was open before came back, where Return sent it to everyone.
    @Test func eachChatKeepsItsOwnDraft() async throws {
        let (model, _) = await readyModel(demo: false)
        let club = MockRaven.bookClubID
        model.selectGroup(club)
        model.select(MockRaven.minaAddress)
        model.composerText = "Only for Mina"
        model.selectGroup(club)
        #expect(model.composerText.isEmpty)
        model.composerText = "For the whole club"
        model.select(MockRaven.minaAddress)
        #expect(model.composerText == "Only for Mina")
        model.select(MockRaven.aliAddress)
        #expect(model.composerText.isEmpty)
        model.open(.network)
        #expect(model.composerText.isEmpty)
        model.selectGroup(club)
        #expect(model.composerText == "For the whole club")
        await model.sendGroupComposer()
        #expect(model.groupMessages[club]?.last?.text == "For the whole club")
        #expect(model.composerText.isEmpty)
        model.select(MockRaven.minaAddress)
        #expect(model.composerText == "Only for Mina")
        model.selectGroup(club)
        #expect(model.composerText.isEmpty)           // sent: no draft left behind
    }

    /// Each swap is counted, so the composer does not read another chat's draft as typing.
    @Test func aDraftSwapIsCounted() async {
        let (model, _) = await readyModel(demo: false)
        model.select(MockRaven.minaAddress)
        let swaps = model.draftSwaps
        model.select(MockRaven.minaAddress)           // the same chat: nothing swapped
        #expect(model.draftSwaps == swaps)
        model.select(MockRaven.aliAddress)
        #expect(model.draftSwaps == swaps + 1)
    }

    /// A send the engine refused took its text with it; now the text comes back to type again.
    @Test func aRefusedSendGivesItsTextBack() async throws {
        let (model, _) = await readyModel(demo: false)
        model.select(MockRaven.minaAddress)
        let long = String(repeating: "a", count: 4001)
        model.composerText = long
        await model.sendComposer()
        #expect(model.composerText == long)
        #expect(model.toast?.tone == .danger)

        model.selectGroup(MockRaven.bookClubID)
        let longer = String(repeating: "b", count: 8200)
        model.composerText = longer
        await model.sendGroupComposer()
        #expect(model.composerText == longer)
        model.select(MockRaven.minaAddress)
        #expect(model.composerText == long)
    }

    /// A packet for a chat that was not on screen flew, late, when the chat came back.
    @Test func routeMotionsOnlyForTheChatOnScreen() async {
        let (model, mock) = await readyModel()
        model.routeQueue = []
        model.open(.network)                          // Ali stays selected behind the Network page
        await advance(model, mock, seconds: 2)        // Ali's message arrives at 1.2 s
        #expect(model.messages[MockRaven.aliAddress]?.last?.text == "Great. Can you bring the charger?")
        #expect(model.routeQueue.isEmpty)
        model.select(MockRaven.aliAddress)
        #expect(model.routeQueue.isEmpty)
        await advance(model, mock, seconds: 3)        // the demo send to Ali starts at 4.5 s
        #expect(model.routeQueue.map(\.kind) == [.out])
        model.open(.settings)                         // the route line leaves the screen: so do its packets
        #expect(model.routeQueue.isEmpty)
    }

    /// A toast of two or three lines covered the newest message's status in a narrow chat. The list
    /// keeps room for it, measured at the toast's own width.
    @Test func theListMeasuresTheToastAtItsOwnWidth() {
        #expect(ComposerBar.toastWidth(in: 340) == 340 - 2 * ComposerBar.toastInset)   // the smallest window
        #expect(ComposerBar.toastWidth(in: 1200) == ComposerBar.toastMaxWidth)
        #expect(ComposerBar.toastWidth(in: 20) == 0)
    }
}

/// What the main window says: whole or in a shorter form, never cut, and in plain words.
@MainActor
@Suite struct MainWindowTextTests {
    let now = testStart

    /// The search left every group in the sidebar, and said nothing when nothing matched.
    @Test func searchFindsGroupsToo() async {
        let mock = readyMock(demo: false)
        let model = AppModel(engine: mock, now: { mock.clock.now })
        await model.bootstrap()
        #expect(model.filteredGroups.map(\.name) == ["Book club"])
        model.searchText = "book"
        #expect(model.filteredGroups.map(\.name) == ["Book club"] && model.filteredContacts.isEmpty)
        model.searchText = "Plumber"
        #expect(model.filteredGroups.isEmpty && model.filteredContacts.isEmpty)
        #expect(tr(.macHomeSearchNone, ["query": "Plumber"]) == "Nothing found for “Plumber”")
        model.groupsAvailable = false
        model.searchText = ""
        #expect(model.filteredGroups.isEmpty)
    }

    /// "1 waiting · until Wed 1…", "Raven's background…", "Fingerprint If4x-36F…": each has a shorter
    /// form that fits whole.
    @Test func shortFormsSayTheSameWithoutCutting() {
        var c = Contact(address: "a", name: "Mina", shortAddress: "a", verified: true, presence: .waiting)
        #expect(Display.shortStatus(c) == nil)
        c.waiting = Waiting(count: 2, untilMs: now.addingTimeInterval(22 * 3600).ms)
        #expect(Display.statusLine(c, now: now).text.hasPrefix("2 waiting · until "))
        #expect(Display.shortStatus(c) == "2 waiting")

        let waiting = Message(id: "1", address: "a", direction: .outgoing, text: "t", atMs: now.ms, state: .waiting,
                              untilMs: now.addingTimeInterval(22 * 3600).ms)
        #expect(Display.status(waiting, name: "Mina", now: now).text.hasPrefix("Waiting for Mina · until "))
        #expect(Display.shortStatus(waiting, name: "Mina") == "Waiting for Mina")
        var delivered = waiting
        delivered.state = .delivered
        #expect(Display.shortStatus(delivered, name: "Mina") == nil)

        let node = NodeStatus(running: true, startedByApp: true, receive: true, lastOkMs: now.ms, build: "dev",
                              carriers: Carriers(lan: "on", internet: "preview", p2p: "preview", custody: "preview"))
        let ok = Display.sidebarHeartbeat(node: node, lastOk: now, now: now.addingTimeInterval(4))
        #expect(ok.ok && ok.text == "your node: ok · 4 s" && ok.short == "ok · 4 s")
        let down = Display.sidebarHeartbeat(node: nil, lastOk: now, now: now)
        #expect(!down.ok && down.text == "your node: not responding" && down.short == "not responding")

        #expect(Display.routeEnd("Mina") == "Mina")
        #expect(Display.routeEnd("The neighbour from the third floor") == "The neighbour from the…")
    }

    /// The receipt's toast said "via –" when the receipt named no path.
    @Test func aReceiptWithoutAPathSaysNoDash() {
        #expect(Display.deliveredTicker(name: "Ali", path: "LAN direct", ms: 600)
                == "Delivered to Ali via LAN direct in 0.6 s · receipt signed by Ali")
        #expect(Display.deliveredTicker(name: "Ali", path: nil, ms: 600) == "Delivered to Ali in 0.6 s · receipt signed by Ali")
        #expect(Display.deliveredTicker(name: "Ali", path: " ", ms: 600) == "Delivered to Ali in 0.6 s · receipt signed by Ali")
    }

    /// In a narrow sidebar the fingerprint is the code alone, which skipped the cleaning the whole line
    /// has: an override character in the code could turn the text around.
    @Test func theShortFingerprintIsCleanedLikeTheWholeLine() {
        let id = Identity(address: "a", words: [], oldCode: "\u{202E}KLHQ-uLWW-5iB0\u{200B}")
        #expect(Display.youCode(id) == "KLHQ-uLWW-5iB0")
        #expect(Display.you(id, name: nil).fingerprint == "Fingerprint KLHQ-uLWW-5iB0")
        #expect(Display.youCode(Identity(address: "a", words: [], oldCode: " ")) == nil)
        #expect(Display.youCode(nil) == nil)
    }

    /// Visible texts in plain words: no apostrophes, hyphens or dashes, and "No Raven server" (never a
    /// plain "no server").
    @Test func theMainWindowSaysItPlainly() {
        func plain(_ text: String) -> Bool {
            text.range(of: #"['’–—]|\w-\w"#, options: .regularExpression) == nil
                && text.range(of: "no server", options: .caseInsensitive) == nil
        }
        let name = ["name": "Mina"]
        var shown = [tr(.macChatEncrypted, name), tr(.macChatEncryptedShort), tr(.macGroupsEncrypted),
                     tr(.macHomeBannerNotVerified, name), tr(.macChatAwayTitle, name), tr(.macHomeNoFriendsBody),
                     tr(.macHomeSearchNone, ["query": "Sam"]), tr(.macHomeWaitingShort, ["n": "1"]),
                     Display.deliveredTicker(name: "Ali", path: nil, ms: 600)]
        for state in [MessageState.sending, .sent, .delivered, .waiting, .timeRanOut, .notSentMeetFirst, .failed] {
            let m = Message(id: "1", address: "a", direction: .outgoing, text: "t", atMs: now.ms, state: state,
                            untilMs: now.addingTimeInterval(3600).ms)
            shown.append(Display.status(m, name: "Mina", now: now).text)
        }
        let hb = Display.sidebarHeartbeat(node: nil, lastOk: nil, now: now)
        shown += [hb.text, hb.short]
        for text in shown { #expect(plain(text), "\(text)") }
        #expect([tr(.macChatEncrypted, name), tr(.macChatEncryptedShort), tr(.macGroupsEncrypted)]
            .allSatisfy { $0.contains("No Raven server") })
    }
}
