import Foundation
import SQLite3
import SuperFlowCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A thin SQLite3 wrapper: one connection, WAL, foreign keys, typed binds. Rows are JSON documents in a few indexed
/// columns, so the schema stays small while the domain model evolves (see `Schema`).
final class Database {
    private var db: OpaquePointer?
    let url: URL

    init(url: URL) throws {
        self.url = url
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw StoreError.database(message)
        }
        try exec("PRAGMA journal_mode = WAL")
        try exec("PRAGMA foreign_keys = ON")
        try exec("PRAGMA busy_timeout = 2000")
    }

    deinit { sqlite3_close(db) }

    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(error)
            throw StoreError.database(message)
        }
    }

    enum Value {
        case text(String), int(Int64), real(Double), null
    }

    /// Runs a statement that returns no rows.
    func run(_ sql: String, _ binds: [Value] = []) throws {
        let statement = try prepare(sql, binds)
        defer { sqlite3_finalize(statement) }
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw StoreError.database(String(cString: sqlite3_errmsg(db))) }
    }

    /// Runs a query and maps every row.
    func query<T>(_ sql: String, _ binds: [Value] = [], _ row: (Row) throws -> T) throws -> [T] {
        let statement = try prepare(sql, binds)
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW { results.append(try row(Row(statement: statement!))) }
            else if rc == SQLITE_DONE { break }
            else { throw StoreError.database(String(cString: sqlite3_errmsg(db))) }
        }
        return results
    }

    func scalar(_ sql: String, _ binds: [Value] = []) throws -> Int64 {
        try query(sql, binds) { $0.int(0) }.first ?? 0
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    var userVersion: Int {
        get { Int((try? scalar("PRAGMA user_version")) ?? 0) }
        set { try? exec("PRAGMA user_version = \(newValue)") }
    }

    private func prepare(_ sql: String, _ binds: [Value]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.database(String(cString: sqlite3_errmsg(db)))
        }
        for (index, value) in binds.enumerated() {
            let i = Int32(index + 1)
            switch value {
            case .text(let s): sqlite3_bind_text(statement, i, s, -1, sqliteTransient)
            case .int(let n): sqlite3_bind_int64(statement, i, n)
            case .real(let d): sqlite3_bind_double(statement, i, d)
            case .null: sqlite3_bind_null(statement, i)
            }
        }
        return statement
    }

    struct Row {
        let statement: OpaquePointer
        func text(_ i: Int) -> String { sqlite3_column_text(statement, Int32(i)).map { String(cString: $0) } ?? "" }
        func int(_ i: Int) -> Int64 { sqlite3_column_int64(statement, Int32(i)) }
        func real(_ i: Int) -> Double { sqlite3_column_double(statement, Int32(i)) }
        func isNull(_ i: Int) -> Bool { sqlite3_column_type(statement, Int32(i)) == SQLITE_NULL }
    }
}

/// JSON coding shared by every table: dates as seconds since 1970 so SQL can compare them.
enum JSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ text: String) -> T? {
        try? decoder.decode(type, from: Data(text.utf8))
    }
}
