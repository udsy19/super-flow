import AppKit
import Combine
import Carbon.HIToolbox
import SuperFlowCore
import HubKit

func registerHubKitTests() {
    SelfTest.cases.append(("HubKit.meetingRetryOffers", { MainActor.assumeIsolated {
        let words = "We agreed to ship the beta on Friday and Priya sends the pricing proposal tomorrow morning before the review"
        let long = Meeting(title: "Sync", endedAt: Date(), tracks: [AudioTrack(channel: .mic, file: "mic.m4a")],
                           segments: [TranscriptSegment(start: 0, end: 5, text: words), TranscriptSegment(start: 6, end: 9, text: words)])
        check(MeetingRetry.canSummarize(long) && !MeetingRetry.canRetryTranscript(long), "a transcript without notes offers Generate summary")
        var short = long
        short.segments = [TranscriptSegment(start: 0, end: 1, text: "Hello there.")]
        check(!MeetingRetry.canSummarize(short), "too short to summarize: no button")
        var summarized = long
        summarized.summary = MeetingSummary(title: "Sync", summary: "Done.")
        check(!MeetingRetry.canSummarize(summarized), "a summary is there")
        var silent = long
        silent.segments = []
        check(MeetingRetry.canRetryTranscript(silent), "no transcript but audio: Retry transcript")
        silent.audioDeletedAt = Date()
        check(!MeetingRetry.canRetryTranscript(silent), "audio gone: nothing to retry")
    } }))
    SelfTest.cases.append(("HubKit.dates", {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_760_000_000) // a Thursday
        check(HubFormat.dayTitle(now.addingTimeInterval(-60), now: now, calendar: calendar) == "Today", "same day")
        check(HubFormat.dayTitle(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "Yesterday", "previous day")
        check(!["Today", "Yesterday"].contains(HubFormat.dayTitle(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar)),
              "older days are named")
        let stamps = [now, now.addingTimeInterval(-120), now.addingTimeInterval(-86_400), now.addingTimeInterval(-86_500)]
        let groups = HubFormat.groupByDay(stamps.reversed(), date: { $0 }, now: now, calendar: calendar)
        check(groups.map(\.title) == ["Today", "Yesterday"] && groups.map(\.items.count) == [2, 2], "grouped by day, newest day first")
        check(HubFormat.duration(35) == "35 s" && HubFormat.duration(42 * 60) == "42 min" && HubFormat.duration(3900) == "1 h 5 min"
              && HubFormat.duration(7200) == "2 h", "durations")
        check(HubFormat.clock(187) == "03:07" && HubFormat.clock(3765) == "1:02:45", "clock")
        check(HubFormat.wordsPerMinute(words: 300, seconds: 120) == 150 && HubFormat.wordsPerMinute(words: 5, seconds: 2) == nil, "wpm")
    }))

    SelfTest.cases.append(("HubKit.keys", {
        let chord = KeyChord(UInt16(kVK_Space), UInt16(kVK_Command), KeyChord.fn)
        check(HubFormat.keyLabels(chord) == ["Fn", "⌘ Cmd", "Space"], "Fn, modifiers, then keys")
        let map = ShortcutMap.macDefaults
        func assigned(_ outcome: ShortcutEditing.Outcome) -> (ShortcutMap, ShortcutAction?)? {
            if case .assigned(let m, let r) = outcome { return (m, r) } else { return nil }
        }
        check(assigned(ShortcutEditing.assign(KeyChord(UInt16(kVK_ANSI_A)), to: .pushToTalk, in: map)) == nil, "a letter alone is refused")
        check(assigned(ShortcutEditing.assign(KeyChord(UInt16(kVK_Shift), UInt16(kVK_ANSI_A)), to: .pushToTalk, in: map)) == nil,
              "Shift + letter is refused")
        check(assigned(ShortcutEditing.assign(KeyChord(UInt16(kVK_F5)), to: .pushToTalk, in: map)) != nil, "a function key alone is fine")
        check(assigned(ShortcutEditing.assign(KeyChord(UInt16(kVK_Escape)), to: .pushToTalk, in: map)) == nil, "Esc alone only cancels")
        check(assigned(ShortcutEditing.assign(KeyChord(UInt16(kVK_Control), UInt16(kVK_Option), UInt16(kVK_Command), UInt16(kVK_ANSI_K)),
                                              to: .pushToTalk, in: map)) == nil, "at most three keys")
        if let (m, replaced) = assigned(ShortcutEditing.assign(KeyChord(KeyChord.fn, UInt16(kVK_Space)), to: .pushToTalk, in: map)) {
            check(replaced == .handsFree, "taking a chord reports where it came from")
            check(m.chords(for: .pushToTalk) == [KeyChord(KeyChord.fn, UInt16(kVK_Space))] && m.chords(for: .handsFree).isEmpty,
                  "the action keeps only the new chord and the old owner loses it")
        } else { check(false, "Fn + Space can be pushed to talk") }
        if let (m, replaced) = assigned(ShortcutEditing.assign(KeyChord(KeyChord.fn), to: .pushToTalk, in: map)) {
            check(replaced == nil && m == map, "re-recording the same chord changes nothing")
        } else { check(false, "Fn alone is a valid chord") }
        check(ShortcutEditing.chord(held: [KeyChord.fn], key: UInt16(kVK_Space)) == KeyChord(KeyChord.fn, UInt16(kVK_Space)), "held + key")
        check(ShortcutEditing.editableActions(commandMode: false).contains(.commandMode) == false
              && ShortcutEditing.editableActions(commandMode: true).contains(.commandMode), "Command Mode listed only when on")
    }))

    SelfTest.cases.append(("HubKit.routes", {
        check(HubPage.allCases.filter { $0 != .settings }.allSatisfy { HubSection.section(for: $0) != nil }, "every page opens somewhere")
        check(HubSection.section(for: .settings) == nil && HubSection.section(for: .notetaker) == .meetings
              && HubSection.section(for: .scratchpad) == .notes, "page mapping")
    }))

    SelfTest.cases.append(("HubKit.dictionaryAndSnippets", {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            DictionaryEntry(phrase: "Priya", isStarred: true, createdAt: old),
            DictionaryEntry(phrase: "super base", replacement: "Supabase", createdAt: old.addingTimeInterval(10)),
            DictionaryEntry(phrase: "Kubernetes", source: .learned, createdAt: old.addingTimeInterval(20)),
        ]
        check(DictionaryListing.items(entries, filter: .all, sort: "Newest", query: "").map(\.phrase) == ["Kubernetes", "super base", "Priya"],
              "newest first")
        check(DictionaryListing.items(entries, filter: .all, sort: "Alphabetical", query: "").map(\.phrase) == ["Kubernetes", "Priya", "super base"],
              "alphabetical by the written form")
        check(DictionaryListing.items(entries, filter: .all, sort: "Starred", query: "").first?.phrase == "Priya", "starred first")
        check(DictionaryListing.items(entries, filter: .replacements, sort: "Newest", query: "").map(\.phrase) == ["super base"], "replacements")
        check(DictionaryListing.items(entries, filter: .learned, sort: "Newest", query: "").map(\.phrase) == ["Kubernetes"], "learned")
        check(DictionaryListing.items(entries, filter: .all, sort: "Newest", query: "supa").count == 1, "search matches replacements")
        check(DictionaryListing.duplicate("priya", in: entries)?.phrase == "Priya", "duplicates ignore case")
        check(DictionaryListing.duplicate("Priya", in: entries, excluding: entries[0].id) == nil, "editing an entry isn't a duplicate")

        let snippets = [Snippet(trigger: "My calendar link", expansion: "https://cal.com/a")]
        check(SnippetRules.similar(to: "my calendar link!", in: snippets) != nil, "same cue, other case and punctuation")
        check(SnippetRules.similar(to: "calendar link", in: snippets) != nil, "a cue inside another")
        check(SnippetRules.similar(to: "calendar", in: snippets) != nil && SnippetRules.similar(to: "address", in: snippets) == nil, "words")
        check(SnippetRules.similar(to: "My calendar link", in: snippets, excluding: snippets[0].id) == nil, "editing itself")
    }))

    SelfTest.cases.append(("HubKit.meetingExport", {
        let you = Speaker(label: "You", channel: .mic), priya = Speaker(label: "Speaker 1", name: "Priya", channel: .system)
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let item = ActionItem(text: "Send the launch checklist", owner: "Priya", isCompleted: true)
        var meeting = Meeting(title: "Launch / review", startedAt: start, endedAt: start.addingTimeInterval(42 * 60), platform: .zoom,
                              participants: [Participant(name: "Priya")], speakers: [you, priya],
                              segments: [TranscriptSegment(channel: .mic, speakerID: you.id, start: 1, end: 3, text: "Thanks for joining."),
                                         TranscriptSegment(channel: .mic, speakerID: you.id, start: 4, end: 6, text: "Let's start."),
                                         TranscriptSegment(channel: .system, speakerID: priya.id, start: 7, end: 9, text: "Sounds good."),
                                         TranscriptSegment(channel: .system, start: 10, end: 11, text: "partial", isFinal: false)],
                              notes: "Ask about the budget.")
        meeting.summary = MeetingSummary(title: "Launch review", summary: "We agreed the plan.", decisions: ["Ship on Tuesday"],
                                         actionItems: [item], followUps: ["Who owns the blog post?"])
        let groups = TranscriptGroup.make(meeting)
        check(groups.map(\.speaker) == ["You", "Priya"] && groups[0].lines.count == 2 && groups.map(\.ordinal) == [0, 1],
              "consecutive lines by one speaker group; partials are left out")
        let md = MeetingExport.text(meeting, format: .markdown)
        for part in ["# Launch / review", "## Summary", "We agreed the plan.", "## Key decisions\n\n- Ship on Tuesday",
                     "- [x] Send the launch checklist — Priya", "## Follow-ups", "## Notes\n\nAsk about the budget.",
                     "**You** (00:01): Thanks for joining. Let's start.", "**Priya** (00:07): Sounds good.", "42 min", "Zoom"] {
            check(md.contains(part), "Markdown has \(part.debugDescription)")
        }
        check(!md.contains("partial"), "no partial text in the export")
        let overridden = MeetingExport.text(meeting, format: .markdown, actionItems: [ActionItem(text: "Send the deck", owner: "Sam")])
        check(overridden.contains("- [ ] Send the deck — Sam") && !overridden.contains("launch checklist"), "the store's action items replace the summary's")
        check(MeetingExport.fileName(for: meeting, format: .markdown).hasSuffix("Launch   review 2025-10-09.md")
                  && !MeetingExport.fileName(for: meeting, format: .markdown).contains("/"),
              "file name is safe")
        check(HubFormat.audioExpiry(of: Meeting(title: "x", startedAt: start, endedAt: start, tracks: [AudioTrack(channel: .mic, file: "mic.caf")]),
                                    days: 30) == start.addingTimeInterval(30 * 86_400), "audio expiry from the end of the meeting")
        check(HubFormat.audioExpiry(of: meeting, days: 30) == nil, "no audio, no expiry")
    }))

    SelfTest.cases.append(("HubKit.modelSummary", {
        let queue = AutoDownloadPolicy.order(for: ModelCatalog.preset(isAppleSilicon: true, memoryBytes: 16 << 30))
        let speech = queue.first { $0.kind == .asr }!
        var states: [String: ModelState] = [:]
        let notReady = ModelSummary.make(queue: queue, state: { states[$0] ?? .notDownloaded },
                                         status: .downloading(modelID: speech.id, progress: DownloadProgress(bytesReceived: 42, bytesExpected: 100)))
        check(!notReady.speechReady && notReady.fraction == 0.42 && notReady.detail.contains("42 %") && !notReady.isComplete,
              "speech downloading: progress, not ready")
        for m in queue { states[m.id] = .installed }
        let done = ModelSummary.make(queue: queue, state: { states[$0] ?? .notDownloaded }, status: .upToDate)
        check(done.isComplete && done.speechReady && done.fraction == nil, "everything installed")
        states[queue.last!.id] = .notDownloaded
        let waiting = ModelSummary.make(queue: queue, state: { states[$0] ?? .notDownloaded }, status: .waitingForNetwork)
        check(waiting.speechReady && !waiting.isComplete && waiting.detail == HubFormat.autoDownloadText(.waitingForNetwork) { $0 },
              "waiting says why, never asks")
        check(HubFormat.autoDownloadText(.waitingForDisk(freeBytes: 1 << 30)) { $0 }.contains("free"), "disk wait names the free space")
    }))

    SelfTest.cases.append(("HubKit.notesStore", { MainActor.assumeIsolated { hubNotesStore() } }))
    SelfTest.cases.append(("HubKit.renders", { MainActor.assumeIsolated { hubRenders() } }))
}

