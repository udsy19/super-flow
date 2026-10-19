import Combine
import Foundation
import FlowStore
import SQLite3
import SuperFlowCore

// Owned with FlowStore: the SQLite store behind HistoryStoring and MeetingStoring.
func registerFlowStoreTests() {
    SelfTest.cases.append(("FlowStore.dictations", { MainActor.assumeIsolated { storeDictations() } }))
    SelfTest.cases.append(("FlowStore.dictionaryAndSnippets", { MainActor.assumeIsolated { storeDictionary() } }))
    SelfTest.cases.append(("FlowStore.meetings", { MainActor.assumeIsolated { storeMeetings() } }))
    SelfTest.cases.append(("FlowStore.damagedRecovery", { MainActor.assumeIsolated { storeRecovery() } }))
    SelfTest.cases.append(("FlowStore.salvageDamagedPages", { MainActor.assumeIsolated { storeSalvage() } }))
    SelfTest.cases.append(("FlowStore.migrationFailureKeepsRows", { MainActor.assumeIsolated { storeMigrationFailure() } }))
    SelfTest.cases.append(("FlowStore.unwritableFolder", { MainActor.assumeIsolated { storeUnwritableFolder() } }))
    SelfTest.cases.append(("FlowStore.concurrentWriters", { MainActor.assumeIsolated { storeConcurrentWriters() } }))
    SelfTest.cases.append(("FlowStore.notes", { MainActor.assumeIsolated { storeNotes() } }))
}

@MainActor private func freshStore() -> SQLiteStore {
    SQLiteStore.open(at: SuperFlowPaths.support.appendingPathComponent("test-\(UUID().uuidString).sqlite"))
}

@MainActor private func storeDictations() {
    let store = freshStore()
    let older = Dictation(createdAt: Date(timeIntervalSince1970: 1_800_000_000), rawText: "um send the invoice", cleanedText: "Send the invoice.",
                          app: AppRecord(bundleID: "com.apple.mail", name: "Mail", category: .email), duration: 2)
    let newer = Dictation(createdAt: Date(timeIntervalSince1970: 1_800_000_100), rawText: "hola Anaïs", cleanedText: "Hola, Anaïs.", language: "es", duration: 1)
    try? store.save(older)
    try? store.save(newer)
    check(store.dictation(older.id) == older, "round trip through SQLite")
    check(store.dictations(matching: "", limit: 10, offset: 0).map(\.id) == [newer.id, older.id], "newest first")
    check(store.lastDictation?.id == newer.id, "last dictation")
    check(store.dictations(matching: "inv", limit: 10, offset: 0).map(\.id) == [older.id], "prefix search")
    check(store.dictations(matching: "anais", limit: 10, offset: 0).map(\.id) == [newer.id], "diacritic-insensitive search")
    let stats = store.statistics(since: Date(timeIntervalSince1970: 1_800_000_050))
    check(stats.dictations == 1 && stats.words == 2 && stats.seconds == 1, "statistics since a date")
    var edited = older
    edited.usesRawText = true
    try? store.save(edited)
    check(store.dictation(older.id)?.usesRawText == true && store.dictations(matching: "", limit: 10, offset: 0).count == 2, "upsert keeps one row")
    check((try? store.pruneDictations(before: Date(timeIntervalSince1970: 1_800_000_050))) == 1 && store.dictation(older.id) == nil, "prune by cutoff")

    // Dictation audio goes after 14 days and the text stays, except audio that is the only record of an untranscribed one.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try? FileManager.default.createDirectory(at: SuperFlowPaths.dictationAudio, withIntermediateDirectories: true)
    func kept(_ name: String, text: String, daysAgo: Double, outcome: DictationOutcome = .formatted) -> Dictation {
        let file = name + ".caf"
        try? Data("audio".utf8).write(to: SuperFlowPaths.dictationAudio.appendingPathComponent(file))
        let row = Dictation(createdAt: now.addingTimeInterval(-daysAgo * 86_400), rawText: text, cleanedText: text, outcome: outcome, audioFile: file)
        try? store.save(row)
        return row
    }
    let old = kept("old", text: "Ship it on Friday.", daysAgo: 20)
    let failed = kept("failed", text: "", daysAgo: 20, outcome: .error)
    let recent = kept("recent", text: "Lunch at noon?", daysAgo: 3)
    let cutoff = RetentionPolicy.dictationAudioCutoff(now: now)
    check((try? store.pruneDictationAudio(before: cutoff)) == 1, "one old file pruned")
    func exists(_ row: Dictation) -> Bool { FileManager.default.fileExists(atPath: SuperFlowPaths.dictationAudio.appendingPathComponent(row.audioFile!).path) }
    check(!exists(old) && store.dictation(old.id)?.audioFile == nil && store.dictation(old.id)?.cleanedText == "Ship it on Friday.",
          "an old dictation keeps its text and loses its audio")
    check(exists(failed) && store.dictation(failed.id)?.audioFile == failed.audioFile, "audio that is the only record stays for Retry transcript")
    check(exists(recent) && store.dictation(recent.id)?.audioFile == recent.audioFile, "recent audio stays")
    check((try? store.pruneDictationAudio(before: cutoff)) == 0, "pruning again finds nothing")
    for row in [failed, recent] { try? store.deleteDictation(row.id) }
    try? store.deleteDictation(old.id)
    try? store.deleteDictation(newer.id)
    check(store.lastDictation == nil, "delete")
    check((try? store.deleteDictation(newer.id)) == nil, "deleting a missing row throws")
}

