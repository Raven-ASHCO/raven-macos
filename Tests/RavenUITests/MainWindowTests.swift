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
}