@MainActor private func hubNotesStore() {
    let history = FakeHubHistory()
    let store = NotesStore(history: history)
    let note = store.create()
    store.update(note.id, text: "Groceries\n\nmilk\neggs")
    check(store.notes.first?.title == "Groceries" && store.notes.first?.preview == "milk eggs", "title and preview")
    check(history.notes.map(\.text) == ["Groceries\n\nmilk\neggs"], "notes are rows in the store")
    let reloaded = NotesStore(history: history)
    check(reloaded.notes.map(\.text) == ["Groceries\n\nmilk\neggs"], "a new view reads the store")
    reloaded.delete(note.id)
    check(NotesStore(history: history).notes.isEmpty, "delete reaches the store")
    let memory = NotesStore(history: nil)
    memory.update(memory.create().id, text: "Offline")
    check(memory.sorted.first?.title == "Offline", "without a store the notes live in memory")
    check(ScratchNote(text: "  \n").title == "New note", "an empty note's title")
}

/// Every screen, offscreen, with fake stores; PNGs go to $SUPERFLOW_RENDER_DIR when set.
@MainActor private func hubRenders() {
    let saved = (Services.history, Services.meetings, Services.models)
    let history = FakeHubHistory(), models = FakeHubModels()
    Services.history = history
    Services.meetings = history
    Services.models = models
    defer { Services.history = saved.0; Services.meetings = saved.1; Services.models = saved.2 }
    let notes = NotesStore(history: nil)
    for text in ["Lisbon trip\n\nBook flights before Friday. Ask Marco about the apartment near Alfama.",
                 "Q4 planning\n\nThree bets: importer, offline mode, faster onboarding.",
                 "Gift ideas\n\nSam: film camera, a good notebook."] {
        notes.update(notes.create().id, text: text)
    }
    let out = ProcessInfo.processInfo.environment["SUPERFLOW_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
    if let out { try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }

    func render(_ screen: HubRender.Screen, dark: Bool = false, name: String? = nil) {
        guard let rep = HubRender.image(screen, dark: dark, notes: notes) else { check(false, "\(screen) rendered"); return }
        check(rep.pixelsWide >= 1140 && rep.pixelsHigh >= 750, "\(screen) has the window size")
        check(distinctColours(rep) > 12, "\(screen) drew something")
        if let out, let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: out.appendingPathComponent("\(name ?? screen.rawValue).png"))
        }
    }
    for screen in HubRender.Screen.allCases { render(screen) }
    for pane in SettingsPane.allCases {
        guard let rep = HubRender.settingsPage(pane) else { check(false, "\(pane) page rendered"); continue }
        check(rep.pixelsHigh > 300 && distinctColours(rep) > 8, "\(pane) page drew something")
        if let out, let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: out.appendingPathComponent("page-\(pane.rawValue).png"))
        }
    }
    render(.home, dark: true, name: "home-dark")
    render(.meetingSummary, dark: true, name: "meetingSummary-dark")
    render(.settingsModels, dark: true, name: "settingsModels-dark")
    models.speechReady = false
    render(.home, name: "home-downloading")
    render(.onboardingTryIt, name: "onboardingTryIt-downloading")
    history.reset()
    render(.home, name: "home-empty")
    render(.meetings, name: "meetings-empty")
}

