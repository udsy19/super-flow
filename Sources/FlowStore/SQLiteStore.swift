import Combine
import Foundation
import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch).
public enum FlowStoreModule {
    @MainActor public static func install() {
        let store = SQLiteStore.open()
        Services.history = store
        Services.meetings = store
    }
}

/// The SQLite store behind `HistoryStoring` and `MeetingStoring`. A database that cannot be opened or migrated is
/// moved to `SuperFlowPaths.backup` and a fresh one is started, so the app always launches.
@MainActor
public final class SQLiteStore: HistoryStoring, MeetingStoring {
    private let db: Database
    private let changeSubject = PassthroughSubject<StoreChange, Never>()
    public var changes: AnyPublisher<StoreChange, Never> { changeSubject.eraseToAnyPublisher() }

    public static func open(at url: URL = SuperFlowPaths.database) -> SQLiteStore {
        do {
            return try SQLiteStore(url: url)
        } catch {
            Log.store.error("Store at \(url.path, privacy: .public) is damaged: \(error.localizedDescription, privacy: .public); starting over")
            let fm = FileManager.default
            let stamp = ISO8601DateFormatter().string(from: Date())
            for suffix in ["", "-wal", "-shm"] {
                let file = URL(fileURLWithPath: url.path + suffix)
                try? fm.moveItem(at: file, to: SuperFlowPaths.backup.appendingPathComponent("\(stamp)-\(file.lastPathComponent)"))
            }
            return try! SQLiteStore(url: url)
        }
    }

    public init(url: URL) throws {
        db = try Database(url: url)
        try Schema.migrate(db)
    }

    // MARK: - Dictations

    public func dictation(_ id: UUID) -> Dictation? {
        (try? db.query("SELECT json FROM dictations WHERE id = ?", [.text(id.uuidString)]) { JSON.decode(Dictation.self, $0.text(0)) })?
            .first ?? nil
    }

    public func dictations(matching query: String, limit: Int, offset: Int) -> [Dictation] {
        let rows: [Dictation?]
        if let fts = Schema.ftsQuery(query) {
            rows = (try? db.query("""
                SELECT d.json FROM dictations d JOIN dictations_fts f ON f.id = d.id WHERE dictations_fts MATCH ? AND d.is_archived = 0
                ORDER BY d.created_at DESC LIMIT ? OFFSET ?
                """, [.text(fts), .int(Int64(limit)), .int(Int64(offset))]) { JSON.decode(Dictation.self, $0.text(0)) }) ?? []
        } else {
            rows = (try? db.query("SELECT json FROM dictations WHERE is_archived = 0 ORDER BY created_at DESC LIMIT ? OFFSET ?",
                                  [.int(Int64(limit)), .int(Int64(offset))]) { JSON.decode(Dictation.self, $0.text(0)) }) ?? []
        }
        return rows.compactMap { $0 }
    }

    public var lastDictation: Dictation? { dictations(matching: "", limit: 1, offset: 0).first }

