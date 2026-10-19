import Combine
import Foundation
import SQLite3
import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch).
public enum FlowStoreModule {
    @MainActor public static func install() {
        let store = SQLiteStore.open()
        // An in-memory session would import the notes only to lose them at quit; the file waits for a usable store.
        if !store.isTemporary { store.importNotesFile(at: SuperFlowPaths.support.appendingPathComponent("notes.json")) }
        Services.history = store
        Services.meetings = store
    }
}

/// The SQLite store behind `HistoryStoring` and `MeetingStoring`. Opening never fails and never loses what is on disk:
/// a damaged file (or one whose schema can't be brought up to date) is moved to `SuperFlowPaths.backup`, a fresh store
/// starts, and every row that can still be read is copied into it; a file that can't be used for any other reason
/// (read-only, busy, a full disk, a folder that can't be written) stays exactly where it is and the session runs on an
/// in-memory store. Either way `openingNotice` says so once.
@MainActor
public final class SQLiteStore: HistoryStoring, MeetingStoring {
    private let db: Database
    private let changeSubject = PassthroughSubject<StoreChange, Never>()
    public var changes: AnyPublisher<StoreChange, Never> { changeSubject.eraseToAnyPublisher() }

    /// Set when the store isn't the one on disk as it was: the card the app shows after launch (strings.md's database errors).
    public private(set) var openingNotice: FlowBarNotification?
    /// The session runs on an in-memory store: nothing is written to disk until the next launch.
    public var isTemporary: Bool { db.url == nil }

    public static func open(at url: URL = SuperFlowPaths.database) -> SQLiteStore {
        switch connect(url) {
        case .ready(let db):
            return SQLiteStore(db)
        case .unusable(let why, let full):
            Log.store.error("Store at \(url.path, privacy: .public) can't be used (\(why, privacy: .public)); it is left untouched and this session keeps history in memory")
            return temporary(notice: full ? StoreNotices.storageFull() : StoreNotices.unavailable())
        case .damaged(let why):
            Log.store.error("Store at \(url.path, privacy: .public) is damaged (\(why, privacy: .public)); a copy goes to Backup and a fresh store starts")
            guard let backup = setAside(url), case .ready(let db) = connect(url) else {
                return temporary(notice: StoreNotices.unavailable())
            }
            let store = SQLiteStore(db)
            let kept = store.salvage(from: backup)
            Log.store.info("Kept \(kept) row(s) from the damaged store")
            store.openingNotice = StoreNotices.damaged()
            return store
        }
    }

    private init(_ db: Database) {
        self.db = db
    }

    private static func temporary(notice: FlowBarNotification) -> SQLiteStore {
        // An in-memory database only fails to open when SQLite itself can't allocate; there is nothing to fall back to.
        let db = try! Database(url: nil)
        try? Schema.migrate(db)
        let store = SQLiteStore(db)
        store.openingNotice = notice
        return store
    }

    private enum Connection {
        case ready(Database)
        /// The file itself is damaged, or its schema can't be migrated: set it aside and start over.
        case damaged(String)
        /// Something around the file is wrong (permissions, locks, space): leave it alone.
        case unusable(String, storageFull: Bool)
    }

    private static func connect(_ url: URL) -> Connection {
        let db: Database
        do { db = try Database(url: url) } catch let error as Database.OpenError {
            return isDamage(error.code) ? .damaged(error.message) : .unusable(error.message, storageFull: error.code == SQLITE_FULL)
        } catch {
            return .unusable(error.localizedDescription, storageFull: false)
        }
        if let damage = db.damage() { return .damaged(damage) }
        do { try Schema.migrate(db) } catch {
            // A step the schema refuses (a table of another shape) is as unusable as damage; anything else is transient.
            let schema = isDamage(db.lastFailure) || [SQLITE_ERROR, SQLITE_CONSTRAINT, SQLITE_MISMATCH, SQLITE_SCHEMA].contains(db.lastFailure)
            return schema ? .damaged("migration: \(error.localizedDescription)")
                          : .unusable(error.localizedDescription, storageFull: db.lastFailure == SQLITE_FULL)
        }
        return .ready(db)
    }

    private static func isDamage(_ code: Int32) -> Bool { code == SQLITE_CORRUPT || code == SQLITE_NOTADB }