/// How many distinct colours a sample of pixels has: a blank render has one or two.
@MainActor private func distinctColours(_ rep: NSBitmapImageRep) -> Int {
    var seen: Set<UInt32> = []
    for y in stride(from: 0, to: rep.pixelsHigh, by: 23) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 17) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            seen.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
        }
    }
    return seen.count
}

// MARK: - Fakes (the contracts only)

@MainActor
private final class FakeHubHistory: HistoryStoring, MeetingStoring {
    var all: [Dictation] = []
    var dictionary: [DictionaryEntry] = []
    var snippets: [Snippet] = []
    var transforms: [TransformPrompt] = []
    var notes: [ScratchNote] = []
    var meetingList: [Meeting] = []
    var actionItems: [ActionItem] = []
    let subject = PassthroughSubject<StoreChange, Never>()
    var changes: AnyPublisher<StoreChange, Never> { subject.eraseToAnyPublisher() }

    init() { seed() }

    func reset() {
        all = []; meetingList = []; actionItems = []
        subject.send(.reloaded)
    }

    private func seed() {
        let now = Date()
        let day: TimeInterval = 86_400
        func app(_ name: String, _ id: String) -> AppRecord { AppRecord(bundleID: id, name: name) }
        let slack = app("Slack", "com.tinyspeck.slackmacgap"), mail = app("Mail", "com.apple.mail"), notes = app("Notes", "com.apple.Notes")
        let cursor = app("Cursor", "com.todesktop.230313mzl4w4u92"), messages = app("Messages", "com.apple.MobileSMS")
        func d(_ ago: TimeInterval, _ text: String, _ app: AppRecord, raw: String? = nil, outcome: DictationOutcome = .formatted) -> Dictation {
            Dictation(createdAt: now.addingTimeInterval(-ago), rawText: raw ?? text, cleanedText: text, app: app,
                      duration: Double(Dictation.countWords(text)) / 2.4, outcome: outcome)
        }
        all = [
            d(4 * 60, "Can we push the design review to Thursday afternoon? I'd like Priya's feedback on the onboarding flow first.", slack,
              raw: "um can we push the design review to thursday afternoon I'd like priya's feedback on the onboarding flow first"),
            d(31 * 60, "Thanks for sending the contract over. I've signed it and attached a copy for your records.", mail),
            d(52 * 60, "Remind me to book the flights to Lisbon before Friday.", notes),
            d(day + 3600, "Quick update for the team: the new importer shipped, the sync bug is fixed, and the release notes are in the doc.", slack),
            d(day + 2 * 3600, "", slack, outcome: .dismissed),
            d(day + 5 * 3600, "Write a function that takes a list of meetings and returns the ones longer than an hour.", cursor),
            d(3 * day, "Happy birthday Sam! Hope you have a great one, let's celebrate this weekend.", messages),
        ]
        let base = now.addingTimeInterval(-30 * day)
        dictionary = [
            DictionaryEntry(phrase: "Priya", isStarred: true, createdAt: base),
            DictionaryEntry(phrase: "super base", replacement: "Supabase", createdAt: base.addingTimeInterval(10)),
            DictionaryEntry(phrase: "Kubernetes", source: .learned, createdAt: base.addingTimeInterval(20)),
            DictionaryEntry(phrase: "quen", replacement: "Qwen", createdAt: base.addingTimeInterval(30)),
            DictionaryEntry(phrase: "Anaïs", createdAt: base.addingTimeInterval(40)),
            DictionaryEntry(phrase: "SwiftPM", source: .learned, createdAt: base.addingTimeInterval(50)),
            DictionaryEntry(phrase: "OKRs", createdAt: base.addingTimeInterval(60)),
        ]
        snippets = [
            Snippet(trigger: "my calendar link", expansion: "https://cal.com/alex/30min", createdAt: base),
            Snippet(trigger: "intro email", expansion: "Hi there, I'm Alex and I run product at Northwind. Would you have 20 minutes this week? I'd love to show you what we're building.",
                    createdAt: base.addingTimeInterval(10)),
            Snippet(trigger: "home address", expansion: "221 Harbour Street, Apt 4B, Brooklyn, NY 11201", createdAt: base.addingTimeInterval(20)),
            Snippet(trigger: "sign off", expansion: "Thanks,\nAlex", createdAt: base.addingTimeInterval(30)),
        ]

        let you = Speaker(label: "You", channel: .mic)
        let priya = Speaker(label: "Speaker 1", name: "Priya Shah", channel: .system)
        let marcus = Speaker(label: "Speaker 2", name: "Marcus Lee", channel: .system)
        let lines: [(Speaker, String)] = [
            (you, "Thanks for joining, both of you."), (you, "I want one last pass before we announce on Tuesday."),
            (priya, "Sounds good. Engineering is in good shape."), (priya, "The importer passed the load test last night."),
            (marcus, "Marketing still needs the final screenshots. Can we freeze the UI by Friday?"),
            (you, "Yes, let's freeze Friday at noon."), (priya, "I'll send the launch checklist today."),
            (marcus, "One open question: who writes the blog post?"),
        ]
        var t: TimeInterval = 2
        let segments = lines.map { speaker, text -> TranscriptSegment in
            defer { t += 9 }
            return TranscriptSegment(channel: speaker.channel, speakerID: speaker.id, start: t, end: t + 7, text: text)
        }
        let launchStart = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(-3600)
        let launch = Meeting(
            title: "Product launch review", startedAt: launchStart, endedAt: launchStart.addingTimeInterval(42 * 60), platform: .zoom,
            participants: [Participant(name: "Priya Shah"), Participant(name: "Marcus Lee"), Participant(name: "Alex Kim")],
            speakers: [you, priya, marcus],
            tracks: [AudioTrack(channel: .mic, file: "mic.caf", duration: 2520), AudioTrack(channel: .system, file: "system.caf", duration: 2520)],
            segments: segments, notes: "Check the pricing page copy before Tuesday.",
            summary: MeetingSummary(title: "Product launch review",
                                    summary: "The team reviewed launch readiness for Tuesday. Engineering is on track and the importer passed its load test. Marketing needs final screenshots, so the UI freezes on Friday at noon.",
                                    decisions: ["Announce the launch on Tuesday.", "Freeze the UI on Friday at noon."],
                                    actionItems: [], followUps: ["Who writes the launch blog post?"], modelID: ModelCatalog.qwen35_4B.id))
        let sync = Meeting(title: "Weekly design sync", startedAt: now.addingTimeInterval(-day - 5 * 3600),
                           endedAt: now.addingTimeInterval(-day - 5 * 3600 + 1800), platform: .googleMeet,
                           participants: [Participant(name: "Priya Shah"), Participant(name: "Jo Park")],
                           tracks: [AudioTrack(channel: .mic, file: "mic.caf")], segments: Array(segments.prefix(3)),
                           summary: MeetingSummary(title: "Weekly design sync", summary: "Reviewed the new settings layout."),
                           audioDeletedAt: now.addingTimeInterval(-3600))
        let hiring = Meeting(title: "Hiring plan notes", startedAt: now.addingTimeInterval(-3 * day), endedAt: now.addingTimeInterval(-3 * day + 900),
                             segments: Array(segments.suffix(2)))
        meetingList = [launch, sync, hiring]
        actionItems = [
            ActionItem(meetingID: launch.id, text: "Send the launch checklist", owner: "Priya", due: now.addingTimeInterval(day), sortOrder: 0),
            ActionItem(meetingID: launch.id, text: "Deliver final screenshots to marketing", owner: "Alex", due: now.addingTimeInterval(3 * day), sortOrder: 1),
            ActionItem(meetingID: launch.id, text: "Book the launch review room", isCompleted: true, sortOrder: 2),
        ]
    }

