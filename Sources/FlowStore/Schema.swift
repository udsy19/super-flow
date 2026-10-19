import Foundation

/// Tables (behaviour.md §19.1, trimmed to what the rebuild keeps). Each row is the JSON of its Core value plus the
/// columns the queries need; FTS5 indexes the text that search covers. `migrate` runs the steps past `user_version`.
enum Schema {
    static let version = 2

    static let create = """
    CREATE TABLE IF NOT EXISTS dictations (
        id TEXT PRIMARY KEY, created_at REAL NOT NULL, bundle_id TEXT, outcome TEXT NOT NULL, word_count INTEGER NOT NULL,
        duration REAL NOT NULL, audio_file TEXT, is_archived INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS dictations_created ON dictations(created_at DESC);
    CREATE VIRTUAL TABLE IF NOT EXISTS dictations_fts USING fts5(id UNINDEXED, text, tokenize = 'unicode61 remove_diacritics 2');

    CREATE TABLE IF NOT EXISTS dictionary (
        id TEXT PRIMARY KEY, phrase TEXT NOT NULL UNIQUE COLLATE NOCASE, created_at REAL NOT NULL, is_starred INTEGER NOT NULL,
        json TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS snippets (
        id TEXT PRIMARY KEY, trigger TEXT NOT NULL UNIQUE COLLATE NOCASE, created_at REAL NOT NULL, json TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS transforms (id TEXT PRIMARY KEY, name TEXT NOT NULL, json TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, created_at REAL NOT NULL, updated_at REAL NOT NULL, json TEXT NOT NULL);

    CREATE TABLE IF NOT EXISTS meetings (
        id TEXT PRIMARY KEY, started_at REAL NOT NULL, ended_at REAL, has_audio INTEGER NOT NULL, title TEXT NOT NULL, json TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS meetings_started ON meetings(started_at DESC);
    CREATE VIRTUAL TABLE IF NOT EXISTS meetings_fts USING fts5(id UNINDEXED, text, tokenize = 'unicode61 remove_diacritics 2');

    CREATE TABLE IF NOT EXISTS action_items (
        id TEXT PRIMARY KEY, meeting_id TEXT, sort_order INTEGER NOT NULL, is_completed INTEGER NOT NULL, is_archived INTEGER NOT NULL,
        json TEXT NOT NULL);
    """

    static func migrate(_ db: Database) throws {
        if db.userVersion < 1 {
            try db.exec(create)
            db.userVersion = 1
        }
        if db.userVersion < 2 {
            // `create` is idempotent; version 2 adds the notes table.
            try db.exec(create)
            db.userVersion = 2
        }
    }

    /// Turns a search string into an FTS5 prefix query: each word becomes `"word"*`, AND-ed.
    static func ftsQuery(_ text: String) -> String? {
        let words = text.split { $0.isWhitespace }.map { String($0).replacingOccurrences(of: "\"", with: "") }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }
}