    /// Moves the database and its -wal/-shm into Backup under one time stamp; returns the moved database, or nil when
    /// it couldn't be moved (the folder is read-only).
    private static func setAside(_ url: URL) -> URL? {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date())
        let moved = SuperFlowPaths.backup.appendingPathComponent("\(stamp)-\(url.lastPathComponent)")
        do { try fm.moveItem(at: url, to: moved) } catch {
            Log.store.error("Couldn't move the damaged store aside: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        for suffix in ["-wal", "-shm"] {
            try? fm.moveItem(at: URL(fileURLWithPath: url.path + suffix), to: URL(fileURLWithPath: moved.path + suffix))
        }
        return moved
    }

    /// Copies every row that can still be read and decoded from a set-aside database; returns how many were kept.
    private func salvage(from backup: URL) -> Int {
        guard let old = try? Database(url: backup, readOnly: true) else { return 0 }
        var kept = 0
        func copy<T: Decodable>(_ table: String, as type: T.Type, _ save: (T) throws -> Void) {
            for json in old.readableJSON(of: table) {
                guard let value = JSON.decode(type, json) else { continue }
                do { try save(value); kept += 1 } catch {
                    Log.store.error("Couldn't keep a row of \(table, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        copy("dictations", as: Dictation.self) { try save($0) }
        copy("dictionary", as: DictionaryEntry.self) { try save($0) }
        copy("snippets", as: Snippet.self) { try save($0) }
        copy("transforms", as: TransformPrompt.self) { try save($0) }
        copy("notes", as: ScratchNote.self) { try save($0) }
        copy("meetings", as: Meeting.self) { try save($0) }
        copy("action_items", as: ActionItem.self) { try save($0) }
        return kept
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

    // MARK: - Notes

    public var notes: [ScratchNote] {
        ((try? db.query("SELECT json FROM notes ORDER BY updated_at DESC") { JSON.decode(ScratchNote.self, $0.text(0)) }) ?? []).compactMap { $0 }
    }

    public func save(_ note: ScratchNote) throws {
        try db.run("INSERT OR REPLACE INTO notes (id, created_at, updated_at, json) VALUES (?, ?, ?, ?)",
                   [.text(note.id.uuidString), .real(note.createdAt.timeIntervalSince1970), .real(note.updatedAt.timeIntervalSince1970),
                    .text(try JSON.encode(note))])
        changeSubject.send(.notes)
    }

    public func deleteNote(_ id: UUID) throws {
        try db.run("DELETE FROM notes WHERE id = ?", [.text(id.uuidString)])
        changeSubject.send(.notes)
    }

    /// Moves the notes an earlier version kept in `notes.json` (ISO-8601 dates) into the table, then parks the file
    /// in `SuperFlowPaths.backup`. Nothing happens when the file is absent; an unreadable file is parked unimported.
    public func importNotesFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let notes = try? decoder.decode([ScratchNote].self, from: data) {
            for note in notes { try? save(note) }
            Log.store.info("Imported \(notes.count) note(s) from notes.json")
        } else {
            Log.store.error("notes.json is unreadable; parked in Backup without importing")
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? FileManager.default.moveItem(at: url, to: SuperFlowPaths.backup.appendingPathComponent("\(stamp)-\(url.lastPathComponent)"))
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

/// The cards for a store that couldn't be opened as it was (strings.md `database_*`, rewritten for a local app).
enum StoreNotices {
    static func damaged() -> FlowBarNotification {
        FlowBarNotification(id: "store.damaged", title: "Local database corruption",
                            subtitle: "Some of your local data was damaged. Everything readable was kept, and a copy of the old file is in the Backup folder.",
                            variant: .alert, timeout: nil)
    }

    static func unavailable() -> FlowBarNotification {
        FlowBarNotification(id: "store.unavailable", title: "There was an error",
                            subtitle: "Super Flow couldn't open its history, so nothing new is saved until it restarts. Restarting the app should fix it.",
                            variant: .error, timeout: nil)
    }

    static func storageFull() -> FlowBarNotification {
        FlowBarNotification(id: "store.full", title: "Storage Full",
                            subtitle: "You are running out of space on your computer. Free some space, then restart Super Flow to save history again.",
                            variant: .error, timeout: nil)
    }
}