    public func save(_ dictation: Dictation) throws {
        try db.transaction {
            try db.run("""
                INSERT OR REPLACE INTO dictations (id, created_at, bundle_id, outcome, word_count, duration, audio_file, is_archived, json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(dictation.id.uuidString), .real(dictation.createdAt.timeIntervalSince1970),
                      dictation.app.map { .text($0.bundleID) } ?? .null, .text(dictation.outcome.rawValue),
                      .int(Int64(dictation.wordCount)), .real(dictation.duration), dictation.audioFile.map { .text($0) } ?? .null,
                      .int(dictation.isArchived ? 1 : 0), .text(try JSON.encode(dictation))])
            try db.run("DELETE FROM dictations_fts WHERE id = ?", [.text(dictation.id.uuidString)])
            try db.run("INSERT INTO dictations_fts (id, text) VALUES (?, ?)",
                       [.text(dictation.id.uuidString), .text(dictation.rawText + "\n" + dictation.cleanedText)])
        }
        changeSubject.send(.dictations)
    }

    public func deleteDictation(_ id: UUID) throws {
        guard let existing = dictation(id) else { throw StoreError.notFound(id) }
        try db.transaction {
            try db.run("DELETE FROM dictations WHERE id = ?", [.text(id.uuidString)])
            try db.run("DELETE FROM dictations_fts WHERE id = ?", [.text(id.uuidString)])
        }
        if let file = existing.audioFile { try? FileManager.default.removeItem(at: SuperFlowPaths.dictationAudio.appendingPathComponent(file)) }
        changeSubject.send(.dictations)
    }

    @discardableResult public func pruneDictations(before cutoff: Date) throws -> Int {
        let ids = try db.query("SELECT id, audio_file FROM dictations WHERE created_at < ?", [.real(cutoff.timeIntervalSince1970)]) {
            ($0.text(0), $0.isNull(1) ? nil : $0.text(1))
        }
        guard !ids.isEmpty else { return 0 }
        try db.transaction {
            try db.run("DELETE FROM dictations_fts WHERE id IN (SELECT id FROM dictations WHERE created_at < ?)", [.real(cutoff.timeIntervalSince1970)])
            try db.run("DELETE FROM dictations WHERE created_at < ?", [.real(cutoff.timeIntervalSince1970)])
        }
        for (_, file) in ids { if let file { try? FileManager.default.removeItem(at: SuperFlowPaths.dictationAudio.appendingPathComponent(file)) } }
        changeSubject.send(.reloaded)
        return ids.count
    }

    @discardableResult public func eraseDictations() throws -> Int {
        try pruneDictations(before: .distantFuture)
    }

    public func statistics(since: Date) -> (dictations: Int, words: Int, seconds: TimeInterval) {
        let row = try? db.query("SELECT COUNT(*), COALESCE(SUM(word_count), 0), COALESCE(SUM(duration), 0) FROM dictations WHERE created_at >= ?",
                                [.real(since.timeIntervalSince1970)]) { (Int($0.int(0)), Int($0.int(1)), $0.real(2)) }.first
        return row ?? (0, 0, 0)
    }

    // MARK: - Dictionary, snippets, transforms

    public var dictionary: [DictionaryEntry] {
        ((try? db.query("SELECT json FROM dictionary ORDER BY created_at DESC") { JSON.decode(DictionaryEntry.self, $0.text(0)) }) ?? [])
            .compactMap { $0 }
    }

    public func save(_ entry: DictionaryEntry) throws {
        let phrase = entry.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { throw StoreError.invalid("The word can't be empty.") }
        var entry = entry
        entry.phrase = phrase
        try db.run("INSERT OR REPLACE INTO dictionary (id, phrase, created_at, is_starred, json) VALUES (?, ?, ?, ?, ?)",
                   [.text(entry.id.uuidString), .text(phrase), .real(entry.createdAt.timeIntervalSince1970), .int(entry.isStarred ? 1 : 0),
                    .text(try JSON.encode(entry))])
        changeSubject.send(.dictionary)
    }

    public func deleteDictionaryEntry(_ id: UUID) throws {
        try db.run("DELETE FROM dictionary WHERE id = ?", [.text(id.uuidString)])
        changeSubject.send(.dictionary)
    }

    public var snippets: [Snippet] {
        ((try? db.query("SELECT json FROM snippets ORDER BY created_at DESC") { JSON.decode(Snippet.self, $0.text(0)) }) ?? []).compactMap { $0 }
    }

    public func save(_ snippet: Snippet) throws {
        let trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trigger.isEmpty else { throw StoreError.invalid("The snippet needs a trigger phrase.") }
        guard snippet.expansion.count <= Snippet.maxExpansionLength else { throw StoreError.invalid("This expansion is too long") }
        var snippet = snippet
        snippet.trigger = trigger
        try db.run("INSERT OR REPLACE INTO snippets (id, trigger, created_at, json) VALUES (?, ?, ?, ?)",
                   [.text(snippet.id.uuidString), .text(trigger), .real(snippet.createdAt.timeIntervalSince1970), .text(try JSON.encode(snippet))])
        changeSubject.send(.snippets)
    }

    public func deleteSnippet(_ id: UUID) throws {
        try db.run("DELETE FROM snippets WHERE id = ?", [.text(id.uuidString)])
        changeSubject.send(.snippets)
    }

    public var transforms: [TransformPrompt] {
        ((try? db.query("SELECT json FROM transforms ORDER BY name") { JSON.decode(TransformPrompt.self, $0.text(0)) }) ?? []).compactMap { $0 }
    }

    public func save(_ transform: TransformPrompt) throws {
        try db.run("INSERT OR REPLACE INTO transforms (id, name, json) VALUES (?, ?, ?)",
                   [.text(transform.id.uuidString), .text(transform.name), .text(try JSON.encode(transform))])
    }

    public func deleteTransform(_ id: UUID) throws {
        try db.run("DELETE FROM transforms WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: - Meetings

    public func meeting(_ id: UUID) -> Meeting? {
        (try? db.query("SELECT json FROM meetings WHERE id = ?", [.text(id.uuidString)]) { JSON.decode(Meeting.self, $0.text(0)) })?.first ?? nil
    }

    public func meetings(matching query: String, limit: Int, offset: Int) -> [Meeting] {
        let rows: [Meeting?]
        if let fts = Schema.ftsQuery(query) {
            rows = (try? db.query("""
                SELECT m.json FROM meetings m JOIN meetings_fts f ON f.id = m.id WHERE meetings_fts MATCH ?
                ORDER BY m.started_at DESC LIMIT ? OFFSET ?
                """, [.text(fts), .int(Int64(limit)), .int(Int64(offset))]) { JSON.decode(Meeting.self, $0.text(0)) }) ?? []
        } else {
            rows = (try? db.query("SELECT json FROM meetings ORDER BY started_at DESC LIMIT ? OFFSET ?",
                                  [.int(Int64(limit)), .int(Int64(offset))]) { JSON.decode(Meeting.self, $0.text(0)) }) ?? []
        }
        return rows.compactMap { $0 }
    }

    public func save(_ meeting: Meeting) throws {
        try db.transaction {
            try db.run("INSERT OR REPLACE INTO meetings (id, started_at, ended_at, has_audio, title, json) VALUES (?, ?, ?, ?, ?, ?)",
                       [.text(meeting.id.uuidString), .real(meeting.startedAt.timeIntervalSince1970),
                        meeting.endedAt.map { .real($0.timeIntervalSince1970) } ?? .null, .int(meeting.hasAudio ? 1 : 0),
                        .text(meeting.title), .text(try JSON.encode(meeting))])
            try db.run("DELETE FROM meetings_fts WHERE id = ?", [.text(meeting.id.uuidString)])
            let text = [meeting.title, meeting.notes, meeting.summary?.summary ?? "", meeting.transcriptText].joined(separator: "\n")
            try db.run("INSERT INTO meetings_fts (id, text) VALUES (?, ?)", [.text(meeting.id.uuidString), .text(text)])
        }
        changeSubject.send(.meetings)
    }

    public func deleteMeeting(_ id: UUID) throws {
        guard meeting(id) != nil else { throw StoreError.notFound(id) }
        try db.transaction {
            try db.run("DELETE FROM meetings WHERE id = ?", [.text(id.uuidString)])
            try db.run("DELETE FROM meetings_fts WHERE id = ?", [.text(id.uuidString)])
            try db.run("DELETE FROM action_items WHERE meeting_id = ?", [.text(id.uuidString)])
        }
        try? FileManager.default.removeItem(at: SuperFlowPaths.meetingAudio.appendingPathComponent(id.uuidString))
        changeSubject.send(.meetings)
    }

    public func meetingsWithAudio(before cutoff: Date) -> [Meeting] {
        ((try? db.query("SELECT json FROM meetings WHERE has_audio = 1 AND ended_at IS NOT NULL AND ended_at < ? ORDER BY started_at",
                        [.real(cutoff.timeIntervalSince1970)]) { JSON.decode(Meeting.self, $0.text(0)) }) ?? []).compactMap { $0 }
    }

    @discardableResult public func pruneMeetings(before cutoff: Date) throws -> Int {
        let ids = try db.query("SELECT id FROM meetings WHERE ended_at IS NOT NULL AND ended_at < ?", [.real(cutoff.timeIntervalSince1970)]) {
            UUID(uuidString: $0.text(0))
        }.compactMap { $0 }
        for id in ids { try deleteMeeting(id) }
        if !ids.isEmpty { changeSubject.send(.reloaded) }
        return ids.count
    }

    // MARK: - Action items

    public var actionItems: [ActionItem] {
        ((try? db.query("SELECT json FROM action_items ORDER BY is_completed, sort_order") { JSON.decode(ActionItem.self, $0.text(0)) }) ?? [])
            .compactMap { $0 }
    }

    public func save(_ item: ActionItem) throws {
        try db.run("INSERT OR REPLACE INTO action_items (id, meeting_id, sort_order, is_completed, is_archived, json) VALUES (?, ?, ?, ?, ?, ?)",
                   [.text(item.id.uuidString), item.meetingID.map { .text($0.uuidString) } ?? .null, .int(Int64(item.sortOrder)),
                    .int(item.isCompleted ? 1 : 0), .int(item.isArchived ? 1 : 0), .text(try JSON.encode(item))])
        changeSubject.send(.actionItems)
    }

    public func deleteActionItem(_ id: UUID) throws {
        try db.run("DELETE FROM action_items WHERE id = ?", [.text(id.uuidString)])
        changeSubject.send(.actionItems)
    }
}
