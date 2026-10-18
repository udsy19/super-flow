import AppKit
import Foundation
import SuperFlowCore

/// Meeting export (behaviour.md §20.8): Markdown or plain text in the notes template of §20.7.5 — title, summary, key
/// decisions, action items, follow-ups, the user's notes (verbatim) and the transcript — plus the action items as a
/// checklist, the clipboard and `.md`/`.txt` files.
public enum MeetingExport {
    public enum Format: String, CaseIterable, Sendable {
        case markdown, plainText

        public var fileExtension: String { self == .markdown ? "md" : "txt" }
    }

    public static func text(_ meeting: Meeting, format: Format, includeTranscript: Bool = true) -> String {
        let md = format == .markdown
        func heading(_ title: String) -> String { md ? "## \(title)" : title.uppercased() }
        var parts: [String] = [md ? "# \(meeting.title)" : meeting.title]

        var facts = [meeting.startedAt.formatted(date: .abbreviated, time: .shortened)]
        if meeting.endedAt != nil { facts.append(duration(meeting.duration)) }
        if let platform = platformName(meeting.platform) { facts.append(platform) }
        var header = facts.joined(separator: " · ")
        let people = meeting.participants.map(\.name).filter { !$0.isEmpty }
        if !people.isEmpty { header += "\nParticipants: " + people.joined(separator: ", ") }
        parts.append(header)

        if let summary = meeting.summary {
            if !summary.summary.isEmpty { parts.append(heading("Summary") + "\n\n" + summary.summary) }
            if !summary.decisions.isEmpty { parts.append(heading("Key decisions") + "\n\n" + bullets(summary.decisions)) }
            if !summary.actionItems.isEmpty { parts.append(heading("Action items") + "\n\n" + checklist(summary.actionItems)) }
            if !summary.followUps.isEmpty { parts.append(heading("Follow-ups") + "\n\n" + bullets(summary.followUps)) }
        }
        let notes = meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { parts.append(heading("Notes") + "\n\n" + notes) }
        if includeTranscript, !meeting.segments.filter(\.isFinal).isEmpty {
            parts.append(heading("Transcript") + "\n\n" + transcript(meeting, format: format))
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// Action items as a checklist ("- [ ] Send the deck — Priya, due 23 Oct 2026").
    public static func checklist(_ items: [ActionItem]) -> String {
        items.sorted { $0.sortOrder < $1.sortOrder }.map { item in
            var line = "- [\(item.isCompleted ? "x" : " ")] \(item.text)"
            var details: [String] = []
            if let owner = item.owner { details.append(owner) }
            if let due = item.due { details.append("due " + due.formatted(date: .abbreviated, time: .omitted)) }
            if !details.isEmpty { line += " — " + details.joined(separator: ", ") }
            return line
        }.joined(separator: "\n")
    }

    /// Consecutive segments of one speaker form a block: "**Priya** (12:04): …" (plain text: "Priya (12:04): …").
    public static func transcript(_ meeting: Meeting, format: Format) -> String {
        var blocks: [(speaker: String, start: TimeInterval, text: [String])] = []
        for segment in TranscriptChunker.finalSegments(meeting.segments) {
            let speaker = meeting.speakerLabel(for: segment)
            if blocks.last?.speaker == speaker { blocks[blocks.count - 1].text.append(segment.text) }
            else { blocks.append((speaker, segment.start, [segment.text])) }
        }
        return blocks.map { block in
            let name = format == .markdown ? "**\(block.speaker)**" : block.speaker
            return "\(name) (\(TranscriptChunker.timestamp(block.start))): " + block.text.joined(separator: " ")
        }.joined(separator: "\n\n")
    }

    public static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// A file name from the title and date: "Design review 2026-10-18.md".
    public static func fileName(for meeting: Meeting, format: Format) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let title = meeting.title.components(separatedBy: unsafe).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let day = meeting.startedAt.formatted(.iso8601.year().month().day())
        return "\(title.isEmpty ? MeetingRecorder.untitledNote : String(title.prefix(80))) \(day).\(format.fileExtension)"
    }

    public static func write(_ meeting: Meeting, format: Format, to url: URL, includeTranscript: Bool = true) throws {
        try Data(text(meeting, format: format, includeTranscript: includeTranscript).utf8).write(to: url, options: .atomic)
    }

    private static func bullets(_ items: [String]) -> String { items.map { "- " + $0 }.joined(separator: "\n") }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private static func platformName(_ platform: MeetingPlatform) -> String? {
        switch platform {
        case .zoom: "Zoom"
        case .teams: "Microsoft Teams"
        case .googleMeet: "Google Meet"
        case .slack: "Slack"
        case .webex: "Webex"
        case .discord: "Discord"
        case .whatsapp: "WhatsApp"
        case .facetime: "FaceTime"
        case .other: nil
        }
    }
}
