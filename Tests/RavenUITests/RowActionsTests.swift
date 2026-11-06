import Foundation
import Testing
@testable import RavenUI

/// A friend row in the sidebar: what it offers besides opening the chat. Its right-click menu had the
/// items, VoiceOver had none of them; both now come from one list.
@MainActor
@Suite struct RowActionsTests {
    func readyModel() async -> AppModel {
        let mock = readyMock(demo: false)
        let model = AppModel(engine: mock, now: { mock.clock.now })
        await model.bootstrap()
        return model
    }

    /// The items of the menu, in its order, with the texts of the string table and the text rules.
    @Test func theRowOffersTheMenuItemsInTheirOrder() async throws {
        let model = await readyModel()
        let mina = try #require(model.contacts.first { $0.address == MockRaven.minaAddress })
        let titles = FriendRowAction.allCases.map { $0.title(mina) }
        #expect(FriendRowAction.allCases == [.rename, .checkWords, .routes])
        #expect(titles == [tr(.contactRename), tr(.homeBannerNotVerifiedAction), tr(.networkRoutesTitle, ["name": "Mina"])])
        #expect(titles == ["Rename…", "Check words", "How Raven reaches Mina"])
        for title in titles {
            #expect(TextRulesTests.plain(title), "\(title)")
        }
    }

    /// Each action opens its sheet for the friend of the row, also when another chat is open, and the
    /// open chat stays.
    @Test func eachActionOpensItsSheetForThatFriend() async {
        let model = await readyModel()
        model.select(MockRaven.aliAddress)
        let mina = MockRaven.minaAddress
        let sheets: [(FriendRowAction, AppModel.Sheet)] = [
            (.rename, .rename(mina)), (.checkWords, .checkWords(mina)), (.routes, .friendRoutes(mina)),
        ]
        for (action, sheet) in sheets {
            model.sheet = nil
            model.perform(action, for: mina)
            #expect(model.sheet == sheet, "\(action)")
            #expect(model.selectedAddress == MockRaven.aliAddress, "\(action)")
        }
    }

    /// The row makes its menu and its VoiceOver actions from the same list and adds no item of its own
    /// to either (a SwiftUI view cannot be asked for its actions without a window).
    @Test func theMenuAndTheVoiceOverActionsAreOneList() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/RavenUI/Views/MainView.swift"),
                                encoding: .utf8)
        let row = try #require(source.components(separatedBy: "struct FriendRow: View").dropFirst().first?
            .components(separatedBy: "public enum FriendRowAction").first)
        #expect(row.contains(".contextMenu { actionButtons }"))
        #expect(row.contains(".accessibilityActions { actionButtons }"))
        #expect(row.components(separatedBy: "FriendRowAction.allCases").count == 2)
        #expect(!row.contains("Button(tr("))
    }
}
