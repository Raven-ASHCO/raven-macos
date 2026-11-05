import Foundation
import Testing
@testable import RavenUI

/// The macOS 27.2 SDK declares `Date.<=` and `Date.>=` as back deployed to macOS 27.2. A Mac whose
/// system says 27.2 but whose Foundation does not have them yet jumps to a missing function: the
/// app, the demo engine's clock and RavenSnapshots ended with signal 11 there. Raven compares dates
/// with `<` and `>` only, so no build reaches for those two functions.
@MainActor
@Suite struct DateOrderTests {
    /// The names the linker asks the system for when code uses `Date.<=` (le) or `Date.>=` (ge),
    /// put together at run time so this file does not carry them itself.
    static let missingOnSomeSystems = ["le", "ge"].map { "$s10Foundation4DateV2" + $0 + "oiySbAC_ACtFZ" }

    /// This test binary carries RavenUI and the tests; neither may use `Date.<=` or `Date.>=`.
    @Test func noCodeUsesTheBackDeployedDateOperators() throws {
        let marker: @convention(c) () -> Void = {}
        var info = Dl_info()
        #expect(dladdr(unsafeBitCast(marker, to: UnsafeRawPointer.self), &info) != 0)
        let path = try #require(info.dli_fname.map { String(cString: $0) })
        let binary = try Data(contentsOf: URL(fileURLWithPath: path))
        for name in Self.missingOnSomeSystems {
            #expect(binary.range(of: Data(name.utf8)) == nil, "\(name) in \(path)")
        }
    }

    /// The demo engine's timeline and the clock tick that drops the bold of a new message, both of
    /// which compare dates, run without the two operators.
    @Test func theTimelineAndTheClockTickRun() async throws {
        let clock = MockClock(fixed: testStart)
        let mock = MockRaven(start: .ready, demo: true, clock: clock, identityDelay: 0)
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        for _ in 0..<3 {
            clock.advance(1)
            model.tick()
            await model.pollNow()
        }
        #expect(!model.freshUntil.isEmpty)
        clock.advance(2)
        model.tick()
        #expect(model.freshUntil.isEmpty)
    }
}
