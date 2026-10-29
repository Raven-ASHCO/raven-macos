import Foundation
import Testing
@testable import RavenUI

/// What the app does with raven-client's extra fields (API.md), and which engine a build picks.
/// These run with or without the engine linked.
@MainActor
@Suite struct EngineExtrasTests {
    /// MockRaven, except that its next `events.poll` answers `reset: true` with an event that must
    /// not be applied (it stands for "events were lost").
    final class ResettingEngine: RavenEngine, @unchecked Sendable {
        let inner: MockRaven
        private let lock = NSLock()
        private var resetNext = false

        init(_ inner: MockRaven) { self.inner = inner }

        func resetOnNextPoll() { lock.withLock { resetNext = true } }

        private func takeReset() -> Bool {
            lock.withLock { () -> Bool in
                let take = resetNext
                resetNext = false
                return take
            }
        }

        func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
            guard op == "events.poll", takeReset() else { return try await inner.call(op: op, args: args) }
            let lost: JSONValue = [
                "seq": 3, "kind": "incoming", "at_ms": .int(testStart.ms),
                "message": ["id": "lost-1", "address": .string(MockRaven.aliAddress), "direction": "in",
                            "text": "should not be applied", "at_ms": .int(testStart.ms), "state": "delivered"],
            ]
            return ["seq": 3, "reset": true, "events": [lost]]
        }
    }

    @Test func resetReloadsInsteadOfApplyingEvents() async throws {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: false, clock: clock, identityDelay: 0)
        let engine = ResettingEngine(mock)
        let model = AppModel(engine: engine, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        let aliMessages = model.messages[MockRaven.aliAddress]?.count
        // Changed behind the model's back: only a reload shows it.
        _ = try await mock.renameContact(address: MockRaven.aliAddress, name: "Ali B")
        #expect(model.contact(MockRaven.aliAddress)?.name == "Ali")
        model.routeQueue = []
        model.toast = nil

        model.lastSeq = 10                                                  // as if the engine restarted
        engine.resetOnNextPoll()
        await model.pollNow()
        #expect(model.lastSeq == 3)                                         // the engine's seq, even if lower
        #expect(model.contact(MockRaven.aliAddress)?.name == "Ali B")       // reloaded
        #expect(model.message("lost-1") == nil)                             // the batch was not applied
        #expect(model.messages[MockRaven.aliAddress]?.count == aliMessages)
        #expect(model.routeQueue.isEmpty && model.toast == nil)             // no motion for what was missed
        #expect(model.phase == .ready)
    }

    @Test func nodeStateFromTheEngineDecidesStarting() {
        let carriers = Carriers(lan: "on", internet: "preview", p2p: "preview", custody: "preview")
        var node = NodeStatus(running: true, startedByApp: true, receive: true, lastOkMs: 0, build: "release", carriers: carriers)
        #expect(node.starting)                          // no `state` (mock, older engine): guessed
        node.state = "send_only"
        #expect(!node.starting)                         // running without a listener is not "starting"
        #expect(Display.listening(node).busy == false)
        node.state = "starting"
        #expect(node.starting)
        #expect(Display.listening(node).text == tr(.netStarting))
        let decoded = try? JSONValue.parse(#"""
            {"running": true, "started_by_app": false, "receive": true, "last_ok_ms": 1, "build": "release",
             "carriers": {"lan": "on", "internet": "preview", "p2p": "preview", "custody": "preview"},
             "state": "local_only", "lab": [], "stop": "managed", "note": "left running"}
            """#).decode(NodeStatus.self)
        #expect(decoded?.state == "local_only" && decoded?.stop == "managed" && decoded?.note == "left running")
    }

    @Test func aStopThatLeavesTheNodeRunningIsExplained() {
        let model = AppModel(engine: readyMock(demo: false))
        let carriers = Carriers(lan: "on", internet: "preview", p2p: "preview", custody: "preview")
        var status = NodeStatus(running: true, startedByApp: false, receive: true, lastOkMs: 0, build: "release", carriers: carriers)
        status.stop = "managed"
        status.note = "Raven's background program runs as a login service."
        model.noteStop(status)
        #expect(model.toast?.text == "Raven's background program runs as a login service." && model.toast?.tone == .warning)
        model.toast = nil
        status.stop = "stopped"
        status.note = nil
        model.noteStop(status)
        #expect(model.toast == nil && model.actionError == nil)
        status.stop = "failed"
        status.note = "Operation not permitted (os error 1)"
        model.noteStop(status)
        #expect(model.actionError?.code == ErrorCode.internalError)
        #expect(model.actionError?.detail == "Operation not permitted (os error 1)")
    }

    @Test func profileDetailReachesTheFailureScreen() throws {
        let state = try JSONValue.parse(#"{"state": "unreadable", "reason": "Raven can't read its files.", "detail": "io: denied"}"#)
            .decode(ProfileState.self)
        #expect(state.state == .unreadable && state.detail == "io: denied")
    }

    /// MockRaven only on an explicit demo switch; otherwise the engine (or MissingEngine).
    @Test func theMockIsChosenOnlyByTheDemoSwitch() {
        #expect(EngineFactory.makeDefault(environment: ["RAVEN_DEMO": "1"]) is MockRaven)
        #expect(EngineFactory.makeDefault(environment: ["RAVEN_DEMO": "1", "RAVEN_MOCK_STATE": "ready"]) is MockRaven)
        for env in [[:], ["RAVEN_DEMO": "0"], ["RAVEN_ENGINE": "client"], ["RAVEN_MOCK_STATE": "ready"]] {
            let engine = EngineFactory.makeDefault(environment: env)   // making one calls nothing
            #expect(!(engine is MockRaven))
            #if RAVEN_ENGINE
            #expect(engine is RavenClientEngine)
            #else
            #expect(engine is MissingEngine)
            #endif
        }
    }
}
