import Foundation
import SuperFlowCore

/// E-mail layout in e-mail apps (behaviour.md §8.3 "Email"; strings.md `personalization_email_*`): the greeting on
/// its own line (inline for Casual), the body, then the sign-off and the name on their own lines.
enum Email {
    struct Parts {
        var greeting: String?
        var body: String
        var signOff: String?
    }

    private static let greetingPattern = try! NSRegularExpression(
        pattern: #"^(good morning|good afternoon|good evening|greetings|hello|hi|hey|dear)(?![\p{L}\p{N}])"#, options: [.caseInsensitive])
    private static let closingPattern = try! NSRegularExpression(pattern: #"(?:^|(?<=[\s,.!?]))("# + [
        "thanks again", "thanks so much", "thank you so much", "many thanks", "thank you", "thanks", "best regards", "kind regards",
        "warm regards", "all the best", "regards", "best wishes", "best", "cheers", "sincerely", "talk soon", "take care",
    ].joined(separator: "|") + #")[,.!]?(?:\s+([\p{L}][\p{L}'’\-]*(?:\s+[\p{L}][\p{L}'’\-]*)?))?[.!]?\s*$"#, options: [.caseInsensitive])
    /// Closings that end an e-mail even without a name after them.
    private static let standaloneClosings: Set<String> = [
        "best regards", "kind regards", "warm regards", "all the best", "regards", "best wishes", "best", "cheers", "sincerely",
    ]
    /// Addressees that stay lower case ("Hi team,").
    private static let groupAddressees: Set<String> = ["team", "all", "everyone", "everybody", "folks", "guys", "there", "y'all", "friends"]
    /// Words that start the body right after a greeting, so they are not part of the name.
    private static let bodyStarters: Set<String> = Lexicon.continuationWords.union([
        "i", "i'm", "i've", "i'd", "i'll", "hope", "just", "quick", "wanted", "following", "regarding", "attached", "per", "great",
        "good", "sorry", "happy",
    ])
    private static let notNames: Set<String> = Lexicon.continuationWords.union(["for", "you", "again", "much", "lot", "everyone", "all"])

    /// Splits a finished text into greeting, body and sign-off; nil when it has neither.
    static func split(_ text: String) -> Parts? {
        var body = text
        var greeting: String?
        var signOff: String?
        if let (line, rest) = splitGreeting(body) { greeting = line; body = rest }
        if let (closing, rest) = splitSignOff(body) { signOff = closing; body = rest }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // A greeting or sign-off alone ("hi John") is a message, not an e-mail to lay out.
        guard greeting != nil || signOff != nil, !body.isEmpty else { return nil }
        return Parts(greeting: greeting, body: body, signOff: signOff)
    }

    static func join(_ parts: Parts, style: WritingStyle) -> String {
        var body = parts.body
        var text = ""
        if let greeting = parts.greeting {
            if style == .casual || style == .veryCasual {
                // "Hi Alex, it was great talking with you today."
                var words = Words(body)
                if words.count > 0, Lexicon.continuationWords.contains(words[0].lower), words[0].lower != "i",
                   Casing.isPlainCapitalized(words[0].text) {
                    words[0].text = words[0].text.lowercased()
                    body = words.text
                }
                text = greeting + " " + body
            } else {
                var words = Words(body)
                if words.count > 0 { words[0].text = Casing.capitalized(words[0].text) }
                text = greeting + "\n\n" + words.text
            }
        } else {
            text = body
        }
        if let signOff = parts.signOff { text = text.isEmpty ? signOff : text + "\n\n" + signOff }
        return text
    }

    private static func splitGreeting(_ text: String) -> (String, String)? {
        let ns = text as NSString
        guard let match = greetingPattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let opener = ns.substring(with: match.range).lowercased()
        let rest = Words(ns.substring(from: match.range.location + match.range.length))
        let length = nameLength(rest)
        let name = (0..<length).map { k in groupAddressees.contains(rest[k].lower) ? rest[k].lower : Casing.capitalized(rest[k].text) }
        var body = rest
        body.items.removeSubrange(0..<length)
        if body.count > 0 { body[0].gap = "" } else { body.tail = "" }
        let line = ([opener.prefix(1).uppercased() + opener.dropFirst()] + name).joined(separator: " ") + ","
        return (line, body.text)
    }

    /// How many words after the greeting are the addressee: up to the first comma or sentence end (three words at
    /// most), else the run of capitalised words, else a group ("team") or a single word the body clearly follows.
    private static func nameLength(_ rest: Words) -> Int {
        guard rest.count > 0, !Gap.hasComma(rest[0].gap), !Gap.endsSentence(rest[0].gap) else { return 0 }
        // "hi John", "hey team thanks": all of it is the greeting line, so there is no e-mail to lay out.
        if rest.count <= 2 { return rest.count }
        let isBody = { (k: Int) in bodyStarters.contains(rest[k].lower) && !groupAddressees.contains(rest[k].lower) }
        if let stop = (1..<min(rest.count, 4)).first(where: { Gap.hasComma(rest[$0].gap) || Gap.endsSentence(rest[$0].gap) }) {
            return (0..<stop).contains(where: isBody) ? 0 : stop
        }
        var length = 0
        while length < min(rest.count - 1, 3), Casing.isPlainCapitalized(rest[length].text), !isBody(length) { length += 1 }
        if length == 0, rest.count > 1, !isBody(0), groupAddressees.contains(rest[0].lower) || bodyStarters.contains(rest[1].lower) {
            length = 1
        }
        return length
    }

    private static func splitSignOff(_ text: String) -> (String, String)? {
        let ns = text as NSString
        guard let match = closingPattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let closing = ns.substring(with: match.range(at: 1))
        let nameRange = match.range(at: 2)
        let name = nameRange.location == NSNotFound ? nil : ns.substring(with: nameRange)
        let nameWords = name?.split(separator: " ").map { String($0) } ?? []
        if nameWords.contains(where: { notNames.contains($0.lowercased()) }) { return nil }
        let before = ns.substring(to: match.range.location)
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard let lastBefore = trimmed.last else { return nil }
        let afterPause = ".,!?\n".contains(lastBefore)
        let enoughBefore = Dictation.countWords(before) >= 3
        guard nameWords.isEmpty ? standaloneClosings.contains(closing.lowercased()) && afterPause : afterPause || enoughBefore else { return nil }
        let line = closing.prefix(1).uppercased() + closing.dropFirst().lowercased() + ","
            + (nameWords.isEmpty ? "" : "\n" + nameWords.map(Casing.capitalized).joined(separator: " "))
        return (line, before.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ",")))
    }
}
