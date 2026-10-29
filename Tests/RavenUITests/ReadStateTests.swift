import Foundation
import Testing
@testable import RavenUI

/// E1 round two: read and unread come from the engine, which shares one read marker per friend with
/// the terminal app. A chat read in either app is read in both, and the counts survive a restart.
@MainActor
@Suite struct ReadStateTests {
    func readyModel(_ mock: MockRaven? = nil) async -> (AppModel, MockRaven) {
        let mock = mock ?? readyMock()
        let clock = mock.clock
        let model = AppModel(engine: mock, now: { clock.now })
        await model.bootstrap()
        await model.pollNow()
        return (model, mock)
    }

    func advance(_ model: AppModel, _ mock: MockRaven, seconds: Int) async {
        for _ in 0..<seconds {
            mock.clock.advance(1)
            model.tick()
            await model.pollNow()
        }
    }

    /// The engine's count for `address` (what a restarted app, or the terminal app, sees).
    func engineUnread(_ mock: MockRaven, _ address: String) async throws -> Int {
        try await mock.contacts().first { $0.address == address }?.unread ?? -1
    }

    /// Waits for the background `messages.mark_read` the model started.
    func settled(_ mock: MockRaven, _ address: String, is want: Int) async throws -> Bool {
        for _ in 0..<100 {
            if try await engineUnread(mock, address) == want { return true }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @Test func countsComeFromTheEngineAndSurviveARestart() async throws {
        let (model, mock) = await readyModel()
        #expect(model.unread.values.allSatisfy { $0 == 0 })
        await advance(model, mock, seconds: 3)        // Rena writes at 2.6 s while Ali is open
        #expect(model.unread[MockRaven.renaAddress] == 1)
        #expect(try await engineUnread(mock, MockRaven.renaAddress) == 1)
        // A new window on the same engine (the app opened again) shows the same count.
        let (again, _) = await readyModel(mock)
        #expect(again.unread[MockRaven.renaAddress] == 1)
    }

    @Test func openingAChatMarksItReadInTheEngine() async throws {
        let (model, mock) = await readyModel()
        await advance(model, mock, seconds: 3)
        model.select(MockRaven.renaAddress)
        #expect(model.unread[MockRaven.renaAddress] == 0)
        #expect(try await settled(mock, MockRaven.renaAddress, is: 0))
        let (again, _) = await readyModel(mock)
        #expect(again.unread[MockRaven.renaAddress] == 0)
    }

    @Test func aChatReadInTheTerminalAppIsReadHere() async throws {
        let (model, mock) = await readyModel()
        await advance(model, mock, seconds: 3)
        #expect(model.unread[MockRaven.renaAddress] == 1)
        // The terminal app read Rena's chat: the engine's marker moved, and its event says so.
        _ = try await mock.markRead(address: MockRaven.renaAddress)
        await model.pollNow()
        #expect(model.unread[MockRaven.renaAddress] == 0)
        #expect(model.contact(MockRaven.renaAddress) != nil)
    }

    @Test func theOpenChatIsReadOnlyWhileTheWindowShowsIt() async throws {
        let (model, mock) = await readyModel()
        model.windowVisible = false                    // the menu bar only
        await advance(model, mock, seconds: 2)        // Ali writes at 1.2 s; his chat is selected
        #expect(model.unread[MockRaven.aliAddress] == 1)
        #expect(try await engineUnread(mock, MockRaven.aliAddress) == 1)
        model.windowVisible = true                     // the window opens on his chat
        #expect(model.unread[MockRaven.aliAddress] == 0)
        #expect(try await settled(mock, MockRaven.aliAddress, is: 0))
    }

    @Test func markingReadNeverMovesBackAndYoursAreNeverUnread() async throws {
        let mock = readyMock()
        _ = try await mock.send(address: MockRaven.renaAddress, text: "hi")
        #expect(try await engineUnread(mock, MockRaven.renaAddress) == 0)
        let unread = try raw(mock, "messages.mark_read", ["address": .string(MockRaven.aliAddress), "id": "m1"])
        #expect(unread["result"]?["unread"]?.int == 0)  // m2 (read before the demo) stays the marker
        #expect(try await engineUnread(mock, MockRaven.aliAddress) == 0)
        let missing = try raw(mock, "messages.mark_read", ["address": .string(MockRaven.aliAddress), "id": "nope"])
        #expect(missing["error"]?["code"]?.string == ErrorCode.badRequest)
    }

    @Test func unreadEventsAndContactsDecode() throws {
        let event = try JSONValue.parse(#"{"seq":3,"kind":"unread","at_ms":5,"address":"rvn1x","unread":2}"#)
            .decode(RavenEvent.self)
        #expect(event.kind == .unread && event.address == "rvn1x" && event.unread == 2)
        let older = try JSONValue.parse(#"{"address":"a","name":"n","short_address":"s","verified":true,"presence":"none"}"#)
            .decode(Contact.self)
        #expect(older.unread == nil)
    }
}