@MainActor private func storeDictionary() {
    let store = freshStore()
    let entry = DictionaryEntry(phrase: "  Kubernetes ", replacement: nil, isStarred: true)
    try? store.save(entry)
    check(store.dictionary.first?.phrase == "Kubernetes" && store.dictionary.first?.isStarred == true, "phrase trimmed and stored")
    check((try? store.save(DictionaryEntry(phrase: "   "))) == nil, "empty phrase rejected")
    try? store.deleteDictionaryEntry(entry.id)
    check(store.dictionary.isEmpty, "dictionary delete")

    let snippet = Snippet(trigger: "my address", expansion: "1 Main St", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    try? store.save(snippet)
    check(store.snippets == [snippet], "snippet round trip")
    check((try? store.save(Snippet(trigger: "x", expansion: String(repeating: "a", count: Snippet.maxExpansionLength + 1)))) == nil, "too-long expansion rejected")
    try? store.deleteSnippet(snippet.id)
    check(store.snippets.isEmpty, "snippet delete")

    let polish = TransformPrompt(name: "Polish", instruction: "Make it clearer", isBuiltIn: true)
    try? store.save(polish)
    check(store.transforms == [polish], "transform round trip")
    try? store.deleteTransform(polish.id)
    check(store.transforms.isEmpty, "transform delete")
}

@MainActor private func storeMeetings() {
    let store = freshStore()
    let meeting = sampleMeeting()
    try? store.save(meeting)
    check(store.meeting(meeting.id) == meeting, "meeting round trip with segments, speakers and summary")
    check(store.meetings(matching: "roadmap", limit: 10, offset: 0).map(\.id) == [meeting.id], "transcript search")
    check(store.meetings(matching: "colour", limit: 10, offset: 0).map(\.id) == [meeting.id], "notes search")
    check(store.meetings(matching: "nothing-here", limit: 10, offset: 0).isEmpty, "no match")
    let cutoff = Date(timeIntervalSince1970: 1_800_010_000)
    check(store.meetingsWithAudio(before: cutoff).map(\.id) == [meeting.id], "meetings with audio before the cutoff")
    var pruned = meeting
    pruned.audioDeletedAt = Date()
    try? store.save(pruned)
    check(store.meetingsWithAudio(before: cutoff).isEmpty, "audio-deleted meetings drop out")

    let item = ActionItem(meetingID: meeting.id, text: "Send the deck", sortOrder: 1)
    let done = ActionItem(text: "Old task", isCompleted: true, sortOrder: 0)
    try? store.save(item)
    try? store.save(done)
    check(store.actionItems.map(\.id) == [item.id, done.id], "open items first, then by order")
    try? store.deleteMeeting(meeting.id)
    check(store.meeting(meeting.id) == nil && store.actionItems.map(\.id) == [done.id], "deleting a meeting removes its action items")
    try? store.save(sampleMeeting(endedAt: Date(timeIntervalSince1970: 1_700_000_000)))
    check((try? store.pruneMeetings(before: Date(timeIntervalSince1970: 1_750_000_000))) == 1 && store.meetings(matching: "", limit: 10, offset: 0).isEmpty,
          "transcript retention prunes whole meetings")
}

@MainActor private func storeNotes() {
    let store = freshStore()
    var changes: [StoreChange] = []
    let subscription = store.changes.sink { changes.append($0) }
    defer { subscription.cancel() }
    let older = ScratchNote(text: "Groceries\n\nmilk", createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
    let newer = ScratchNote(text: "Plan", createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(timeIntervalSince1970: 5))
    try? store.save(older)
    try? store.save(newer)
    check(store.notes.map(\.id) == [newer.id, older.id] && store.notes.last == older, "notes round trip, newest edit first")
    check(changes == [.notes, .notes], "the change feed reports notes")
    try? store.deleteNote(newer.id)
    check(store.notes.map(\.id) == [older.id], "delete")

    // The notes.json of pre-1.0 builds is imported once and parked in Backup.
    let file = SuperFlowPaths.support.appendingPathComponent("notes-\(UUID().uuidString).json")
    let legacy = ScratchNote(text: "Legacy note", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200))
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    try? encoder.encode([legacy]).write(to: file)
    store.importNotesFile(at: file)
    check(store.notes.contains { $0.id == legacy.id && $0.text == "Legacy note" && $0.updatedAt == legacy.updatedAt }, "notes.json imported")
    check(!FileManager.default.fileExists(atPath: file.path)
              && ((try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.backup.path)) ?? []).contains { $0.hasSuffix(file.lastPathComponent) },
          "the file is parked in Backup")
    store.importNotesFile(at: file)
    check(store.notes.filter { $0.id == legacy.id }.count == 1, "importing again is a no-op")
}

