import Foundation
import Testing
@testable import RavenUI

/// What the three-machine evaluation (E1) found in the Mac app, kept fixed.
@MainActor
@Suite struct E1FixesTests {
    func readyModel(engine: ((MockRaven) -> RavenEngine)? = nil) async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0)
        let model = AppModel(engine: engine?(mock) ?? mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        return (model, mock)
    }

    /// 1. "This profile's port: 7420" under "Listening on port 17420": the profile's port is said only
    /// while raven-node doesn't run (the engine's `port` is the port it really listens on).
    @Test func theProfilePortLineShowsOnlyWhileNothingListens() async throws {
        let (model, mock) = await readyModel()
        var status = try await mock.networkStatus()
        status.port = 17420
        status.node = "running"
        #expect(model.node?.running == true)
        #expect(NetworkModel.profilePortLine(status: status, node: model.node) == nil)
        var stopped = try #require(model.node)
        stopped.running = false
        status.node = "not_running"
        status.port = 7420
        #expect(NetworkModel.profilePortLine(status: status, node: stopped) == 7420)
    }

    /// 3. "Waiting for win-c · until –": no dash without a deadline, and a `state` event's deadline
    /// reaches the bubble.
    @Test func aWaitingBubbleShowsTheRealDeadline() async throws {
        let unknown = Message(id: "1", address: "a", direction: .outgoing, text: "t", atMs: testStart.ms,
                              state: .waiting, untilMs: nil)
        #expect(Display.tick(unknown, name: "win-c", now: testStart).text == "Waiting for win-c")

        let (model, _) = await readyModel()
        model.select(MockRaven.renaAddress)
        model.composerText = "are you there?"
        await model.sendComposer()
        let id = try #require(model.messages[MockRaven.renaAddress]?.last?.id)
        let until = testStart.addingTimeInterval(22 * 3600)
        await model.apply([RavenEvent(seq: 900, kind: .state, atMs: testStart.ms, id: id, state: .waiting,
                                      untilMs: until.ms)])
        let m = try #require(model.message(id))
        #expect(m.untilMs == until.ms)
        #expect(Display.tick(m, name: "Rena", now: testStart).text == "Waiting for Rena · until " + TimeText.clock(until))
        #expect(!Display.tick(m, name: "Rena", now: testStart).text.contains("–"))
    }

    /// 4. Send again added a second bubble beside "Not sent". It retries the same message: an ended one
    /// that comes back with a new id (`replaces`) takes the old one's place.
    @Test func sendAgainKeepsOneBubble() async throws {
        let (model, _) = await readyModel(engine: { ReplacingEngine($0) })
        let rena = MockRaven.renaAddress
        let ended = Message(id: "ended-1", address: rena, direction: .outgoing, text: "first hello",
                            atMs: testStart.ms, state: .notSentMeetFirst)
        model.messages[rena] = (model.messages[rena] ?? []) + [ended]
        await model.retry("ended-1")
        let list = try #require(model.messages[rena])
        #expect(list.filter { $0.text == "first hello" }.count == 1)
        #expect(!list.contains { $0.id == "ended-1" })
        #expect(list.last?.text == "first hello")
        #expect(list.last?.state != .notSentMeetFirst)
        // The mock's own retry keeps the id: still one bubble.
        let (plain, mock) = await readyModel()
        plain.select(rena)
        let sent = try await mock.send(address: rena, text: "again")
        await plain.reloadHistories()
        await plain.retry(sent.id)
        #expect(plain.messages[rena]?.filter { $0.text == "again" }.count == 1)
    }

    /// 6. "No messages with mac-b yet. Say hello!" stayed behind the first bubble: it shows only while
    /// there is no message and none on its way.
    @Test func theEmptyChatTextGoesWithTheFirstMessage() async {
        let one = Message(id: "p-1", address: "a", direction: .outgoing, text: "hi", atMs: 1, state: .sending)
        #expect(AppModel.chatIsEmpty(messages: [], sendsInFlight: 0))
        #expect(!AppModel.chatIsEmpty(messages: [], sendsInFlight: 1))
        #expect(!AppModel.chatIsEmpty(messages: [one], sendsInFlight: 0))
        let (model, _) = await readyModel()
        model.messages[MockRaven.renaAddress] = []
        model.select(MockRaven.renaAddress)
        #expect(model.chatIsEmpty(MockRaven.renaAddress))
        model.composerText = "hello"
        await model.sendComposer()
        #expect(!model.chatIsEmpty(MockRaven.renaAddress))
    }

    /// 7. "Not sent: meet first" told a user nothing.
    @Test func notSentSaysWhoAndWhy() {
        let m = Message(id: "1", address: "a", direction: .outgoing, text: "t", atMs: 1, state: .notSentMeetFirst)
        let text = Display.tick(m, name: "mac-b", now: testStart).text
        #expect(text == "Not sent: mac-b isn't reachable. A first message needs you both online.")
    }

    /// 8. The window never said who you are.
    @Test func youAreShownWithYourFingerprint() async {
        let (model, _) = await readyModel()
        let you = Display.you(model.identity, name: "Sam")
        #expect(you.title.hasPrefix("You"))
        #expect(you.fingerprint == "Fingerprint " + (model.identity?.oldCode ?? "?"))
        #expect(Display.you(nil, name: nil).title == "You")
        #expect(Display.you(Identity(displayName: "Sam", address: "a", words: [], oldCode: "KLHQ-uLWW-5iB0"), name: nil)
                == ("You · Sam", "Fingerprint KLHQ-uLWW-5iB0"))
    }

    /// 9. "node ok · now" didn't say whose node.
    @Test func theHeartbeatSaysYourNode() async {
        let (model, _) = await readyModel()
        #expect(Display.heartbeat(node: model.node, lastOk: model.lastStatusOk, now: model.now).text.hasPrefix("your node: ok"))
    }

    /// 11. Details showed "id=pending-4" and raven-node's words: plain lines, the rest under Technical details.
    @Test func detailsArePlainWithTechnicalApart() async throws {
        let (model, mock) = await readyModel()
        let delivered = try #require(model.messages[MockRaven.aliAddress]?.first { $0.direction == .outgoing && $0.state == .delivered })
        let d = try await mock.details(id: delivered.id)
        #expect(d.detail.hasPrefix("Message ID: "))
        #expect(!d.detail.contains("state="))
        #expect(d.technical?.contains("state=delivered") == true)
    }

    /// 13. No time on bubbles.
    @Test func bubblesHaveAShortTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_793_000_000)   // a Monday afternoon (UTC)
        let earlier = now.addingTimeInterval(-3600)
        let c = calendar.dateComponents([.hour, .minute], from: earlier)
        #expect(TimeText.bubble(ms: earlier.ms, now: now, calendar: calendar)
                == String(format: "%02d:%02d (UTC)", c.hour!, c.minute!))
        let lastWeek = now.addingTimeInterval(-3 * 86_400)
        #expect(TimeText.bubble(ms: lastWeek.ms, now: now, calendar: calendar) == TimeText.clock(lastWeek, calendar: calendar))
    }
}

/// The real engine's Send again of an ended message: the text goes again as a new message, and
/// `replaces` names the old one (API.md, `messages.retry`). Everything else is the mock's.
final class ReplacingEngine: RavenEngine, @unchecked Sendable {
    let mock: MockRaven
    init(_ mock: MockRaven) { self.mock = mock }

    func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        guard op == "messages.retry", case .string(let id)? = args["id"], id == "ended-1" else {
            return try await mock.call(op: op, args: args)
        }
        let sent = try await mock.call(op: "messages.send", args: ["address": .string(MockRaven.renaAddress),
                                                                  "text": .string("first hello")])
        guard case .object(var result) = sent else { return sent }
        result["changed"] = .bool(true)
        result["replaces"] = .string(id)
        return .object(result)
    }
}
