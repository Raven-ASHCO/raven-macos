import Foundation
import Testing
@testable import RavenUI

/// The text rules across the areas of the Mac app (each area checks its own screens too): visible
/// texts in plain English with no apostrophes, hyphens or dashes, and "No Raven server", never a plain
/// "no server".
@MainActor
@Suite struct TextRulesTests {
    static func plain(_ text: String) -> Bool {
        text.range(of: #"['‘’‐‑‒–—―−-]"#, options: .regularExpression) == nil
            && text.range(of: "no server", options: .caseInsensitive) == nil
    }

    /// The first screen said "No server." under the mark and "your friends' computers ... no server"
    /// and "Wi-Fi" in its body, while About said "No Raven server".
    @Test func welcomeSaysNoRavenServer() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/RavenUI/Views/WelcomeView.swift"),
                                encoding: .utf8)
        let welcome = try #require(source.components(separatedBy: "public struct SetupView").first)
        for shared in [".appTagline", ".welcomeBody1", ".welcomeBody2"] {
            #expect(!welcome.contains("tr(" + shared + ")"), "\(shared)")
        }
        for text in [tr(.macAppTagline), tr(.macWelcomeBody1), tr(.macWelcomeBody2)] {
            #expect(Self.plain(text), "\(text)")
        }
        #expect(tr(.macAppTagline).hasSuffix("No Raven server."))
        #expect(tr(.macWelcomeBody1).contains("no Raven server"))
    }
}