@MainActor private func storeRecovery() {
    let url = SuperFlowPaths.support.appendingPathComponent("damaged-\(UUID().uuidString).sqlite")
    try? Data("not a database".utf8).write(to: url)
    let store = SQLiteStore.open(at: url)
    try? store.save(Snippet(trigger: "t", expansion: "e"))
    check(store.snippets.count == 1, "a damaged file is replaced by a working store")
    let backups = (try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.backup.path)) ?? []
    check(backups.contains { $0.hasSuffix(url.lastPathComponent) }, "the damaged file is kept in Backup")
    check(store.openingNotice?.id == "store.damaged" && !store.isTemporary, "the user is told, and the new store is on disk")
}

/// A file damaged in its later pages: the rows that can still be read (the dictionary, a snippet, a meeting, the
/// first dictations) are carried into the fresh store.
@MainActor private func storeSalvage() {
    let url = SuperFlowPaths.support.appendingPathComponent("salvage-\(UUID().uuidString).sqlite")
    let word = DictionaryEntry(phrase: "Kubernetes", isStarred: true)
    let snippet = Snippet(trigger: "my address", expansion: "1 Main St")
    let meeting = sampleMeeting()
    do {
        let store = SQLiteStore.open(at: url)
        try? store.save(word)
        try? store.save(snippet)
        try? store.save(meeting)
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 60)
        for i in 0..<400 { try? store.save(Dictation(createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(i)), rawText: filler, cleanedText: filler)) }
    }   // closed: the WAL is checkpointed into the file
    guard let handle = try? FileHandle(forUpdating: url), let size = try? handle.seekToEnd(), size > 64 * 1024 else {
        check(false, "the test database was written"); return
    }
    try? handle.seek(toOffset: size - 16 * 1024)
    try? handle.write(contentsOf: Data((0..<8192).map { UInt8(truncatingIfNeeded: $0 &* 37) }))
    try? handle.close()

    let reopened = SQLiteStore.open(at: url)
    check(reopened.openingNotice?.id == "store.damaged", "damage found on open: \(String(describing: reopened.openingNotice?.id))")
    check(reopened.dictionary.map(\.id) == [word.id] && reopened.snippets.map(\.id) == [snippet.id] && reopened.meeting(meeting.id) == meeting,
          "the dictionary, snippets and meetings survive")
    let kept = reopened.dictations(matching: "", limit: 1000, offset: 0).count
    check(kept > 0, "the readable dictations are kept (\(kept) of 400)")
    check(reopened.dictations(matching: "lorem", limit: 5, offset: 0).count == min(kept, 5), "search works on the kept rows")
    let backups = (try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.backup.path)) ?? []
    check(backups.contains { $0.hasSuffix(url.lastPathComponent) }, "the damaged file is kept in Backup")
}

