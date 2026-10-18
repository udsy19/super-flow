import Foundation
import SuperFlowCore

// Meeting notes (behaviour.md §20.7.4–§20.7.6, local-models.md §8.6): the transcript is cut into chunks that each fit one
// LLM call; every chunk is "mapped" to structured notes (during the meeting, so the end is fast), the notes are merged
// without the LLM, and one short "reduce" call writes the title and summary. Everything the model returns is checked
// against the transcript and the user's notes: items, names, dates and numbers it cannot point to are dropped.

/// One call to the notes LLM.
public struct NotesRequest: Sendable {
    public enum Kind: String, Sendable {
        /// Transcript excerpt → key points, decisions, action items, open questions (JSON).
        case extract
        /// Too many key points → fewer (JSON).
        case condense
        /// Merged notes → title and summary (JSON).
        case write
        /// A question about the meeting → a short answer (text).
        case answer
    }
    public var kind: Kind
    public var instruction: String
    public var input: String
}

/// The local LLM that writes meeting notes (`Defaults[.notesModelID]`, Qwen3.5-4B by default).
@MainActor
public protocol NotesLanguageModel: AnyObject {
    var modelID: String { get }
    var isReady: Bool { get }
    /// Transcript words one call can carry next to its instruction and answer.
    var inputWordBudget: Int { get }
    func complete(_ request: NotesRequest) async throws -> String
}

/// Notes through CleanupKit's LLM (`TextCleaning.transform`), the only LLM entry point in the contracts. It runs on the
/// model CleanupKit has loaded (the cleanup model), not on `Defaults[.notesModelID]`, until the contracts can ask for the
/// notes model. The transform input cap (`DictationLimits.transformMaxWords`) bounds each call, labels included.
@MainActor
final class CleanupNotesModel: NotesLanguageModel {
    var modelID: String { Defaults[.cleanupModelID] ?? Defaults[.notesModelID] }
    var isReady: Bool { Services.cleanup?.isModelReady ?? false }
    var inputWordBudget: Int { DictationLimits.transformMaxWords - 150 }

    func complete(_ request: NotesRequest) async throws -> String {
        guard let cleanup = Services.cleanup else { throw MeetingNotesError.modelNotReady }
        return try await cleanup.transform(request.input, instruction: request.instruction)
    }
}

public enum MeetingNotesError: LocalizedError, Equatable {
    case modelNotReady
    case tooShort
    case noTranscript

    public var errorDescription: String? {
        switch self {
        case .modelNotReady: "The notes model isn't ready yet."
        case .tooShort: "The meeting was too short to summarize."
        case .noTranscript: "No transcript or audio available for a summary"
        }
    }
}

@MainActor
public final class MeetingSummarizer: MeetingSummarizing {
    public static let shared = MeetingSummarizer(model: CleanupNotesModel())

    /// Below this many words of transcript plus notes there is nothing worth summarising.
    public static let minimumWords = 25

    public let model: NotesLanguageModel
    /// Chunk notes by the segments they came from, so the rolling map during the meeting is reused at the end.
    private var cache: [ChunkKey: ChunkNotes] = [:]

    public init(model: NotesLanguageModel) {
        self.model = model
    }

    public var isModelReady: Bool { model.isReady }
    public var chunkWordBudget: Int { max(100, model.inputWordBudget) }

    // MARK: MeetingSummarizing

    public func map(_ segments: [TranscriptSegment]) async throws -> MeetingSummary {
        let notes = try await chunkNotes(segments, label: { $0.channel.liveLabel })
        let grounding = Grounding(TranscriptChunker.render(segments, label: { $0.channel.liveLabel }))
        return MeetingSummary(title: "", summary: notes.keyPoints.map { "- " + $0 }.joined(separator: "\n"), decisions: notes.decisions,
                              actionItems: notes.actions.map { $0.item(meetingID: nil, reference: Date(), grounding: grounding) },
                              followUps: notes.questions, modelID: model.modelID)
    }

    /// The map step for every chunk not mapped yet (the "Summarizing meeting..." stage); `summarize` then only merges and
    /// writes.
    public func mapChunks(of meeting: Meeting) async throws {
        let segments = try summarizableSegments(meeting)
        for chunk in TranscriptChunker.chunks(segments, wordBudget: chunkWordBudget) {
            _ = try await chunkNotes(chunk, label: { meeting.speakerLabel(for: $0) })
        }
    }

