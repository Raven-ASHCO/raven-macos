import Foundation
import Testing
@testable import RavenUI

@Suite struct SanitizerTests {
    @Test func removesBidiControls() {
        // "Ali" + RIGHT-TO-LEFT OVERRIDE + "gnp.exe" would display as "Aliexe.png".
        #expect(Sanitizer.line("Ali\u{202E}gnp.exe") == "Alignp.exe")
        #expect(Sanitizer.line("\u{2066}a\u{2067}b\u{2068}c\u{2069}\u{202A}d\u{202B}e\u{202C}\u{202D}") == "abcde")
        #expect(Sanitizer.line("a\u{200E}b\u{200F}c\u{061C}") == "abc")
    }

    @Test func removesZeroWidthAndInvisible() {
        #expect(Sanitizer.line("A\u{200B}l\u{200C}i\u{200D}\u{2060}\u{FEFF}") == "Ali")
        #expect(Sanitizer.line("soft\u{00AD}hyphen") == "softhyphen")
        #expect(Sanitizer.line("tag\u{E0041}\u{E007F}s") == "tags")
        #expect(Sanitizer.line("a\u{3164}b\u{115F}c\u{034F}") == "abc")
    }

    @Test func removesControlCharacters() {
        #expect(Sanitizer.line("a\u{0007}b\u{001B}[31mc\u{007F}d\u{0085}e\u{009B}f") == "ab[31mcd ef")
        #expect(Sanitizer.text("bell\u{0007}") == "bell")
    }

    @Test func singleLineCollapsesWhitespace() {
        #expect(Sanitizer.line("  Mina \n\n  B.\t ") == "Mina B.")
        #expect(Sanitizer.line("a\u{2028}b\u{2029}c") == "a b c")
    }

    @Test func messageTextKeepsNewlines() {
        #expect(Sanitizer.text("one\r\ntwo\rthree\nfour") == "one\ntwo\nthree\nfour")
        #expect(Sanitizer.text("a\n\n\n\n\nb") == "a\n\nb")
        #expect(Sanitizer.text("a\u{2028}b") == "a\nb")
    }

    @Test func limitsStackedMarks() {
        let zalgo = "e" + String(repeating: "\u{0301}", count: 40)
        #expect(Sanitizer.line(zalgo).unicodeScalars.count == 4)
        #expect(Sanitizer.line("e\u{0301}") == "e\u{0301}")
    }

    @Test func keepsOrdinaryTextOfAnyScript() {
        #expect(Sanitizer.text("Hello \u{1F44B} naïve café") == "Hello \u{1F44B} naïve café")
        #expect(Sanitizer.text("\u{0627}\u{0628}\u{062A}") == "\u{0627}\u{0628}\u{062A}")   // right-to-left letters stay
    }

    @Test func truncatesLongLines() {
        #expect(Sanitizer.line(String(repeating: "x", count: 300), maxLength: 10) == "xxxxxxxxxx…")
    }

    @Test func sanitisesEveryJSONString() throws {
        let dirty: JSONValue = ["a": "x\u{202E}y", "b": ["c\u{200B}d", 1, true], "e": ["f": "g\u{0007}"]]
        #expect(dirty.sanitized() == ["a": "xy", "b": ["cd", 1, true], "e": ["f": "g"]])
    }

    /// Even if an engine forgets to sanitise, the typed layer cleans names and messages.
    @Test func typedLayerCleansEngineOutput() async throws {
        let engine = DirtyEngine()
        let contacts = try await engine.contacts()
        #expect(contacts.first?.name == "Ali gpj.exe")
        let history = try await engine.history(address: "rvn1qdirty")
        #expect(history.first?.text == "hidden")
        let error = await #expect(throws: RavenError.self) { try await engine.call(op: "fail", args: [:]) }
        #expect(error?.message == "Try again")
    }
}

/// An engine that returns hostile text, to prove the app's own defence.
final class DirtyEngine: RavenEngine, @unchecked Sendable {
    func call(op: String, args: [String: JSONValue]) async throws -> JSONValue {
        switch op {
        case "contacts.list":
            return ["contacts": [[
                "address": "rvn1qdirty", "name": "Ali\u{202E}\n\u{200B}gpj.exe", "short_address": "rvn1qdir…dirty",
                "verified": true, "presence": "in_touch", "future_field": "ignored",
            ]]]
        case "messages.history":
            return ["messages": [[
                "id": "1", "address": "rvn1qdirty", "direction": "in", "text": "\u{2066}hid\u{200D}den\u{2069}",
                "at_ms": 1, "state": "delivered",
            ]]]
        default:
            return try RavenEnvelope.parseResponse(RavenEnvelope.failure(RavenError(code: "INTERNAL", message: "Try\u{202E} again")))
        }
    }
}
