import Foundation
import SuperFlowCore

/// The deterministic layers around the LLM (local-models.md §3.5), always on. `prepare` runs before the model (and is
/// the whole cleanup when the model is skipped); `finish` runs after it.
struct RulePass {
    let level: CleanupLevel
    let style: WritingStyle
    let format: TranscriptionFormat
    let category: AppCategory
    /// The English rule set (fillers, numbers, lists, styles); other languages get the language-neutral passes
    /// ("Style formatting only applies in English", strings.md `hub_banner_styles_disclaimer`).
    let english: Bool
    let pressEnterEnabled: Bool
    let vocabulary: Vocabulary

    init(_ input: CleanupInput, pressEnterEnabled: Bool) {
        level = input.level
        style = input.style
        format = input.format
        category = input.context.app?.category ?? .other
        let language = input.transcript.language.lowercased()
        english = language.isEmpty || language == "auto" || language.hasPrefix("en")
        self.pressEnterEnabled = pressEnterEnabled
        vocabulary = Vocabulary(dictionary: input.dictionary, snippets: input.snippets)
    }

    /// "None" and "No AI formatting": only commands, snippets and the dictionary touch the words.
    var isVerbatim: Bool { level == .none || format == .noAIFormatting }

    struct Prepared {
        /// The text with snippet placeholders, ready for the LLM or for `finish`.
        var text: String
        var expansions: [String: String]
        var actions: [PostInsertAction]
        /// Words other than placeholders.
        var wordCount: Int
    }

    func prepare(_ raw: String) -> Prepared {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let actions: [PostInsertAction]
        (text, actions) = SpokenCommands.keyActions(text, pressEnterEnabled: pressEnterEnabled)
        let expansions: [String: String]
        (text, expansions) = vocabulary.insertPlaceholders(text)
        text = vocabulary.applyReplacements(text)

        var words = Words(text)
        if english { SpokenCommands.apply(&words) }
        if !isVerbatim {
            if english {
                Disfluency.removeFillers(&words)
                SelfCorrections.apply(&words)
            }
            Disfluency.collapseRepeats(&words)
            if english {
                if category != .terminal { Lists.apply(&words) }
                NumberWords.apply(&words)
            }
            // Terminals take commands ("git status") as typed: no capitals added.
            if category != .terminal { Casing.sentenceCase(&words, english: english) }
        }
        return Prepared(text: Casing.tidy(words.text), expansions: expansions, actions: actions,
                        wordCount: words.items.filter { !$0.isPlaceholder }.count)
    }

    /// Spellings, style, format, snippet expansion and joining with the text around the cursor.
    func finish(_ text: String, _ prepared: Prepared, context: AppContext) -> String {
        var text = vocabulary.enforceSpellings(text)
        if !isVerbatim && english {
            if category == .email, let parts = Email.split(text) {
                var parts = parts
                parts.body = Style.apply(parts.body, style: style, category: category, keep: vocabulary.keepCase,
                                         openEnd: endsWithInlineSnippet(parts.body, prepared))
                text = Email.join(parts, style: style)
            } else {
                text = Style.apply(text, style: style, category: category, keep: vocabulary.keepCase,
                                   openEnd: endsWithInlineSnippet(text, prepared))
            }
        }
        switch format {
        case .casualMessaging where english: text = Style.casualMessaging(text, keep: vocabulary.keepCase)
        case .allLowercase: text = text.lowercased().replacingOccurrences(of: "⟦s", with: "⟦S")
        default: break
        }
        text = Casing.tidy(text)
        if prepared.wordCount == 0 && !prepared.expansions.isEmpty {
            // A snippet-only dictation inserts exactly the expansions.
            text = Words(text).items.filter(\.isPlaceholder).map(\.text).joined(separator: " ")
        }
        text = Vocabulary.expand(text, prepared.expansions)
        return Joining.join(text, before: context.textBefore, after: context.textAfter, english: english)
    }

    /// The text ends with a one-line snippet that ends in a word or number, so the sentence still needs its punctuation.
    private func endsWithInlineSnippet(_ text: String, _ prepared: Prepared) -> Bool {
        let words = Words(text)
        guard let last = words.items.last, last.isPlaceholder, words.tail.isEmpty, let expansion = prepared.expansions[last.text],
              !expansion.contains(where: \.isNewline), let end = expansion.last else { return false }
        return end.isLetter || end.isNumber
    }
}