    public func summarize(_ meeting: Meeting) async throws -> MeetingSummary {
        let segments = try summarizableSegments(meeting)
        let notesText = meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = { (segment: TranscriptSegment) in meeting.speakerLabel(for: segment) }
        var merged = ChunkNotes()
        for chunk in TranscriptChunker.chunks(segments, wordBudget: chunkWordBudget) {
            merged.merge(try await chunkNotes(chunk, label: label))
        }
        for part in TranscriptChunker.pieces(of: notesText, wordBudget: chunkWordBudget) { merged.merge(try await notesFromUserNotes(part)) }
        merged.keyPoints = try await condense(merged.keyPoints)

        let source = Grounding(TranscriptChunker.render(segments, label: label) + "\n" + notesText + "\n"
                               + (meeting.speakers.map(\.displayName) + meeting.participants.map(\.name)).joined(separator: "\n"))
        let written = try await write(merged)
        let summary = source.groundedSentences(written.summary)
        let generatedTitle = written.title.flatMap { source.supports($0, threshold: 0.5) ? $0 : nil }
        return MeetingSummary(
            title: meeting.calendarEventID == nil ? (generatedTitle ?? meeting.title) : meeting.title,
            summary: summary.isEmpty ? merged.keyPoints.map { "- " + $0 }.joined(separator: "\n") : summary,
            decisions: merged.decisions,
            actionItems: merged.actions.enumerated().map {
                var item = $0.element.item(meetingID: meeting.id, reference: meeting.startedAt, grounding: source)
                item.sortOrder = $0.offset
                return item
            },
            followUps: merged.questions, generatedAt: Date(), modelID: model.modelID)
    }

