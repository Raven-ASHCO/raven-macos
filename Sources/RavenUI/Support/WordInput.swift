import Foundation

/// Splits what the user types while a friend reads their security words.
///
/// Follows the reference parser (core/protocol/reference/raven_protocol/security_words.py):
/// - separators: spaces (also no-break and ideographic), dashes, commas, semicolons, dots, bullets,
///   slashes, bars, colons, brackets and quotes;
/// - Persian, Arabic-Indic and full-width digits are folded to ASCII, and tokens made only of digits
///   are position numbers ("1.", or U+06F1 in Persian digits) and are dropped;
/// - zero-width characters inside a token are dropped; ASCII and full-width letters fold to a-z.
/// Nothing here knows the friend's words: the result is checked only by the engine.
public enum WordInput {
    static let separators: Set<Character> = Set(["\r\n", "\r", "\n"]).union(
        " \t\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}"
            + "-\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}\u{2212},;.\u{00B7}\u{2022}/|:()[]\"'`")
    static let invisible: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{200E}", "\u{200F}", "\u{2060}", "\u{FEFF}"]

    /// Persian (U+06F0), Arabic-Indic (U+0660) and full-width (U+FF10) digits -> ASCII.
    static func foldDigit(_ s: Unicode.Scalar) -> Unicode.Scalar {
        for base: UInt32 in [0x06F0, 0x0660, 0xFF10] where s.value >= base && s.value < base + 10 {
            return Unicode.Scalar(0x30 + s.value - base)!
        }
        return s
    }

    /// ASCII and full-width letters -> lowercase a-z; nil when the token holds anything else.
    public static func foldLatin(_ token: String) -> String? {
        var out = ""
        for s in token.unicodeScalars {
            if invisible.contains(s) { continue }
            var v = s.value
            if (0x41...0x5A).contains(v) { v += 32 }
            else if (0xFF21...0xFF3A).contains(v) { v = v - 0xFF21 + 0x61 }
            else if (0xFF41...0xFF5A).contains(v) { v = v - 0xFF41 + 0x61 }
            guard (0x61...0x7A).contains(v) else { return nil }
            out.unicodeScalars.append(Unicode.Scalar(v)!)
        }
        return out
    }

    /// Tokens in order, position numbers removed. Letters are not folded here (see `foldLatin`).
    public static func tokens(_ text: String) -> [String] {
        var folded = ""
        for s in text.unicodeScalars { folded.unicodeScalars.append(foldDigit(s)) }
        var tokens: [String] = []
        var current = ""
        for ch in folded {
            if separators.contains(ch) {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
            .map { t in String(String.UnicodeScalarView(t.unicodeScalars.filter { !invisible.contains($0) })) }
            .filter { !$0.isEmpty && !$0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// True when `text` ends with a separator, i.e. the last token is finished.
    public static func endsWithSeparator(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return separators.contains(last)
    }

    /// The old letters-and-digits code as typed, ready to compare (engine side): Persian,
    /// Arabic-Indic and full-width digits folded to ASCII, spaces, separators and zero-width
    /// characters dropped. Letters keep their case: the old code is case-sensitive.
    public static func oldCodeKey(_ text: String) -> String {
        var folded = ""
        for s in text.unicodeScalars where !invisible.contains(s) { folded.unicodeScalars.append(foldDigit(s)) }
        return String(folded.filter { !separators.contains($0) && !$0.isWhitespace })
    }

    /// Your own old code as shown to read aloud: groups of 4 separated by spaces, as in the design
    /// ("If4x-36FU-omFi" -> "If4x 36FU omFi"). Only the display changes; letters keep their case,
    /// and the engine ignores the spaces when a friend types the code.
    public static func oldCodeGroups(_ code: String) -> String {
        let key = Array(oldCodeKey(code))
        return stride(from: 0, to: key.count, by: 4)
            .map { String(key[$0..<min($0 + 4, key.count)]) }
            .joined(separator: " ")
    }
}
