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
            let content = SettingsSectionBody(section: section)
                .environmentObject(model)
                .environmentObject(model.clock)
                .ravenTheme(reducedMotion: true)
                .environment(\.ravenSnapshot, true)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            let image = try #require(renderer.cgImage, "no picture of \(section)")
            #expect(CGFloat(image.width) <= width.rounded(.up), "\(section) is \(image.width) points wide in \(width)")
        }
    }
}