    public func ask(_ question: String, about meeting: Meeting) async throws -> String {
        guard model.isReady else { throw MeetingNotesError.modelNotReady }
        let segments = TranscriptChunker.finalSegments(meeting.segments)
        guard !segments.isEmpty || !meeting.notes.isEmpty else { throw MeetingNotesError.noTranscript }
        let label = { (segment: TranscriptSegment) in meeting.speakerLabel(for: segment) }
        // Retrieval when the meeting is longer than one call: the chunks sharing the most words with the question.
        let notes = TranscriptChunker.pieces(of: meeting.notes, wordBudget: chunkWordBudget / 4).first ?? ""
        let budget = chunkWordBudget - Dictation.countWords(notes) - Dictation.countWords(question)
        let chunks = TranscriptChunker.chunks(segments, wordBudget: max(100, budget / 3))
        let wanted = Grounding.keys(question)
        let scores = chunks.map { Grounding.keys(TranscriptChunker.render($0, label: label)).intersection(wanted).count }
        let ranked = chunks.indices.sorted { scores[$0] > scores[$1] }
        var chosen: [Int] = []
        var used = 0
        for index in ranked {
            let words = TranscriptChunker.words(chunks[index])
            if !chosen.isEmpty, used + words > budget { break }
            chosen.append(index)
            used += words
        }
        let transcript = chosen.sorted().map { TranscriptChunker.render(chunks[$0], label: label) }.joined(separator: "\n")
        let input = "Transcript:\n\(transcript)" + (notes.isEmpty ? "" : "\n\nThe user's notes:\n\(notes)")
            + "\n\nQuestion: \(question)"
        let answer = try await model.complete(NotesRequest(kind: .answer, instruction: Prompts.answer, input: input))
        return NotesParser.stripReasoning(answer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Map, condense, reduce

    /// The final segments, once the model is ready and there is enough to summarise.
    private func summarizableSegments(_ meeting: Meeting) throws -> [TranscriptSegment] {
        guard model.isReady else { throw MeetingNotesError.modelNotReady }
        let segments = TranscriptChunker.finalSegments(meeting.segments)
        let notes = meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segments.isEmpty || !notes.isEmpty else { throw MeetingNotesError.noTranscript }
        let words = segments.reduce(0) { $0 + Dictation.countWords($1.text) } + Dictation.countWords(notes)
        guard words >= Self.minimumWords else { throw MeetingNotesError.tooShort }
        return segments
    }

    private func chunkNotes(_ chunk: [TranscriptSegment], label: (TranscriptSegment) -> String) async throws -> ChunkNotes {
        let key = ChunkKey(chunk)
        if let cached = cache[key] { return cached }
        guard model.isReady else { throw MeetingNotesError.modelNotReady }
        let text = TranscriptChunker.render(chunk, label: label)
        let output = try await model.complete(NotesRequest(kind: .extract, instruction: Prompts.extract, input: text))
        let notes = ChunkNotes(parsing: output).grounded(in: Grounding(text))
        cache[key] = notes
        return notes
    }

    private func notesFromUserNotes(_ notes: String) async throws -> ChunkNotes {
        let output = try await model.complete(NotesRequest(kind: .extract, instruction: Prompts.extract, input: "The user's notes:\n" + notes))
        return ChunkNotes(parsing: output).grounded(in: Grounding(notes))
    }

    /// Merges key points with the LLM until they fit one call (a few rounds at most; whatever is left is cut).
    private func condense(_ points: [String]) async throws -> [String] {
        var points = points
        for _ in 0..<3 {
            let words = points.reduce(0) { $0 + Dictation.countWords($1) }
            guard words > chunkWordBudget / 2 else { return points }
            let source = Grounding(points.joined(separator: "\n"))
            var groups: [[String]] = [[]]
            var groupWords = 0
            for point in points {
                let count = Dictation.countWords(point)
                if groupWords + count > chunkWordBudget, !groups[groups.count - 1].isEmpty { groups.append([]); groupWords = 0 }
                groups[groups.count - 1].append(point)
                groupWords += count
            }
            var next: [String] = []
            for group in groups {
                let output = try await model.complete(NotesRequest(kind: .condense, instruction: Prompts.condense,
                                                                   input: group.map { "- " + $0 }.joined(separator: "\n")))
                next += NotesParser.strings(NotesParser.object(output)?["key_points"]).filter { source.supports($0, threshold: 0.6) }
            }
            guard !next.isEmpty, next.count < points.count else { break }
            points = next
        }
        var kept: [String] = []
        var words = 0
        for point in points where words + Dictation.countWords(point) <= chunkWordBudget / 2 {
            kept.append(point)
            words += Dictation.countWords(point)
        }
        return kept
    }

    /// The reduce call: title and summary from the merged notes (the user's notes are in them as extracted points).
    private func write(_ notes: ChunkNotes) async throws -> (title: String?, summary: String) {
        let sections = [("Key points", notes.keyPoints), ("Decisions", notes.decisions),
                        ("Action items", notes.actions.map { $0.task + ($0.owner.map { " (\($0))" } ?? "") }), ("Open questions", notes.questions)]
        var input = ""
        for (heading, items) in sections where !items.isEmpty {
            let lines = items.map { "- " + $0 }.joined(separator: "\n")
            guard Dictation.countWords(input + lines) <= chunkWordBudget else { continue }
            input += (input.isEmpty ? "" : "\n\n") + heading + ":\n" + lines
        }
        let output = try await model.complete(NotesRequest(kind: .write, instruction: Prompts.write, input: input))
        guard let object = NotesParser.object(output) else { return (nil, "") }
        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"#*")))
        return (title?.isEmpty == false ? title : nil, (object["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Prompts

enum Prompts {
    static let rules = """
        Use only what the text says. Never add names, owners, dates, numbers or facts that are not in it; leave out \
        anything you are unsure about. Write in the language of the text. Reply with JSON only, no other text.
        """

    static let extract = """
        You take notes from part of a meeting transcript. Each line is "[time] speaker: words". \(rules)
        Return {"key_points": [], "decisions": [], "action_items": [{"task": "", "owner": null, "due": null}], "open_questions": []}.
        key_points: what was discussed, one short sentence each. decisions: what was agreed or decided. action_items: tasks \
        someone committed to or was asked to do; owner is the person's name as said (or the speaker label), due is the exact \
        words used for the deadline, both null when not said. open_questions: questions left open or follow-ups. Use empty \
        lists when there is nothing.
        """

    static let condense = """
        You merge meeting notes. Combine points that say the same thing and keep every distinct fact. \(rules)
        Return {"key_points": []} with one short sentence per point.
        """

    static let write = """
        You write the summary of a meeting from its notes. \(rules)
        Return {"title": "", "summary": ""}. title: 3 to 6 words naming the main topic. summary: one to three short \
        paragraphs covering what was discussed and agreed.
        """

    static let answer = """
        You answer a question about a meeting from its transcript (lines of "[time] speaker: words") and the user's notes. \
        Answer from what was said, briefly, in the language of the question, as plain text. Never add facts that are not \
        in them; only when nothing in them answers the question, say that the meeting didn't cover it.
        """
}

// MARK: - Chunks

/// Cuts finalised segments into chunks of at most `wordBudget` words, in time order (the same cut every time, so chunks
/// mapped during the meeting are found again at the end).
enum TranscriptChunker {
    static func finalSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// Words a rendered line adds besides the text ("[12:04] Speaker 1:"), counted as a constant so the cut does not
    /// depend on labels, which change once speakers are split and named.
    static let lineOverhead = 3

    static func words(_ segments: [TranscriptSegment]) -> Int {
        segments.reduce(0) { $0 + Dictation.countWords($1.text) + lineOverhead }
    }

    static func chunks(_ segments: [TranscriptSegment], wordBudget: Int) -> [[TranscriptSegment]] {
        var chunks: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = []
        var words = 0
        for segment in finalSegments(segments) {
            let count = Dictation.countWords(segment.text) + lineOverhead
            if !current.isEmpty, words + count > wordBudget { chunks.append(current); current = []; words = 0 }
            current.append(segment)
            words += count
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Free text (the user's notes) in pieces of whole lines of at most `wordBudget` words (a longer line is cut).
    static func pieces(of text: String, wordBudget: Int) -> [String] {
        var pieces: [String] = []
        var current: [String] = []
        var words = 0
        for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            var line = line
            if Dictation.countWords(line) > wordBudget {
                line = line.split(separator: " ").prefix(wordBudget).joined(separator: " ")
            }
            let count = Dictation.countWords(line)
            if !current.isEmpty, words + count > wordBudget { pieces.append(current.joined(separator: "\n")); current = []; words = 0 }
            current.append(line)
            words += count
        }
        if !current.isEmpty { pieces.append(current.joined(separator: "\n")) }
        return pieces
    }

    static func render(_ segments: [TranscriptSegment], label: (TranscriptSegment) -> String) -> String {
        segments.map { "[\(timestamp($0.start))] \(label($0)): \($0.text)" }.joined(separator: "\n")
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
                             : String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// A chunk by its segments and their words (speaker labels may change between the live map and the end; edited text
/// may not reuse old notes).
struct ChunkKey: Hashable {
    var ids: [UUID]
    var texts: [String]
    init(_ segments: [TranscriptSegment]) { ids = segments.map(\.id); texts = segments.map(\.text) }
}

/// What one map call found, before the action items get dates.
struct ChunkNotes: Equatable {
    struct Action: Equatable {
        var task: String
        var owner: String?
        var due: String?

        func item(meetingID: UUID?, reference: Date, grounding: Grounding) -> ActionItem {
            let owner = owner.flatMap { grounding.mentions($0) ? $0 : nil }
            let due = due.flatMap { grounding.mentions($0) ? DueDates.resolve($0, after: reference) : nil }
            return ActionItem(meetingID: meetingID, text: task, owner: owner, due: due)
        }
    }

    var keyPoints: [String] = []
    var decisions: [String] = []
    var actions: [Action] = []
    var questions: [String] = []

    init() {}

    init(parsing output: String) {
        guard let object = NotesParser.object(output) else { return }
        keyPoints = NotesParser.strings(object["key_points"] ?? object["keyPoints"] ?? object["summary"])
        decisions = NotesParser.strings(object["decisions"])
        questions = NotesParser.strings(object["open_questions"] ?? object["openQuestions"] ?? object["follow_ups"] ?? object["followUps"])
        let rawActions = (object["action_items"] ?? object["actionItems"]) as? [Any] ?? []
        actions = rawActions.compactMap { raw in
            if let text = raw as? String { return NotesParser.clean(text).map { Action(task: $0) } }
            guard let fields = raw as? [String: Any], let task = NotesParser.clean(fields["task"] as? String ?? fields["text"] as? String) else { return nil }
            return Action(task: task, owner: NotesParser.clean(fields["owner"] as? String), due: NotesParser.clean(fields["due"] as? String))
        }
    }

    /// Drops what the source does not support (local-models.md §8.6: the model once invented a title word).
    func grounded(in source: Grounding) -> ChunkNotes {
        var notes = ChunkNotes()
        notes.keyPoints = keyPoints.filter { source.supports($0, threshold: 0.6) }
        notes.decisions = decisions.filter { source.supports($0, threshold: 0.6) }
        notes.questions = questions.filter { source.supports($0, threshold: 0.6) }
        notes.actions = actions.filter { source.supports($0.task, threshold: 0.6) }.map {
            Action(task: $0.task, owner: $0.owner.flatMap { source.mentions($0) && !Grounding.isGenericOwner($0) ? $0 : nil },
                   due: $0.due.flatMap { source.mentions($0) ? $0 : nil })
        }
        return notes
    }

    /// Appends another chunk's notes, skipping near-duplicates.
    mutating func merge(_ other: ChunkNotes) {
        func add(_ items: [String], to list: inout [String]) {
            for item in items where !list.contains(where: { Grounding.similar($0, item) }) { list.append(item) }
        }
        add(other.keyPoints, to: &keyPoints)
        add(other.decisions, to: &decisions)
        add(other.questions, to: &questions)
        for action in other.actions {
            if let index = actions.firstIndex(where: { Grounding.similar($0.task, action.task) }) {
                if actions[index].owner == nil { actions[index].owner = action.owner }
                if actions[index].due == nil { actions[index].due = action.due }
            } else {
                actions.append(action)
            }
        }
    }
}

// MARK: - Parsing

enum NotesParser {
    /// Removes `<think>…</think>` blocks some models emit before the answer.
    static func stripReasoning(_ text: String) -> String {
        var text = text
        while let open = text.range(of: "<think>") {
            guard let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) else {
                text.removeSubrange(open.lowerBound..<text.endIndex); break
            }
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return text
    }

    /// The first JSON object in the output, ignoring reasoning, code fences and chatter around it.
    static func object(_ output: String) -> [String: Any]? {
        let text = stripReasoning(output)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let json = String(text[start...end])
        if let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] { return object }
        // Trailing commas are the usual small-model slip.
        let repaired = json.replacingOccurrences(of: ",\\s*([}\\]])", with: "$1", options: .regularExpression)
        return try? JSONSerialization.jsonObject(with: Data(repaired.utf8)) as? [String: Any]
    }

    static func strings(_ value: Any?) -> [String] {
        if let text = value as? String { return clean(text).map { [$0] } ?? [] }
        return (value as? [Any] ?? []).compactMap { clean($0 as? String) }
    }

    /// Trims bullets and whitespace; nil for empty values and the "null"/"none" spellings models use.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "-•*")))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ["", "null", "none", "n/a", "unknown"].contains(trimmed.lowercased()) ? nil : trimmed
    }
}

// MARK: - Grounding

/// What the source text (transcript and notes) can vouch for.
struct Grounding {
    private let keys: Set<String>
    private let words: Set<String>

    init(_ source: String) {
        let words = Self.words(source)
        self.words = Set(words)
        keys = Set(words.map(Self.stem))
    }

    /// True when the text's numbers all appear in the source and at least `threshold` of its content words do.
    func supports(_ text: String, threshold: Double) -> Bool {
        let tokens = Self.words(text)
        let numbers = tokens.filter { $0.allSatisfy(\.isNumber) }
        guard numbers.allSatisfy(words.contains) else { return false }
        let content = tokens.filter { !$0.allSatisfy(\.isNumber) && $0.count >= 3 && !Self.stopwords.contains($0) }.map(Self.stem)
        guard !content.isEmpty else { return !numbers.isEmpty }
        return Double(content.filter(keys.contains).count) / Double(content.count) >= threshold
    }

    /// True when every meaningful word of a name or date phrase appears in the source as said.
    func mentions(_ phrase: String) -> Bool {
        let tokens = Self.words(phrase).filter { !Self.phraseFillers.contains($0) }
        return !tokens.isEmpty && tokens.allSatisfy(words.contains)
    }

    static func keys(_ text: String) -> Set<String> {
        Set(words(text).filter { $0.count >= 3 && !stopwords.contains($0) }.map(stem))
    }

    /// Near-duplicate test for merging chunk notes: most content words shared.
    static func similar(_ a: String, _ b: String) -> Bool {
        let x = keys(a), y = keys(b)
        guard !x.isEmpty, !y.isEmpty else { return a.caseInsensitiveCompare(b) == .orderedSame }
        return Double(x.intersection(y).count) / Double(x.union(y).count) >= 0.7
    }

    static func isGenericOwner(_ owner: String) -> Bool {
        ["them", "someone", "everyone", "team", "the team", "all", "unknown", "speaker"].contains(owner.lowercased())
    }

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// A light stemmer: "shipping", "shipped", "ships" → "ship"; "decide", "decided" → "decid".
    static func stem(_ word: String) -> String {
        var word = word
        for suffix in ["ing", "ed", "es", "s", "ly", "e"] where word.hasSuffix(suffix) && word.count - suffix.count >= 3 {
            word.removeLast(suffix.count)
            break
        }
        if word.count >= 4, let last = word.last, word.dropLast().last == last, !"aeiou".contains(last) { word.removeLast() }
        return String(word.prefix(6))
    }

    /// Sentences of a summary the source supports, paragraphs kept.
    func groundedSentences(_ text: String) -> String {
        text.components(separatedBy: "\n\n").compactMap { paragraph -> String? in
            var kept: [String] = []
            paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { sentence, _, _, _ in
                guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
                if supports(sentence, threshold: 0.5) { kept.append(sentence) }
            }
            return kept.isEmpty ? nil : kept.joined(separator: " ")
        }.joined(separator: "\n\n")
    }

    /// Framing words summaries use that a transcript rarely says; they neither prove nor disprove anything.
    static let stopwords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "these", "those", "will", "would", "should", "could", "shall", "have", "has",
        "had", "are", "was", "were", "been", "being", "they", "them", "their", "there", "then", "than", "from", "into", "onto",
        "about", "also", "just", "some", "what", "when", "where", "which", "who", "whom", "whose", "why", "how", "our", "ours",
        "your", "yours", "you", "his", "her", "hers", "its", "not", "but", "can", "all", "any", "each", "other", "more", "most",
        "very", "does", "did", "done", "doing", "make", "made", "need", "needs", "needed", "going", "get", "got", "let", "lets",
        "okay", "yeah", "team", "meeting", "meetings", "discuss", "discussed", "discussion", "agreed", "agree", "agreement",
        "decide", "decided", "decision", "decisions", "action", "item", "items", "follow", "followup", "next", "step", "steps",
        "question", "questions", "open", "point", "points", "key", "talk", "talked", "said", "says", "mention", "mentioned",
        "note", "notes", "noted", "plan", "planned", "group", "participants", "speaker", "speakers", "everyone", "someone",
        "review", "reviewed", "confirm", "confirmed", "update", "updates", "summary", "regarding", "including", "such", "over",
        "after", "before", "during", "while", "both", "only", "own", "same", "out", "off", "via", "per", "upon", "user",
    ]

    /// Words that may surround a name or deadline without being part of it ("by Friday", "end of the day").
    static let phraseFillers: Set<String> = ["by", "on", "at", "in", "the", "of", "before", "until", "end", "this", "next", "a", "an", "mr", "ms", "mrs", "dr"]
}

// MARK: - Due dates

/// Turns the words a deadline was given in into a day, relative to when the meeting happened.
enum DueDates {
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    static func resolve(_ phrase: String, after reference: Date, calendar: Calendar = .current) -> Date? {
        let lower = phrase.lowercased()
        let day = calendar.startOfDay(for: reference)
        let words = Grounding.words(lower)
        if let match = lower.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            let parts = lower[match].split(separator: "-").compactMap { Int($0) }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        if words.contains("today") || words.contains("tonight") || words.contains("eod") || lower.contains("end of day") { return day }
        if words.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: day) }
        // Full names, and the short forms that are not also ordinary words ("sun", "mon").
        if let weekday = weekdays.firstIndex(where: { name in
            words.contains(name) || words.contains { ["tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat"].contains($0) && name.hasPrefix($0) }
        }) {
            return calendar.nextDate(after: day, matching: DateComponents(weekday: weekday + 1), matchingPolicy: .nextTime)
        }
        for (index, word) in words.enumerated() {
            guard word.count >= 3, let month = months.firstIndex(where: { word.hasPrefix($0) }) else { continue }
            let neighbours = [index - 1, index + 1].filter(words.indices.contains).map { words[$0] }
            guard let dayNumber = neighbours.lazy.compactMap({ Int($0.prefix { $0.isNumber }) }).first(where: { (1...31).contains($0) }) else { continue }
            var components = DateComponents(year: calendar.component(.year, from: day), month: month + 1, day: dayNumber)
            if let date = calendar.date(from: components), date < calendar.date(byAdding: .month, value: -6, to: day)! {
                components.year! += 1
            }
            return calendar.date(from: components)
        }
        return nil
    }
}
