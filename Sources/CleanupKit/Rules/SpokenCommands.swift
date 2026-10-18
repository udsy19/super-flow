import Foundation
import SuperFlowCore

/// Spoken punctuation and layout ("comma", "new paragraph", "bullet point"), "all caps …", and the trailing
/// "press enter" key command (behaviour.md §8.3, local-models.md §3.5 step 1).
enum SpokenCommands {
    private enum Mark {
        /// Attaches to the word before: "hello, how".
        case closing(String)
        /// Attaches to the word after: "(note".
        case opening(String)
        /// Replaces the separator: line and paragraph breaks, list bullets.
        case layout(String)
    }

    private struct Command {
        var phrase: [String]
        var mark: Mark
        /// Also an ordinary noun ("the trial period"), so it is skipped after a determiner or before "of".
        var isAlsoAWord = false
    }

    private static let commands: [Command] = [
        Command(phrase: ["new", "paragraph"], mark: .layout("\n\n")),
        Command(phrase: ["next", "paragraph"], mark: .layout("\n\n")),
        Command(phrase: ["new", "line"], mark: .layout("\n")),
        Command(phrase: ["next", "line"], mark: .layout("\n")),
        Command(phrase: ["bullet", "point"], mark: .layout("\n- ")),
        Command(phrase: ["question", "mark"], mark: .closing("?")),
        Command(phrase: ["exclamation", "point"], mark: .closing("!")),
        Command(phrase: ["exclamation", "mark"], mark: .closing("!")),
        Command(phrase: ["full", "stop"], mark: .closing(".")),
        Command(phrase: ["semicolon"], mark: .closing(";")),
        Command(phrase: ["semi", "colon"], mark: .closing(";")),
        Command(phrase: ["ellipsis"], mark: .closing("…")),
        Command(phrase: ["dot", "dot", "dot"], mark: .closing("…")),
        Command(phrase: ["em", "dash"], mark: .closing(" —")),
        Command(phrase: ["open", "quote"], mark: .opening("\"")),
        Command(phrase: ["close", "quote"], mark: .closing("\"")),
        Command(phrase: ["end", "quote"], mark: .closing("\"")),
        Command(phrase: ["unquote"], mark: .closing("\"")),
        Command(phrase: ["open", "parenthesis"], mark: .opening("(")),
        Command(phrase: ["open", "paren"], mark: .opening("(")),
        Command(phrase: ["close", "parenthesis"], mark: .closing(")")),
        Command(phrase: ["close", "paren"], mark: .closing(")")),
        Command(phrase: ["period"], mark: .closing("."), isAlsoAWord: true),
        Command(phrase: ["comma"], mark: .closing(","), isAlsoAWord: true),
        Command(phrase: ["colon"], mark: .closing(":"), isAlsoAWord: true),
    ]

    /// Words that make "period", "comma" or "colon" a noun when they come right before it.
    private static let nounContext: Set<String> = Lexicon.determiners.union([
        "trial", "grace", "waiting", "probation", "billing", "cooling", "notice", "reporting", "study", "rest", "school", "class",
        "time", "free", "first", "second", "third", "last", "next", "same", "whole", "entire", "oxford", "serial", "inverted",
    ])
    private static let nounFollowers: Set<String> = ["of", "is", "was", "will", "ends", "starts", "begins", "cancer", "splice"]

    /// The Press Enter command (behaviour.md §8.3, the reference regex): stripped, and Return is pressed after pasting.
    private static let pressEnter = try! NSRegularExpression(pattern: #"([.!?;])?\s*\bpress enter\s*([.!?,;:-]*)\s*$"#,
                                                             options: [.caseInsensitive])

    /// Strips a trailing "press enter" when the setting is on; returns the remaining text and the key actions.
    static func keyActions(_ text: String, pressEnterEnabled: Bool) -> (String, [PostInsertAction]) {
        guard pressEnterEnabled else { return (text, []) }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pressEnter.firstMatch(in: text, range: range), let swiftRange = Range(match.range, in: text) else { return (text, []) }
        var kept = String(text[..<swiftRange.lowerBound])
        if let terminator = Range(match.range(at: 1), in: text) { kept += text[terminator] }
        return (kept.trimmingCharacters(in: .whitespaces), [.pressReturn])
    }

    static func apply(_ words: inout Words) {
        var i = 0
        while i < words.count {
            if words[i].isPlaceholder { i += 1; continue }
            if let length = allCaps(&words, at: i) { i += length; continue }
            guard let command = commands.first(where: { Disfluency.matches($0.phrase, in: words, at: i) }),
                  !(command.isAlsoAWord && readsAsNoun(words, at: i, length: command.phrase.count)) else { i += 1; continue }
            insert(command.mark, replacing: i..<i + command.phrase.count, in: &words)
        }
    }

    private static func readsAsNoun(_ words: Words, at i: Int, length: Int) -> Bool {
        if i == 0 { return true }
        if nounContext.contains(words[i - 1].lower) && Gap.isSpace(words[i].gap) { return true }
        let next = i + length
        return next < words.count && nounFollowers.contains(words[next].lower) && Gap.isSpace(words[next].gap)
    }

    private static func insert(_ mark: Mark, replacing range: Range<Int>, in words: inout Words) {
        // Punctuation the speech engine put around the spoken command is replaced by the command itself, except a
        // sentence end before a layout command ("Hello. New paragraph." keeps its period).
        let before = range.lowerBound > 0 ? words[range.lowerBound].gap : ""
        let kept = before.filter { ".!?".contains($0) }
        let separator: String
        var attachNext = false
        switch mark {
        case .closing(let p): separator = p + " "
        case .opening(let p): separator = (range.lowerBound > 0 ? " " : "") + p; attachNext = true
        case .layout(let p): separator = kept + p; attachNext = true
        }
        let atEnd = range.upperBound == words.count
        words.items.removeSubrange(range)
        if range.lowerBound == 0, case .closing = mark {
            // Nothing to attach to: drop the command.
            if words.count > 0 { words[0].gap = "" } else { words.tail = "" }
            return
        }
        if atEnd {
            words.tail = attachNext ? separator : separator.trimmingCharacters(in: .whitespaces)
        } else {
            // At the very start nothing comes before: no leading line break or space ("- milk", not "\n-milk").
            words[range.lowerBound].gap = range.lowerBound == 0 ? String(separator.drop { $0.isNewline || $0 == " " }) : separator
        }
    }

    /// "all caps hello" → "HELLO"; returns the words consumed.
    private static func allCaps(_ words: inout Words, at i: Int) -> Int? {
        guard Disfluency.matches(["all", "caps"], in: words, at: i), i + 2 < words.count, !words[i + 2].isPlaceholder else { return nil }
        let gap = words[i].gap
        words.items.removeSubrange(i..<i + 2)
        words[i].gap = gap
        words[i].text = words[i].text.uppercased()
        return 1
    }
}
