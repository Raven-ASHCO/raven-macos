import Foundation
import Testing
import SwiftUI
@testable import RavenUI

@Suite struct WordInputTests {
    @Test func splitsOnSeparators() {
        #expect(WordInput.tokens("turtle frog, bread;wolf-paper/laptop|funnel·mango•honey wagon")
            == ["turtle", "frog", "bread", "wolf", "paper", "laptop", "funnel", "mango", "honey", "wagon"])
    }

    @Test func dropsPositionNumbersInAnyDigits() {
        #expect(WordInput.tokens("1. turtle 2. frog") == ["turtle", "frog"])
        #expect(WordInput.tokens("\u{06F1}. turtle \u{06F2}. frog") == ["turtle", "frog"])      // Persian digits
        #expect(WordInput.tokens("\u{0661}- turtle \u{0662}- frog") == ["turtle", "frog"])      // Arabic-Indic digits
        #expect(WordInput.tokens("\u{FF11} turtle") == ["turtle"])                       // full-width digit
    }

    @Test func dropsZeroWidthInsideTokens() {
        #expect(WordInput.tokens("tur\u{200B}tle") == ["turtle"])
    }

    @Test func foldsLatin() {
        #expect(WordInput.foldLatin("TuRtLe") == "turtle")
        #expect(WordInput.foldLatin("\u{FF54}\u{FF55}\u{FF52}\u{FF54}\u{FF4C}\u{FF45}") == "turtle")   // full-width letters
        #expect(WordInput.foldLatin("\u{0627}\u{0628}") == nil)   // Arabic-script letters (another keyboard layout)
    }

    /// Your own old code is shown in groups of 4 (security-words design: "If4x 36FU omFi").
    @Test func groupsTheOldCodeForReadingAloud() {
        #expect(WordInput.oldCodeGroups("If4x-36FU-omFi") == "If4x 36FU omFi")
        #expect(WordInput.oldCodeGroups("If4x36FUomFi") == "If4x 36FU omFi")
        #expect(WordInput.oldCodeGroups(" If4x - 36FU\u{200B}omFi ") == "If4x 36FU omFi")
        #expect(WordInput.oldCodeGroups("Tq7m-29Xa-hKe") == "Tq7m 29Xa hKe")
        #expect(WordInput.oldCodeGroups("") == "")
        // What is shown is what a friend may type: the key (case kept) is the same.
        #expect(WordInput.oldCodeKey(WordInput.oldCodeGroups("If4x-36FU-omFi")) == "If4x36FUomFi")
    }

    @Test func oldCodeModeHasItsOwnIntro() async {
        let words = await CheckWordsIntro.text(mode: .words, name: "Rena")
        let code = await CheckWordsIntro.text(mode: .oldCode, name: "Rena")
        #expect(words.contains("words") && !words.contains("old code"))
        #expect(code.contains("old code") && !code.contains("your own words") && code.contains("Rena"))
    }

    @Test func knowsWhenATokenIsFinished() {
        #expect(WordInput.endsWithSeparator("turtle "))
        #expect(!WordInput.endsWithSeparator("turtle"))
        #expect(WordInput.endsWithSeparator("turtle\r\n"))
    }
}

@Suite struct ThemeTests {
    @Test func tokensLoad() {
        let t = Theme.shared
        #expect(t.motion.routePacket == 0.7)
        #expect(t.motion.receiptBack == 0.6)
        #expect(t.motion.readAloudStep == 0.8)
        #expect(t.layout.sidebarWidth == 272)
        #expect(t.layout.settingsNavWidth == 228)
        #expect(t.radius.bubble == 18)
        #expect(t.radius.bubbleTail == 6)
    }

    /// The Calm motion tokens: durations, curves (CSS cubic-bezier) and springs.
    @Test func calmMotionTokens() {
        let t = Theme.shared
        #expect(t.motion.bubbleLift == 0.52)
        #expect(t.motion.settingsGlide == 0.45)
        #expect(t.motion.segmentThumb == 0.42)
        #expect(t.motion.switchKnob == 0.3)
        #expect(t.curves["lift"] == Theme.Curve(x1: 0.2, y1: 0.9, x2: 0.25, y2: 1.12))
        #expect(t.curves["glide"] == Theme.Curve(x1: 0.3, y1: 1.25, x2: 0.5, y2: 1.0))
        #expect(t.springs["knob"] == Theme.Spring(response: 0.3, damping: 0.62))
        #expect(t.type.bubble.size == 14.5)
        #expect(t.type.pageTitle.size == 24)
        #expect(abs(t.type.sectionLabel.tracking - 0.44) < 1e-9)   // 0.04 em of 11 pt
    }

    /// Every palette colour exists in light and dark, including the path and Settings section colours.
    @Test func calmPalette() {
        for scheme in [ColorScheme.light, .dark] {
            let p = Theme.shared.palette(scheme)
            for name in Palette.names { #expect(p.colors[name] != nil, "\(name)") }
            #expect(!p.cardShadow.isEmpty && !p.bubbleShadow.isEmpty && !p.sheetShadow.isEmpty)
        }
        #expect(Palette.names.count == 38)
    }

    @Test func hexColours() throws {
        let (r, g, b, a) = try Theme.rgba(hex: "#1F1E1C4D")
        #expect(abs(r - 31.0 / 255) < 1e-9 && abs(g - 30.0 / 255) < 1e-9 && abs(b - 28.0 / 255) < 1e-9)
        #expect(abs(a - 77.0 / 255) < 1e-9)
        #expect(throws: RavenError.self) { try Theme.rgba(hex: "#12") }
    }

    /// tokens avatarRule: (sum of the address bytes) mod 5. The demo friends get violet, aqua, orange.
    @Test func avatarRule() {
        #expect(Theme.avatarIndex(for: MockRaven.aliAddress) == 0)
        #expect(Theme.avatarIndex(for: MockRaven.minaAddress) == 1)
        #expect(Theme.avatarIndex(for: MockRaven.renaAddress) == 2)
        #expect(Theme.avatarIndex(for: "abc") == (97 + 98 + 99) % 5)
    }
}
