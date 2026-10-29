import Foundation
import AppKit
import SwiftUI
import Testing
@testable import RavenUI

/// The third round of E1 fixes in the Mac app: one wait for an away friend, the address in use in
/// Routes, the chat that follows your sends, the header that fits, the Return key, the View menu,
/// plain Security and Network lines, the path chip while a friend is away, and late deliveries.
@MainActor
@Suite struct E1RoundThreeTests {
    func readyModel(network: MockRaven.NetworkMode = .release) async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0, network: network)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        return (model, mock)
    }

    func routes(_ json: String) throws -> ContactRoutes {
        try JSONValue.decoder.decode(ContactRoutes.self, from: Data(json.utf8))
    }

    /// 2. Routes says how long a message could wait by the terminal app's rule (`carriers.away`), not
    /// the coverage class's "up to 7 days"; friends carrying it come as a second line, only when one can.
    @Test func routesSayTheTerminalAppsWait() throws {
        let until = testStart.addingTimeInterval(7 * 86_400).ms
        let direct = try routes("""
            {"address":"a","verified":true,"routes":[],"carriers":{"coverage":{"kind":"direct",
            "name":"Raven keeps it until you're both online","until":"for up to 7 days"},"away":{"until_ms":\(until)}}}
            """)
        #expect(Display.awayLines(direct, name: "mac-a", now: testStart)
                == [tr(.networkRoutesAway, ["name": "mac-a", "time": TimeText.deadline(ms: until, now: testStart)])])
        // A week away has its date (E1 round 4: "until Sun 17:15" read on a Sunday looked like now).
        #expect(TimeText.deadline(ms: until, now: testStart) != TimeText.clock(ms: until))
        let meet = try routes(#"{"address":"a","verified":true,"routes":[],"carriers":{"away":{"meet_first":true}}}"#)
        #expect(Display.awayLines(meet, name: "mac-a", now: testStart) == [tr(.networkRoutesAwayMeetFirst, ["name": "mac-a"])])
        let shared = try routes("""
            {"address":"a","verified":true,"routes":[],"carriers":{"coverage":{"kind":"mutual_friend",
            "name":"a mail friend you share","until":"up to 7 days (letters) or a day (plain)"},"away":{"until_ms":\(until)}}}
            """)
        let lines = Display.awayLines(shared, name: "mac-a", now: testStart)
        #expect(lines.count == 2)
        #expect(lines[1] == tr(.networkRoutesCoverage, ["coverage": "a mail friend you share",
                                                        "until": "up to 7 days (letters) or a day (plain)"]))
        #expect(!lines.joined().contains("for up to 7 days"))
    }

    /// Three-machine test: Routes said "meet first" for a friend Raven had never connected with, where the
    /// terminal app says a first message needs you both online. That friend gets the terminal app's
    /// sentence (`first_message`, next to `meet_first`), and "meet first" is only for an ended connection.
    @Test func routesTellAFirstMessageFromAnEndedConnection() async throws {
        let first = try routes(#"{"address":"a","verified":true,"routes":[],"carriers":{"away":{"meet_first":true,"first_message":true}}}"#)
        let line = Display.awayLines(first, name: "win-c", now: testStart)
        #expect(line == [tr(.networkRoutesAwayFirstMessage, ["name": "win-c"])])
        #expect(line == ["A first message needs you and win-c both online (Raven hasn't connected with win-c yet)."])
        let ended = try routes(#"{"address":"a","verified":true,"routes":[],"carriers":{"away":{"meet_first":true}}}"#)
        #expect(Display.awayLines(ended, name: "win-c", now: testStart)
                == ["To write to win-c, meet first: Raven can't hold new messages for them now."])
        // The demo's friend who isn't verified was never connected with: the first-message rule.
        let (model, _) = await readyModel()
        let rena = MockRaven.renaAddress
        await model.network.loadRoutes(rena)
        let routes = try #require(model.network.routes[rena])
        #expect(routes.carriers?.away == AwayWait(untilMs: nil, meetFirst: true, firstMessage: true))
        #expect(Display.awayLines(routes, name: "Rena", now: testStart).first
                == tr(.networkRoutesAwayFirstMessage, ["name": "Rena"]))
    }

    /// 5. Routes names the address in use and says plainly when the saved one is old.
    @Test func routesShowTheAddressInUse() throws {
        let seen = testStart.addingTimeInterval(-300).ms
        let stale = try routes("""
            {"address":"a","verified":true,"routes":[{"kind":"lan","label":"Same network","value":"192.168.1.146:17420","state":"on"}],
            "lan_now":{"addr":"192.168.0.24:17420","at_ms":\(seen),"saved_stale":true}}
            """)
        let lines = try #require(Display.lanNow(stale, name: "win-c", now: testStart))
        #expect(lines.reached == tr(.networkRoutesLanNow, ["name": "win-c", "addr": "192.168.0.24:17420",
                                                          "when": TimeText.ago(since: 300)]))
        #expect(lines.stale == tr(.networkRoutesLanStale, ["addr": "192.168.1.146:17420", "name": "win-c"]))
        let same = try routes("""
            {"address":"a","verified":true,"routes":[{"kind":"lan","label":"Same network","value":"192.168.0.24:17420","state":"on"}],
            "lan_now":{"addr":"192.168.0.24:17420","at_ms":\(seen),"saved_stale":false}}
            """)
        #expect(Display.lanNow(same, name: "win-c", now: testStart)?.stale == nil)
        #expect(Display.lanNow(try routes(#"{"address":"a","verified":true,"routes":[]}"#), name: "win-c", now: testStart) == nil)
    }

    /// 5. "Use the new address" saves it (contacts.set_address) and reads the routes again.
    @Test func theNewAddressCanBeSaved() async throws {
        let (model, _) = await readyModel()
        let ali = MockRaven.aliAddress
        #expect(await model.network.useLanNow(ali, "192.168.0.24:17420"))
        let saved = try #require(model.network.routes[ali])
        #expect(saved.routes.first { $0.kind == "lan" }?.value == "192.168.0.24:17420")
        #expect(model.contact(ali)?.lan == "192.168.0.24:17420")
        #expect(saved.carriers?.away?.untilMs != nil)
    }

    /// 4. The chat follows its newest message while you are at the bottom, also when it grows after it
    /// came in; scrolling up stops that, and a message you send brings it back.
    @Test func theChatFollowsYourSends() {
        var follow = ChatFollow()
        var steps: [Bool] = []
        // First layout: to the end.
        steps.append(follow.layout(bottom: 400, content: 400, viewport: 300))
        // Scrolled to the end, then a new bubble and a taller one: still following.
        steps.append(follow.layout(bottom: 300, content: 400, viewport: 300))
        let atEnd = follow.on
        steps.append(follow.newMessage(own: false))
        steps.append(follow.layout(bottom: 360, content: 460, viewport: 300))
        #expect(steps == [true, false, true, true])
        #expect(atEnd)
        // You scroll up: no more following, not even for the friend's message.
        steps = [follow.layout(bottom: 340, content: 460, viewport: 300)]
        let scrolledUp = follow.on
        steps.append(follow.newMessage(own: false))
        steps.append(follow.layout(bottom: 400, content: 520, viewport: 300))
        #expect(steps == [false, false, false])
        #expect(!scrolledUp)
        // A message you send brings it back.
        let own = follow.newMessage(own: true)
        #expect(own)
        #expect(follow.on)
        let sending = Message(id: "pending-7", address: "a", direction: .outgoing, text: "t", atMs: testStart.ms, state: .sending)
        let theirs = Message(id: "x", address: "a", direction: .incoming, text: "t", atMs: testStart.ms, state: .delivered)
        #expect(ChatFollow.newest([theirs, sending])?.own == true)
        #expect(ChatFollow.newest([sending, theirs])?.own == false)
    }

    /// 13. Return sends; Option-Return and Shift-Return make a new line. A line break that arrives
    /// without those keys (an accessibility client setting the text) sends what was there.
    @Test func returnSendsAndShiftOrOptionReturnMakesANewLine() {
        #expect(ComposerInput.isNewLine(keyCode: 36, modifiers: [.option]))
        #expect(ComposerInput.isNewLine(keyCode: 36, modifiers: [.shift]))
        #expect(ComposerInput.isNewLine(keyCode: 76, modifiers: [.shift]))
        #expect(!ComposerInput.isNewLine(keyCode: 36, modifiers: []))
        #expect(!ComposerInput.isNewLine(keyCode: 0, modifiers: [.shift]))
        #expect(ComposerInput.isShiftReturn(keyCode: 36, modifiers: [.shift]))
        #expect(!ComposerInput.isShiftReturn(keyCode: 36, modifiers: [.option]))
        #expect(!ComposerInput.isShiftReturn(keyCode: 36, modifiers: [.shift, .command]))
        #expect(ComposerInput.change(old: "hello", new: "hello\n", newLineKey: false) == .send("hello"))
        #expect(ComposerInput.change(old: "hello", new: "hello\n", newLineKey: true) == .edit)
        #expect(ComposerInput.change(old: "a\nb", new: "a\nb\r", newLineKey: false) == .send("a\nb"))
        #expect(ComposerInput.change(old: "", new: "\n", newLineKey: false) == .edit)
        #expect(ComposerInput.change(old: "hell", new: "hello", newLineKey: false) == .edit)
        #expect(ComposerInput.change(old: "hi", new: "hi\nthere\n", newLineKey: false) == .edit)
        // No event, or another key: not a new-line key press.
        #expect(!ComposerInput.newLineKeyDown(nil))
        let typed = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                     isARepeat: false, keyCode: 36)
        #expect(ComposerInput.newLineKeyDown(typed))
    }

    /// 9. View > the sidebar item follows the sidebar.
    @Test func theSidebarMenuItemFollowsTheSidebar() async {
        let (model, _) = await readyModel()
        #expect(model.sidebarShown)
        #expect(Display.sidebarMenuTitle(shown: model.sidebarShown) == tr(.viewHideSidebar))
        model.toggleSidebar()
        #expect(!model.sidebarShown)
        #expect(Display.sidebarMenuTitle(shown: model.sidebarShown) == tr(.viewShowSidebar))
        model.toggleSidebar()
        #expect(model.sidebarVisibility == .all)
    }

    /// 7. The background program's open alerts are "smaller notices, only counted" while nothing needs
    /// you; "Open alerts" is said nowhere.
    @Test func noAlertsWhenNothingNeedsYou() {
        #expect(Display.openNoticesKey(noticesNeedYou: false) == .securityCounted)
        #expect(Display.openNoticesKey(noticesNeedYou: true) == .securityNodeAlerts)
        #expect(!tr(.securityNodeAlerts, ["n": "1"]).lowercased().contains("alert"))
    }

    /// 8. Subtitles in plain words: no command, no "terminal".
    @Test func subtitlesNameNoCommand() {
        for text in [tr(.securityIntro), tr(.networkCheckIntro)] {
            #expect(!text.contains("raven "))
            #expect(!text.contains("terminal"))
        }
    }

    /// 6. The Network page shows the peer-to-peer addresses friends could use; this computer's own
    /// (loopback, link-local) only under Technical details.
    @Test func localOnlyPeerToPeerAddressesAreTechnical() {
        let all = ["/ip4/127.0.0.1/tcp/17423/p2p/12D3", "/ip4/192.168.0.16/tcp/17423/p2p/12D3",
                   "/ip6/::1/tcp/17423/p2p/12D3", "/ip6/fe80::1%en0/tcp/17423", "/ip4/169.254.3.4/udp/17423/quic-v1",
                   "/ip6/2001:db8::7/tcp/17423", "/dns4/relay.example/tcp/443/wss"]
        #expect(Display.p2pAddressesShown(all) == ["/ip4/192.168.0.16/tcp/17423/p2p/12D3", "/ip6/2001:db8::7/tcp/17423",
                                                    "/dns4/relay.example/tcp/443/wss"])
    }

    /// 14. The header's path chip isn't shown while messages to the friend wait.
    @Test func noPathChipWhileTheFriendIsAway() {
        var c = Contact(address: "a", name: "win-c", shortAddress: "a", verified: true, presence: .inTouch)
        #expect(Display.headerPath(c, lastPath: "LAN direct") == "LAN direct")
        c.presence = .waiting
        #expect(Display.headerPath(c, lastPath: "LAN direct") == nil)
        c.presence = .none
        c.waiting = Waiting(count: 1, untilMs: testStart.ms)
        #expect(Display.headerPath(c, lastPath: "LAN direct") == nil)
        #expect(Display.headerPath(Contact(address: "a", name: "b", shortAddress: "a", verified: true, presence: .none),
                                   lastPath: nil) == nil)
    }

    /// 15. A late delivery says when it came, from the message and from its receipt event.
    @Test func aLateDeliverySaysWhenItCame() async throws {
        let at = testStart.addingTimeInterval(-120).ms
        var m = Message(id: "1", address: "a", direction: .outgoing, text: "t", atMs: testStart.addingTimeInterval(-3600).ms,
                        state: .delivered)
        #expect(Display.tick(m, name: "win-c", now: testStart).text == "✓✓ " + tr(.tickDelivered))
        m.deliveredAtMs = at
        #expect(Display.tick(m, name: "win-c", now: testStart).text
                == "✓✓ " + tr(.tickDeliveredAt, ["time": TimeText.bubble(ms: at, now: testStart)]))
        let decoded = try JSONValue.decoder.decode(Message.self, from: Data(
            #"{"id":"1","address":"a","direction":"out","text":"t","at_ms":1,"state":"delivered","delivered_at_ms":99}"#.utf8))
        #expect(decoded.deliveredAtMs == 99)

        let (model, _) = await readyModel()
        let ali = MockRaven.aliAddress
        let waiting = Message(id: "w1", address: ali, direction: .outgoing, text: "later", atMs: testStart.addingTimeInterval(-3600).ms,
                              state: .waiting)
        await model.apply([RavenEvent(seq: 950, kind: .outgoing, atMs: testStart.ms, message: waiting)])
        await model.apply([RavenEvent(seq: 951, kind: .receipt, atMs: at, id: "w1", path: "LAN direct", pathKind: "lan",
                                      ms: 900, deliveredAtMs: at)])
        let delivered = try #require(model.message("w1"))
        #expect(delivered.state == .delivered)
        #expect(delivered.deliveredAtMs == at)
        #expect(delivered.pathKind == "lan")
    }
}