    // HistoryStoring
    func dictation(_ id: UUID) -> Dictation? { all.first { $0.id == id } }
    func dictations(matching query: String, limit: Int, offset: Int) -> [Dictation] {
        let q = query.lowercased()
        return Array(all.filter { q.isEmpty || $0.displayText.lowercased().contains(q) }.sorted { $0.createdAt > $1.createdAt }.dropFirst(offset).prefix(limit))
    }
    var lastDictation: Dictation? { all.max { $0.createdAt < $1.createdAt } }
    func save(_ dictation: Dictation) throws { all.removeAll { $0.id == dictation.id }; all.append(dictation); subject.send(.dictations) }
    func deleteDictation(_ id: UUID) throws { all.removeAll { $0.id == id }; subject.send(.dictations) }
    func pruneDictations(before cutoff: Date) throws -> Int { 0 }
    func eraseDictations() throws -> Int { defer { all = [] }; return all.count }
    func statistics(since: Date) -> (dictations: Int, words: Int, seconds: TimeInterval) {
        let items = all.filter { $0.createdAt >= since && $0.wordCount > 0 }
        return (items.count, items.reduce(0) { $0 + $1.wordCount }, items.reduce(0) { $0 + $1.duration })
    }
    func save(_ entry: DictionaryEntry) throws { dictionary.removeAll { $0.id == entry.id }; dictionary.append(entry); subject.send(.dictionary) }
    func deleteDictionaryEntry(_ id: UUID) throws { dictionary.removeAll { $0.id == id }; subject.send(.dictionary) }
    func save(_ snippet: Snippet) throws { snippets.removeAll { $0.id == snippet.id }; snippets.append(snippet); subject.send(.snippets) }
    func deleteSnippet(_ id: UUID) throws { snippets.removeAll { $0.id == id }; subject.send(.snippets) }
    func save(_ transform: TransformPrompt) throws {}
    func deleteTransform(_ id: UUID) throws {}
    func save(_ note: ScratchNote) throws { notes.removeAll { $0.id == note.id }; notes.append(note); subject.send(.notes) }
    func deleteNote(_ id: UUID) throws { notes.removeAll { $0.id == id }; subject.send(.notes) }

