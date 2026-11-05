import Foundation
import Testing
@testable import RavenUI

/// An engine that fails the named operations once each, then answers as the mock does.
final class FailingOnce: RavenEngine, @unchecked Sendable {
    let inner: MockRaven
    private var failing: Set<String>

    init(_ inner: MockRaven, failing: Set<String>) {
        self.inner = inner
        self.failing = failing
    }

    func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        if failing.remove(op) != nil {
            throw RavenError(code: ErrorCode.internalError, message: tr(.errorInternal), detail: "\(op) failed once")
        }
        return try await inner.call(op: op, args: args)
    }
}

/// Welcome and setup, your identity, adding and checking friends, the friends list.
@MainActor
@Suite struct SetupFriendsTests {
    func readyModel() async -> (AppModel, MockRaven) {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        return (model, mock)
    }

    // MARK: Setup

    /// The background program failed to start after the identity was made: Try again on the same
    /// step went on to make a second identity, which the engine refuses, so setup could never finish.
    @Test func setupTriesAgainWithoutASecondIdentity() async {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .new, demo: false, clock: clock, identityDelay: 0)
        let model = AppModel(engine: FailingOnce(mock, failing: ["node.start"]), now: { clock.now })
        await model.bootstrap()
        model.beginSetup()
        model.submitName()
        await model.chooseReceive(true)
        #expect(model.setupStep == .receive)
        #expect(model.actionError != nil)
        await model.chooseReceive(true)
        #expect(model.setupStep == .words)
        #expect(model.actionError == nil, "the error of the first try is gone")
        #expect(model.identity?.words.count == 10)
        #expect(model.node?.running == true)
    }
}
