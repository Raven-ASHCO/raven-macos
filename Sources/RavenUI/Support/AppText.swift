import Foundation

/// Texts written for the terminal app send you to a `raven` command ("In a terminal, raven lock stops
/// Raven instead.", "Run `raven unlock` in a terminal."), which the Mac app's DMG doesn't install. The
/// app shows those texts without such sentences: the shared strings.en.json and the engine's messages
/// stay as they are (raven-core changes them for every app; until then this is the Mac app's side).
public enum AppText {
    /// `text` without its sentences that tell you to run a command or use a terminal. Can be empty
    /// when every sentence was such a step.
    public static func withoutTerminalSteps(_ text: String) -> String {
        sentences(text).filter { !isTerminalStep($0) }.joined(separator: " ")
    }

    /// A sentence that needs the terminal: it says "in a terminal" (or "the terminal"), or asks you to
    /// run or use a `raven`/`ash` command (written in lower case: "with Raven" is not a command).
    static func isTerminalStep(_ sentence: String) -> Bool {
        let patterns = [#"\b(?i:in|from|use) (?i:a|the) (?i:terminal)\b"#,
                        #"\b(?i:run|use|with):?\s+`?(raven|ash) [a-z]"#]
        return patterns.contains { sentence.range(of: $0, options: .regularExpression) != nil }
    }

    /// Sentences: split after ".", "!" or "?" followed by a space.
    static func sentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var out: [String] = []
        var current = ""
        var previous: Character?
        for ch in trimmed {
            if ch.isWhitespace, let last = previous, ".!?".contains(last) {
                if !current.isEmpty { out.append(current) }
                current = ""
            } else if !(ch.isWhitespace && current.isEmpty) {
                current.append(ch)
            }
            previous = ch
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

extension RavenError {
    /// This error as the Mac app shows it: its message without terminal steps (the whole message stays
    /// in Details), unless nothing would be left.
    func withoutTerminalSteps() -> RavenError {
        let shown = AppText.withoutTerminalSteps(message)
        guard !shown.isEmpty, shown != message.trimmingCharacters(in: .whitespacesAndNewlines) else { return self }
        return RavenError(code: code, message: shown, detail: detail.isEmpty ? message : message + "\n" + detail)
    }
}