    // MeetingStoring
    func meeting(_ id: UUID) -> Meeting? { meetingList.first { $0.id == id } }
    func meetings(matching query: String, limit: Int, offset: Int) -> [Meeting] {
        Array(meetingList.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.startedAt > $1.startedAt }.dropFirst(offset).prefix(limit))
    }
    func save(_ meeting: Meeting) throws { meetingList.removeAll { $0.id == meeting.id }; meetingList.append(meeting); subject.send(.meetings) }
    func deleteMeeting(_ id: UUID) throws { meetingList.removeAll { $0.id == id }; subject.send(.meetings) }
    func meetingsWithAudio(before cutoff: Date) -> [Meeting] { [] }
    func pruneMeetings(before cutoff: Date) throws -> Int { 0 }
    func save(_ item: ActionItem) throws { actionItems.removeAll { $0.id == item.id }; actionItems.append(item); subject.send(.actionItems) }
    func deleteActionItem(_ id: UUID) throws { actionItems.removeAll { $0.id == id }; subject.send(.actionItems) }
}

@MainActor
private final class FakeHubModels: ModelManaging {
    var speechReady = true
    let subject = PassthroughSubject<String, Never>()
    var catalog: [ModelDescriptor] { ModelCatalog.all }
    var changes: AnyPublisher<String, Never> { subject.eraseToAnyPublisher() }
    var diskUsage: Int64 { ModelCatalog.parakeetV3.bytes + ModelCatalog.whisperBase.bytes }