/// A database whose tables don't have the shape this version expects: migration fails, the file goes to Backup, and
/// its rows still come across from their JSON.
@MainActor private func storeMigrationFailure() {
    let url = SuperFlowPaths.support.appendingPathComponent("oldschema-\(UUID().uuidString).sqlite")
    let dictation = Dictation(createdAt: Date(timeIntervalSince1970: 1_800_000_000), rawText: "ship it friday", cleanedText: "Ship it Friday.")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let json = String(decoding: (try? encoder.encode(dictation)) ?? Data(), as: UTF8.self)
    var raw: OpaquePointer?
    sqlite3_open(url.path, &raw)
    sqlite3_exec(raw, "CREATE TABLE dictations (id TEXT PRIMARY KEY, json TEXT NOT NULL)", nil, nil, nil)
    sqlite3_exec(raw, "INSERT INTO dictations VALUES ('\(dictation.id.uuidString)', '\(json.replacingOccurrences(of: "'", with: "''"))')", nil, nil, nil)
    sqlite3_close(raw)

    let store = SQLiteStore.open(at: url)
    check(store.dictation(dictation.id) == dictation, "the row survives the failed migration")
    check(store.openingNotice?.id == "store.damaged" && !store.isTemporary, "a fresh store on disk, and the user is told")
    try? store.save(Snippet(trigger: "t", expansion: "e"))
    check(store.snippets.count == 1, "the fresh store works")
}

/// A folder Super Flow can't write (read-only Application Support): no crash, no data touched, an in-memory session.
@MainActor private func storeUnwritableFolder() {
    let fm = FileManager.default
    let folder = SuperFlowPaths.support.appendingPathComponent("locked-\(UUID().uuidString)", isDirectory: true)
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
    let store = SQLiteStore.open(at: folder.appendingPathComponent("store.sqlite"))
    check(store.isTemporary && store.openingNotice?.id == "store.unavailable", "an in-memory store and a notice")
    let entry = DictionaryEntry(phrase: "Anaïs")
    try? store.save(entry)
    check(store.dictionary.map(\.id) == [entry.id], "the session still works")
    check(((try? fm.contentsOfDirectory(atPath: folder.path)) ?? ["?"]).isEmpty, "nothing was written to the folder")
}

/// Two connections (two copies of the app, or the hub and a helper) writing the same file: every row lands.
@MainActor private func storeConcurrentWriters() {
    let url = SuperFlowPaths.support.appendingPathComponent("shared-\(UUID().uuidString).sqlite")
    let a = SQLiteStore.open(at: url), b = SQLiteStore.open(at: url)
    for i in 0..<50 {
        try? a.save(Dictation(rawText: "a \(i)", cleanedText: "a \(i)"))
        try? b.save(Dictation(rawText: "b \(i)", cleanedText: "b \(i)"))
        try? (i % 2 == 0 ? a : b).save(DictionaryEntry(phrase: "word\(i)"))
    }
    check(a.dictations(matching: "", limit: 500, offset: 0).count == 100 && b.dictations(matching: "", limit: 500, offset: 0).count == 100,
          "both writers' rows are there")
    check(a.dictionary.count == 50 && a.openingNotice == nil && b.openingNotice == nil, "dictionary saved immediately from either side")
}
