import Foundation
import SwiftUI
import Testing
@testable import RavenUI

/// Look and access: window sizes, colours and contrast, keyboard focus and VoiceOver.
@MainActor
@Suite struct LookAccessTests {
    // MARK: Window sizes

    /// In the smallest window Settings had 111 points beside its section list and drew nothing; the
    /// list now shows its squares alone there, and keeps its names where the section has room.
    @Test func theSettingsListNarrowsInASmallWindow() {
        let smallest = Display.detailMinWidth
        #expect(SettingsView.compactNav(width: smallest))
        #expect(SettingsView.sectionWidth(smallest) >= 220)
        #expect(!SettingsView.compactNav(width: 760))
        #expect(SettingsView.sectionWidth(760) >= 300)
        // Wide: at most the token width.
        #expect(SettingsView.sectionWidth(1600) == Theme.shared.layout.settingsMaxWidth)
    }

    /// A row's control goes under its words only when the words would get too narrow beside it.
    @Test func aRowControlGoesUnderTheWordsOnlyWhenNarrow() {
        // The name field (220 points) beside its words in a wide window, under them in a narrow one.
        #expect(BesideOrUnder.beside(width: 640, control: 220))
        #expect(!BesideOrUnder.beside(width: 300, control: 220))
        // A switch stays beside its words even in the smallest window.
        #expect(BesideOrUnder.beside(width: 209, control: 36))
        // No control: nothing to move.
        #expect(BesideOrUnder.beside(width: 40, control: 0))
    }

    /// Every Settings section fits the width the smallest window leaves it: nothing runs past the
    /// cards (a segmented control turns into radio rows, a field narrows, a button goes under).
    @Test func everySettingsSectionFitsTheSmallestWindow() async throws {
        let width = SettingsView.sectionWidth(Display.detailMinWidth)
        for section in AppModel.SettingsSection.allCases {
            let model = await SnapshotCatalog.settingsModel(section)
            let drawn = try drawnWidth(SettingsSectionBody(section: section), model, offered: width)
            #expect(drawn <= width.rounded(.up), "\(section) is \(drawn) points wide in \(width)")
        }
    }

    /// The Network page's cards fit the page the smallest window leaves: they ran past both edges
    /// ("Preview, not in this release" kept one line) and Check network was cut to "Check…".
    @Test func theNetworkCardsFitTheSmallestWindow() async throws {
        let page = Display.detailMinWidth
        #expect(PageLayout.margin(width: page) == 20 && PageLayout.margin(width: 760) == 32)
        let width = page - 2 * PageLayout.margin(width: page)
        for mode in [MockRaven.NetworkMode.release, .lab] {
            let model = await SnapshotCatalog.pageModel(.network, network: mode)
            let status = try #require(model.network.status)
            var cards: [(name: String, view: AnyView)] = [("This computer", AnyView(ThisComputerSection(status: status)))]
            for way in status.carriers {
                cards.append((way.id, AnyView(WayRow(way: way, status: status, net: model.network, card: true))))
            }
            for card in cards {
                let drawn = try drawnWidth(card.view, model, offered: width)
                #expect(drawn <= width.rounded(.up), "\(card.name) is \(drawn) points wide in \(width)")
            }
        }
    }

    /// How wide `view` draws itself when offered `width` points (wider when a part of it cannot
    /// narrow that far).
    func drawnWidth(_ view: some View, _ model: AppModel, offered width: CGFloat) throws -> CGFloat {
        let renderer = ImageRenderer(content: view
            .environmentObject(model)
            .environmentObject(model.clock)
            .ravenTheme(reducedMotion: true)
            .environment(\.ravenSnapshot, true))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return CGFloat(try #require(renderer.cgImage).width)
    }
}
