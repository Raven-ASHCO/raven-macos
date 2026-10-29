import Foundation

/// Cleans text that came from the engine (and so, possibly, from a friend) before it is displayed.
///
/// The engine promises to sanitise already (API.md); this is the app's second line of defence so a
/// name or a message can never draw over the UI, reorder text, or hide characters:
/// - control characters (C0, DEL, C1) are removed; newlines are kept only in message text;
/// - every Unicode "format" character is removed: bidi embeddings, overrides and isolates
///   (U+202A-202E, U+2066-2069), marks (U+200E, U+200F, U+061C), zero-width characters
///   (U+200B-200D, U+2060, U+FEFF), the soft hyphen, invisible operators and tag characters;
/// - line and paragraph separators become a newline (or a space in single-line text);
/// - blank-looking fillers (Hangul fillers, the combining grapheme joiner) are removed;
/// - long runs of combining marks are cut to 3, so stacked marks cannot spill over other rows.
public enum Sanitizer {
    /// A single line: names, addresses, labels, paths. Whitespace is collapsed and trimmed.
    public static func line(_ text: String, maxLength: Int = 200) -> String {
        let cleaned = clean(text, keepNewlines: false)
        var out = ""
        var lastWasSpace = false
        for ch in cleaned {
            if ch.isWhitespace {
                if !lastWasSpace && !out.isEmpty { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        while out.last == " " { out.removeLast() }
        return truncate(out, maxLength)
    }

    /// Message text: newlines are kept (at most one empty line in a row), everything else as `line`.
    public static func text(_ text: String, maxLength: Int = 20_000) -> String {
        let cleaned = clean(text, keepNewlines: true)
        var out = ""
        var newlineRun = 0
        for ch in cleaned {
            if ch == "\n" {
                newlineRun += 1
                if newlineRun <= 2 { out.append(ch) }
            } else {
                newlineRun = 0
                out.append(ch)
            }
        }
        return truncate(out.trimmingCharacters(in: .whitespacesAndNewlines), maxLength)
    }

    /// True when `scalar` is never shown to the user.
    public static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x115F, 0x1160, 0x3164, 0xFFA0, 0x034F: return true   // fillers, grapheme joiner
        default: break
        }
        switch scalar.properties.generalCategory {
        case .control, .format: return true
        default: return false
        }
    }

    static func clean(_ text: String, keepNewlines: Bool) -> String {
        var scalars = String.UnicodeScalarView()
        var markRun = 0
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // Newlines: CR, LF, CRLF, NEL, LS, PS.
            if v == 0x0A || v == 0x0D || v == 0x85 || v == 0x2028 || v == 0x2029 {
                if v == 0x0A && previousWasCR { previousWasCR = false; continue }
                previousWasCR = (v == 0x0D)
                scalars.append(keepNewlines ? "\n" : " ")
                markRun = 0
                continue
            }
            previousWasCR = false
            if v == 0x09 { scalars.append(" "); markRun = 0; continue }
            if isStripped(scalar) { continue }
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark:
                markRun += 1
                if markRun > 3 { continue }
            default:
                markRun = 0
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    static func truncate(_ text: String, _ maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)) + "…"
    }
}
