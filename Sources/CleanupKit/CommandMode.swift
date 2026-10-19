import Foundation
import SuperFlowCore

/// What a Transform or a Command Mode instruction asks for (behaviour.md §10). Short spoken instructions are
/// recognised so the prompt can add the right constraints ("Output only the translation", "use only facts from the
/// text") and the guardrails can bound the output; anything else runs as a custom instruction, verbatim.
enum CommandIntent: Equatable {
    case uppercase, lowercase
    case translate(language: String)
    case summarize
    case formal, casual
    case shorter, longer
    case fixGrammar
    case list
    case polish
    /// A question about the selected text ("what does this mean?").
    case question
    case custom

    /// Instructions longer than this are saved Transform prompts and always run as written.
    static let maxRecognisedWords = 12

    /// Pattern → intent, first match wins.
    private static let rules: [(String, CommandIntent)] = [
        (#"\b(?:all caps|upper ?case|capital letters)\b"#, .uppercase),
        (#"\blower ?case\b"#, .lowercase),
        (#"\b(?:summari[sz]e|summary|sum (?:it|this) up|tl;?dr|gist)\b"#, .summarize),
        (#"\bfix\b.*\b(?:grammar|spelling|typos?|mistakes|punctuation)\b|\bproofread\b|\bcorrect (?:the )?(?:grammar|spelling)\b"#, .fixGrammar),
        (#"\b(?:bullet(?:ed)?(?: points?| list)?|numbered list|(?:into|as) a list|list form)\b"#, .list),
        (#"\b(?:more formal|formal|professional|polite)\b"#, .formal),
        (#"\b(?:casual|friendlier|friendly|informal|relaxed|less formal)\b"#, .casual),
        (#"\b(?:shorter|more concise|concise|condense|shorten|trim (?:it|this)|briefer|tighten)\b"#, .shorter),
        (#"\b(?:longer|expand|elaborate|more detail(?:ed)?|flesh (?:it|this) out)\b"#, .longer),
        (#"^(?:polish|clean (?:it|this) up|clean up|tidy (?:it|this) up)\b"#, .polish),
    ]
    private static let translation = try! NSRegularExpression(pattern: [
        #"\btranslate\b(?:.*?\b(?:in|into|to)\s+(?:the\s+)?([\p{L}][\p{L}\-]*(?:\s+[\p{L}][\p{L}\-]*)?))?\s*[.!?]?$"#,
        #"\b(?:say|write|put) (?:this|it) in ([\p{L}][\p{L}\-]*)\s*[.!?]?$"#,
    ].joined(separator: "|"))

    init(_ instruction: String) {
        let lower = instruction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard Dictation.countWords(lower) <= Self.maxRecognisedWords else { self = .custom; return }
        if let language = Self.translationTarget(lower) { self = .translate(language: language); return }
        if let intent = Self.rules.first(where: { lower.range(of: $0.0, options: .regularExpression) != nil })?.1 { self = intent; return }
        let words = lower.split { !$0.isLetter && $0 != "'" && $0 != "’" }.map(String.init)
        let opensQuestion = words.first.map { Lexicon.isQuestion(firstWord: $0, secondWord: words.dropFirst().first) } ?? false
        self = lower.hasSuffix("?") || opensQuestion ? .question : .custom
    }

    /// "translate this into Spanish please" → "Spanish"; "translate this" → "English".
    private static func translationTarget(_ lower: String) -> String? {
        guard let match = translation.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) else { return nil }
        let captured = [1, 2].compactMap { Range(match.range(at: $0), in: lower) }.first.map { String(lower[$0]) } ?? "english"
        let name = captured.replacingOccurrences(of: #"\s+(?:please|for me|language)$"#, with: "", options: .regularExpression)
        guard !name.isEmpty else { return nil }
        return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Instructions that need no model: case changes always; a plain bulleted list when no model is loaded.
    func applyWithoutModel(_ text: String, modelAvailable: Bool) -> String? {
        switch self {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .list where !modelAvailable: return Self.bullets(text)
        default: return nil
        }
    }

    /// One item per line: the existing lines, else the sentences, else the comma-separated parts.
    static func bullets(_ text: String) -> String {
        let clean = { (s: Substring) in s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-•*"))) }
        var items = text.split(whereSeparator: \.isNewline).map(clean).filter { !$0.isEmpty }
        if items.count < 2 {
            items = text.components(separatedBy: CharacterSet(charactersIn: ".!?;")).map { clean(Substring($0)) }.filter { !$0.isEmpty }
        }
        if items.count < 2 {
            // "eggs, milk and bread": commas, and the last "and"/"or".
            items = text.split(separator: ",").map(clean).filter { !$0.isEmpty }
            if let last = items.popLast() {
                let parts = last.components(separatedBy: " and ").count > 1 ? last.components(separatedBy: " and ") : last.components(separatedBy: " or ")
                let tail = parts.count > 1 ? [parts.dropLast().joined(separator: " and "), parts[parts.count - 1]] : [last]
                items += tail.map { clean(Substring($0)) }.map { $0.hasPrefix("and ") ? String($0.dropFirst(4)) : $0 }.filter { !$0.isEmpty }
            }
        }
        return items.map { "- " + $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "\n")
    }

    /// The task line of the transform prompt.
    var task: String {
        switch self {
        case .translate(let language): "Translate the text into \(language). Output only the translation."
        case .summarize: "Summarize the text in a few sentences, using only information from the text."
        case .formal: "Rewrite the text in a more formal, professional tone. Keep every fact and the same meaning."
        case .casual: "Rewrite the text in a more casual, friendly tone. Keep every fact and the same meaning."
        case .shorter: "Rewrite the text to be more concise. Keep every key fact."
        case .longer: "Expand the text with more detail and smoother flow, using only ideas already in the text."
        case .fixGrammar: "Fix grammar, spelling and punctuation. Change nothing else."
        case .list: "Turn the text into a list, one item per line, each starting with \"- \"."
        case .polish: CommandIntent.polishTask(rules: Defaults[.polishRules])
        case .question: "Answer the question about the text briefly, using only the text."
        case .custom, .uppercase, .lowercase: "Follow the instruction."
        }
    }

    /// Polish's rule checkboxes (behaviour.md §10.1, `Defaults[.polishRules]`) as prompt fragments.
    static func polishTask(rules: [String]) -> String {
        let fragments: [String: String] = [
            "concise": "make it more concise", "clarity": "reword for clarity", "reorder": "reorder for readability",
            "structure": "add structure for readability", "tone": "keep the writer's tone and voice",
        ]
        let chosen = rules.compactMap { fragments[$0] }
        guard !chosen.isEmpty else { return "Polish the text for clarity, keeping the writer's tone." }
        return "Polish the text: " + chosen.joined(separator: "; ") + ". Keep every fact."
    }

    /// The most words the output may have for `inputWords` of selected text; nil when the task sets no bound.
    func maxOutputWords(_ inputWords: Int) -> Int? {
        switch self {
        case .formal, .casual, .fixGrammar, .polish, .translate, .list, .shorter: max(3 * inputWords, inputWords + 30)
        case .summarize: inputWords + 10
        case .longer, .question, .custom, .uppercase, .lowercase: nil
        }
    }

    /// Output token budget relative to the input's tokens.
    var outputFactor: Double {
        switch self {
        case .longer: 3
        case .translate: 2.5
        case .summarize, .question: 1
        default: 2
        }
    }
}
