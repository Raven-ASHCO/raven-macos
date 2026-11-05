import Foundation
@testable import RavenUI

/// desktop/macos (the package root), found from this file's path.
let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// The shared design in the raven-core submodule (core/desktop/design).
let designRoot = packageRoot.appendingPathComponent("core/desktop/design")

/// Whether the raven-core submodule is checked out (`git submodule update --init`). The tests that
/// compare with the shared design need it; in a checkout without it they are skipped and say why.
let coreCheckedOut = FileManager.default.fileExists(atPath: designRoot.appendingPathComponent("strings.en.json").path)

/// A fixed moment for clocks in tests.
let testStart = Date(timeIntervalSince1970: 1_792_497_900)

/// A ready MockRaven on a stopped clock.
func readyMock(demo: Bool = true) -> MockRaven {
    MockRaven(start: .ready, demo: demo, clock: MockClock(fixed: testStart), identityDelay: 0)
}

/// Raw envelope call, as `raven_call` would see it.
func raw(_ mock: MockRaven, _ op: String, _ args: [String: JSONValue] = [:]) throws -> JSONValue {
    try JSONValue.parse(mock.handle(RavenEnvelope.request(op: op, args: args)))
}

/// Polls everything new and returns the events.
func pollAll(_ mock: MockRaven, after seq: inout Int) async throws -> [RavenEvent] {
    let batch = try await mock.poll(after: seq)
    seq = batch.seq
    return batch.events
}
