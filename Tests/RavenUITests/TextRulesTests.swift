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

extension TextRulesTests {
    /// Setup's receive step said "listens on your network (port 7420)", while Settings > General says
    /// the same without the port (owner rule: ports and addresses only under Technical details).
    @Test func setupNamesNoPortAsSettingsDoes() throws {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/RavenUI/Views/WelcomeView.swift"),
                                encoding: .utf8)
        #expect(!source.contains("tr(.setupReceiveBody)"))
        #expect(source.contains("tr(.macSettingsReceiveBody)"))
        let text = tr(.macSettingsReceiveBody)
        #expect(text.range(of: #"\d"#, options: .regularExpression) == nil, "\(text)")
        #expect(!text.lowercased().contains("port"), "\(text)")
        #expect(Self.plain(text), "\(text)")
    }
}

extension TextRulesTests {
    /// Every text of the Mac app's own table, whichever area shows it. Removing a group member said
    /// "this group's messages and can't write to it", and a lock text no screen showed any more said
    /// "doesn't".
    @Test func everyMacTextIsPlain() {
        let keys = Str.allCases.filter { $0.rawValue.hasPrefix("mac.") }
        #expect(keys.count > 100)
        let args = ["name": "Mina", "group": "Book club", "n": "2", "query": "Sam", "when": "now", "secs": "0.4",
                    "word": "turtle", "friend": "Ali"]
        for key in keys {
            for text in [tr(key, args)] + Strings.shared.options(key) {
                #expect(Self.plain(text), "\(key.rawValue): \(text)")
            }
        }
    }
}

extension TextRulesTests {
    /// The locked window said a wrong passphrase in plain words (Display.lockError); every other
    /// error, under a field or in a toast, said the engine's words as sent: "That isn't a Raven
    /// invite or card." (screen 74).
    @Test func errorsAreSaidWithoutContractions() throws {
        let keys = Str.allCases.filter { $0.rawValue.hasPrefix("error.") }
        #expect(keys.count > 10)
        for key in keys {
            let shown = Display.plainWords(tr(key, ["name": "Mina"]))
            #expect(shown.range(of: #"\w(n't|'re|'ll|'ve|'m)\b"#, options: .regularExpression) == nil,
                    "\(key.rawValue): \(shown)")
        }
        #expect(Display.plainWords(tr(.errorCardInvalid)) == "That is not a Raven invite or card. Ask your friend to send it again.")
        let controls = try String(contentsOf: packageRoot.appendingPathComponent("Sources/RavenUI/Components/Controls.swift"),
                                  encoding: .utf8)
        #expect(controls.contains("Text(Display.plainWords(error.message))"))
        let mock = readyMock(demo: true)
        let model = AppModel(engine: mock, now: { mock.clock.now })
        model.fail(RavenError(code: ErrorCode.cardInvalid, message: tr(.errorCardInvalid), detail: "parse"))
        #expect(model.toast?.text == "That is not a Raven invite or card. Ask your friend to send it again.")
    }
}
