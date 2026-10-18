import Foundation
import FlowStore
import SuperFlowCore

// Owned with FlowStore: the SQLite store behind HistoryStoring and MeetingStoring.
func registerFlowStoreTests() {
    SelfTest.cases.append(("FlowStore.dictations", { MainActor.assumeIsolated { storeDictations() } }))
    SelfTest.cases.append(("FlowStore.dictionaryAndSnippets", { MainActor.assumeIsolated { storeDictionary() } }))
    SelfTest.cases.append(("FlowStore.meetings", { MainActor.assumeIsolated { storeMeetings() } }))
    SelfTest.cases.append(("FlowStore.damagedRecovery", { MainActor.assumeIsolated { storeRecovery() } }))
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

@MainActor private func storeRecovery() {
    let url = SuperFlowPaths.support.appendingPathComponent("damaged-\(UUID().uuidString).sqlite")
    try? Data("not a database".utf8).write(to: url)
    let store = SQLiteStore.open(at: url)
    try? store.save(Snippet(trigger: "t", expansion: "e"))
    check(store.snippets.count == 1, "a damaged file is replaced by a working store")
    let backups = (try? FileManager.default.contentsOfDirectory(atPath: SuperFlowPaths.backup.path)) ?? []
    check(backups.contains { $0.hasSuffix(url.lastPathComponent) }, "the damaged file is kept in Backup")
}
