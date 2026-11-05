import AppKit
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

    /// A still draws a scrolling page as the window shows it: the page at its own height, cut at the
    /// window's edge. It squeezed the page into the window instead, so texts lost lines a scroll view
    /// keeps (the Security page in the smallest window ended a line with "the la…").
    @Test func aStillCutsAScrollingPageInsteadOfSqueezingIt() throws {
        let words = String(repeating: "Words that wrap over many lines. ", count: 12)
        for bottomAligned in [false, true] {
            let placed = PlacedHeight()
            let renderer = ImageRenderer(content: RScroll(bottomAligned: bottomAligned) {
                HeightProbe(placed: placed) { Text(words) }
            }
            .frame(width: 200, height: 60)
            .environment(\.ravenSnapshot, true))
            renderer.scale = 1
            _ = try #require(renderer.cgImage)
            #expect(placed.height > 120, "bottom aligned \(bottomAligned): the text got \(placed.height) points")
        }
    }

    // MARK: Colours, contrast and focus

    /// The WCAG contrast of two opaque colours (1 to 21).
    static func contrast(_ a: Color, _ b: Color) -> Double {
        func luminance(_ c: Color) -> Double {
            let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
            func f(_ v: CGFloat) -> Double { Double(v) <= 0.04045 ? Double(v) / 12.92 : pow((Double(v) + 0.055) / 1.055, 2.4) }
            return 0.2126 * f(n.redComponent) + 0.7152 * f(n.greenComponent) + 0.0722 * f(n.blueComponent)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func hex(_ c: Color) -> String {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((n.redComponent * 255).rounded()),
                      Int((n.greenComponent * 255).rounded()), Int((n.blueComponent * 255).rounded()))
    }

    /// Text reaches 4.5 to 1 where it sits, light and dark. The tertiary text (section labels, times,
    /// the sidebar's last line) was 3.06 to 1 in light and 3.37 in dark; it has the iPhone app's colours.
    @Test func textReachesFourAndAHalfToOne() {
        for scheme in [ColorScheme.light, .dark] {
            let p = Theme.shared.palette(scheme)
            for (name, text) in [("textPrimary", p.textPrimary), ("textSecondary", p.textSecondary), ("textTertiary", p.textTertiary)] {
                for (ground, colour) in [("background", p.background), ("surface", p.surface), ("sidebar", p.sidebar)] {
                    #expect(Self.contrast(text, colour) >= 4.5, "\(name) on \(ground) in \(scheme)")
                }
            }
        }
        #expect(Self.hex(Theme.shared.palette(.light).textTertiary) == "#6E6D67")
        #expect(Self.hex(Theme.shared.palette(.dark).textTertiary) == "#908F89")
    }

    /// tokens.macos.json only raises colours tokens.json names; it adds none.
    @Test func theMacTokensOnlyRaiseSharedColours() throws {
        let resources = packageRoot.appendingPathComponent("Sources/RavenUI/Resources")
        func json(_ file: String) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent(file))) as? [String: Any])
        }
        let mac = try json("tokens.macos.json")
        let colours = try #require(try json("tokens.json")["color"] as? [String: Any])
        #expect(Set(mac.keys).isSubset(of: ["name", "note", "colorContrast"]))
        let raised = try #require(mac["colorContrast"] as? [String: Any])
        for (name, value) in raised where name != "note" {
            #expect(colours[name] != nil && Palette.names.contains(name), "\(name) is not a colour of tokens.json")
            let pair = try #require(value as? [String: String], "\(name)")
            #expect(pair["light"] != nil && pair["dark"] != nil, "\(name)")
        }
    }

    /// A button's word reaches 4.5 to 1 on its fill. Erase said its word in the fill red, 3.0 to 1 on
    /// a dark card; under the pointer a primary button now darkens, so its white word gains contrast.
    @Test func buttonWordsReachFourAndAHalfToOne() {
        for scheme in [ColorScheme.light, .dark] {
            let p = Theme.shared.palette(scheme)
            for kind in [RButtonStyle.Kind.secondary, .danger] {
                let word = RButtonStyle.textColor(kind, p)
                #expect(Self.contrast(word, RButtonStyle.fill(kind, hover: false, p)) >= 4.5, "\(kind) in \(scheme)")
            }
            for ground in [p.background, p.surface] {
                #expect(Self.contrast(RButtonStyle.textColor(.plain, p), ground) >= 4.5, "plain in \(scheme)")
            }
            #expect(Self.contrast(p.onAccent, RButtonStyle.fill(.primary, hover: true, p))
                    > Self.contrast(p.onAccent, RButtonStyle.fill(.primary, hover: false, p)))
        }
    }

    /// A field with the keyboard focus shows it in the focus colour, which stands out from what it
    /// rings (3 to 1 for a focus sign); the composer draws its own frame.
    @Test func aFocusedFieldShowsTheFocusColour() {
        for scheme in [ColorScheme.light, .dark] {
            let p = Theme.shared.palette(scheme)
            #expect(RField.border(focused: true, bare: false, p) == p.focus)
            #expect(RField.border(focused: false, bare: false, p) == p.borderStrong)
            #expect(RField.border(focused: true, bare: true, p) == .clear)
            for ground in [p.background, p.surface] { #expect(Self.contrast(p.focus, ground) >= 3) }
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

/// The height a `HeightProbe` last placed its view at.
final class PlacedHeight { var height: CGFloat = 0 }

/// Lays out its one view as offered and notes the height it places it at.
struct HeightProbe: Layout {
    let placed: PlacedHeight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        placed.height = bounds.height
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