    func state(of id: String) -> ModelState {
        switch id {
        case ModelCatalog.parakeetV3.id: speechReady ? .installed : .downloading(fraction: 0.63)
        case ModelCatalog.whisperBase.id, ModelCatalog.sileroVAD.id: .installed
        case ModelCatalog.qwen35_2B.id: speechReady ? .downloading(fraction: 0.42) : .notDownloaded
        case ModelCatalog.whisperSmall.id: .damaged
        default: .notDownloaded
        }
    }
    var autoDownloadStatus: AutoDownloadStatus {
        let model = speechReady ? ModelCatalog.qwen35_2B : ModelCatalog.parakeetV3
        let fraction = speechReady ? 0.42 : 0.63
        return .downloading(modelID: model.id, progress: DownloadProgress(bytesReceived: Int64(Double(model.bytes) * fraction),
                                                                         bytesExpected: model.bytes, rate: 6_000_000))
    }
    func location(of id: String) -> URL? { nil }
    func download(_ id: String) -> AsyncThrowingStream<DownloadProgress, Error> { AsyncThrowingStream { $0.finish() } }
    func pause(_ id: String) {}
    func delete(_ id: String) throws {}
    func importModel(_ id: String, from file: URL) async throws {}
    func startAutomaticDownloads() {}
    func setUserBusy(_ busy: Bool) {}
    func readiness(of id: String) -> Double? { nil }
}
