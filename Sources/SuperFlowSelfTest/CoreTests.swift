import AppKit
import Carbon.HIToolbox
import SuperFlowCore

// Owned with SuperFlowCore: the contracts every module builds on.
func registerCoreTests() {
    SelfTest.cases.append(("Core.modelCodable", { coreModelCodable() }))
    SelfTest.cases.append(("Core.shortcuts", { coreShortcuts() }))
    SelfTest.cases.append(("Core.settingsDefaults", { coreSettingsDefaults() }))
    SelfTest.cases.append(("Core.retention", { coreRetention() }))
    SelfTest.cases.append(("Core.themeMetrics", { coreThemeMetrics() }))
    SelfTest.cases.append(("Core.appLists", { coreAppLists() }))
    SelfTest.cases.append(("Core.modelCatalog", { coreModelCatalog() }))
    SelfTest.cases.append(("Core.contractAdditions", { coreContractAdditions() }))
}

private func roundTrip<T: Codable & Equatable>(_ value: T) -> Bool {
    guard let data = try? JSONEncoder().encode(value), let back = try? JSONDecoder().decode(T.self, from: data) else { return false }
    return back == value
}

func sampleMeeting(id: UUID = UUID(), endedAt: Date? = Date(timeIntervalSince1970: 1_800_003_600)) -> Meeting {
    let you = Speaker(label: "You", name: "Udaya", channel: .mic)
    let them = Speaker(label: "Speaker 1", channel: .system)
    let item = ActionItem(meetingID: id, text: "Send the deck", owner: "Udaya", due: Date(timeIntervalSince1970: 1_800_090_000))
    return Meeting(
        id: id, title: "Design review", startedAt: Date(timeIntervalSince1970: 1_800_000_000), endedAt: endedAt, platform: .zoom,
        calendarEventID: "evt-1", participants: [Participant(name: "Priya", email: "priya@example.com")], speakers: [you, them],
        tracks: [AudioTrack(channel: .mic, file: "mic.caf", duration: 3600, byteSize: 1_000_000),
                 AudioTrack(channel: .system, file: "system.caf", duration: 3600, byteSize: 1_000_000)],
        segments: [TranscriptSegment(channel: .mic, speakerID: you.id, start: 0, end: 2.5, text: "Let's start with the roadmap."),
                   TranscriptSegment(channel: .system, speakerID: them.id, start: 3, end: 6, text: "We ship Thursday.")],
        notes: "Remember the colour tokens.",
        summary: MeetingSummary(title: "Design review", summary: "Roadmap agreed.", decisions: ["Ship Thursday"], actionItems: [item],
                                followUps: ["Confirm with Priya"], generatedAt: Date(timeIntervalSince1970: 1_800_004_000),
                                modelID: ModelCatalog.qwen35_4B.id))
}

private func coreModelCodable() {
    let app = AppRecord(bundleID: "com.apple.mail", name: "Mail", url: nil, windowTitle: "Inbox", category: .email)
    let dictation = Dictation(rawText: "um hello there", cleanedText: "Hello there.", editedText: "Hello there!", app: app, language: "en",
                              duration: 1.8, mode: .pushToTalk, source: .keyboard, outcome: .formatted, audioFile: "a.caf")
    check(roundTrip(dictation), "Dictation with every field")
    check(dictation.wordCount == 2 && dictation.displayText == "Hello there.", "word count and display text")
    var raw = dictation
    raw.usesRawText = true
    check(raw.displayText == "um hello there", "Undo AI edit shows the raw text")
    check(roundTrip(Dictation(rawText: "", cleanedText: "", outcome: .empty)), "Dictation with only defaults")

    check(roundTrip(DictionaryEntry(phrase: "Anaïs", replacement: "Anais", isStarred: true, source: .learned, lastUsedAt: Date(timeIntervalSince1970: 5), useCount: 3)),
          "DictionaryEntry")
    check(roundTrip(Snippet(trigger: "my address", expansion: "1 Main St")), "Snippet")
    let style = StyleProfile(styles: [.personal: .veryCasual, .email: .excited], cleanupLevel: .medium)
    check(roundTrip(style) && style.style(for: .work) == .formal && style.style(for: .personal) == .veryCasual, "StyleProfile with fallbacks")
    check(StyleProfile.default.style(for: .personal) == .casual && StyleProfile.default.style(for: .email) == .formal, "default styles per category")
    check(WritingStyle.options(for: .personal) == [.formal, .casual, .veryCasual] && WritingStyle.options(for: .work) == [.formal, .casual, .excited],
          "style options per category")
    check(roundTrip(TransformPrompt(name: "Boss Mode", instruction: "Rewrite", shortcut: KeyChord(UInt16(kVK_Option), UInt16(kVK_ANSI_2)))),
          "TransformPrompt with a chord")

    let meeting = sampleMeeting()
    check(roundTrip(meeting), "Meeting with every field")
    check(meeting.duration == 3600 && meeting.hasAudio, "duration and audio")
    check(meeting.transcriptText == "Udaya: Let's start with the roadmap.\nSpeaker 1: We ship Thursday.", "transcript text uses speaker names")
    var noAudio = meeting
    noAudio.audioDeletedAt = Date()
    check(!noAudio.hasAudio, "audio deleted")
    check(roundTrip(Meeting(title: "Untitled note")), "Meeting with only defaults")
    check(roundTrip(CalendarEvent(id: "e", title: "Standup", start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2),
                                  joinURL: URL(string: "https://zoom.us/j/1"), platform: .zoom)), "CalendarEvent")
    check(roundTrip(ModelCatalog.parakeetV3) && roundTrip(ModelCatalog.qwen35_2B), "ModelDescriptor")
    check(roundTrip(AppContext(app: app, textBefore: "Hi ", selectedText: "x", isEditable: true, nearbyWords: ["Kubernetes"])), "AppContext")
    check(DictationStatus.listening.isRecording && DictationStatus.processing.isBusy && DictationStatus.error.canStart && !DictationStatus.listening.canStart,
          "status machine predicates")
    check(DismissReason.otherShortcut.rawValue == "other_shortcut" && DictationOutcome.rawTranscript.rawValue == "raw_transcript", "exact reason values")
    check(DictationLimits.maxSessionDuration == 1200 && DictationLimits.debounceWindow == 0.5, "limits")
    check(AudioClip(samples: [Float](repeating: 0, count: 16_000)).duration == 1, "clip duration at 16 kHz")
    check(SpeechPriority.dictation > SpeechPriority.meeting, "dictation pre-empts meetings")
}

private func coreShortcuts() {
    let fnSpace = KeyChord(UInt16(kVK_Space), KeyChord.fn)
    check(fnSpace.stringValue == "49+63" && KeyChord(string: "63+49") == fnSpace, "chord codec sorts codes")
    check(KeyChord(string: "") == nil && KeyChord(string: "a+b") == nil, "malformed chords rejected")
    check(fnSpace.displayString == "Fn + Space", "display order Fn first")
    check(KeyChord(UInt16(kVK_ANSI_V), UInt16(kVK_Command), UInt16(kVK_Control)).displayString == "⌃ Ctrl + ⌘ Cmd + V", "modifier order then key")
    check(KeyChord(KeyChord.fn).hasModifierOrMouse && KeyChord(KeyChord.mouseButton(4)).hasModifierOrMouse && !KeyChord(UInt16(kVK_ANSI_A)).hasModifierOrMouse,
          "modifier / mouse rule")
    check(KeyChord.label(KeyChord.mouseButton(4)) == "Mouse 4" && KeyChord.label(KeyChord.mouseMiddle) == "Middle Click", "mouse labels")
    check(roundTrip(fnSpace), "KeyChord codable as a string")

    let map = ShortcutMap.macDefaults
    check(map.bindings[KeyChord(KeyChord.fn)] == .pushToTalk && map.bindings[fnSpace] == .handsFree, "Fn and Fn+Space defaults")
    check(map.bindings[KeyChord(KeyChord.fn, UInt16(kVK_Control))] == .commandMode, "Fn+Ctrl command mode")
    check(map.chords(for: .notetaker) == [KeyChord(UInt16(kVK_Option), UInt16(kVK_ANSI_M))] && map.doubleTapFnForHandsFree, "⌥M and double-Fn")
    check(map.chords(for: .pasteLastText).first?.displayString == "⌃ Ctrl + ⌘ Cmd + V", "paste last ⌃⌘V")
    check(roundTrip(map), "ShortcutMap codable")
    if let data = try? JSONEncoder().encode(map), let text = String(data: data, encoding: .utf8) {
        check(text.contains("\"49+63\":\"popo\""), "stored as chord-string → action")
    } else { check(false, "ShortcutMap encodes") }
    check(ShortcutMap.noFnKeyboardDefaults.bindings[KeyChord(UInt16(kVK_Control), UInt16(kVK_Space))] == .pushToTalk, "no-Fn alternative")
}

private func coreSettingsDefaults() {
    check(Defaults[.shortcuts] == .macDefaults, "shortcuts default")
    check(Defaults[.openAtLogin] && Defaults[.installUpdates] && Defaults[.autoDownloadModels], "launch at login, updates and model downloads on")
    check(Defaults[.hideFlowBarPermanently] == false && Defaults[.flowBarEdge] == .bottom, "Flow Bar visible at the bottom")
    check(Defaults[.hideAppInDock] == false, "Dock app")
    check(Defaults[.enableSounds] && !Defaults[.shouldMuteAudio] && !Defaults[.shouldPauseAudio], "sound defaults")
    check(Defaults[.shouldAutoLearnWords] && Defaults[.useAxContext] && Defaults[.styleDetectionEnabled], "learning and context on")
    check(!Defaults[.commandModeEnabled] && !Defaults[.pressEnterCommandEnabled] && !Defaults[.stackedMessagesEnabled] && !Defaults[.creatorMode],
          "experimental off")
    check(Defaults[.styleProfile].cleanupLevel == .light && Defaults[.defaultTranscriptionFormat] == .aiFormatting, "Light cleanup, AI formatting")
    check(Defaults[.localDataPolicy] == .store && Defaults[.meetingTranscriptRetentionDays] == RetentionPolicy.keepForever, "store forever")
    check(Defaults[.meetingAudioRetentionDays] == 30, "meeting audio kept 30 days (owner decision)")
    check(Defaults[.meetingDetection] == .notify && !Defaults[.notetakerAutoStartEnabled] && Defaults[.notetakerAutoEndEnabled], "detect, ask, auto-end")
    check(Defaults[.notetakerMaxRecordingLength] == 7200 && Defaults[.notetakerLiveTranscriptEnabled] && Defaults[.notetakerTripleTapShortcutEnabled],
          "notetaker defaults")
    check(Defaults[.asrModelID] == ModelCatalog.parakeetV3.id && Defaults[.cleanupModelID] == ModelCatalog.qwen35_2B.id
          && Defaults[.notesModelID] == ModelCatalog.qwen35_4B.id, "model defaults")
    check(Defaults[.insertionMethod] == .paste && Defaults[.restoreClipboardAfterPaste], "insertion defaults")
    check(Defaults[.theme] == .light && !Defaults[.isOnboardingCompleted], "theme and onboarding")
    check(Defaults[.selectedLanguages].count == 1 && !Defaults[.autoDetectLanguage], "one language, no auto-detect")

    Defaults[.flowBarEdge] = .left
    Defaults[.styleProfile] = StyleProfile(cleanupLevel: .high)
    Defaults[.cleanupModelID] = nil
    check(Defaults[.flowBarEdge] == .left && Defaults[.styleProfile].cleanupLevel == .high && Defaults[.cleanupModelID] == nil, "writes read back")
    Defaults.reset(.flowBarEdge); Defaults.reset(.styleProfile); Defaults.reset(.cleanupModelID)
    check(Defaults[.cleanupModelID] == ModelCatalog.qwen35_2B.id, "reset restores the default")
    check(SettingsOptions.transcriptRetentionDays == [0, 1, 7, 30, 90, 180, 365] && SettingsOptions.maxRecordingLengths == [1800, 3600, 7200, 10800],
          "settings options")
}

private func coreRetention() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    check(RetentionPolicy.cutoff(days: 0, now: now) == nil && RetentionPolicy.cutoff(days: 30, now: now) == now.addingTimeInterval(-30 * 86_400), "cutoff")
    check(RetentionPolicy.dictationCutoff(policy: .store, now: now) == nil, "store keeps everything")
    check(RetentionPolicy.dictationCutoff(policy: .autoDelete24h, now: now) == now.addingTimeInterval(-86_400), "24 h policy")
    check(RetentionPolicy.dictationCutoff(policy: .never, now: now) == now, "never keeps nothing")
    check(RetentionPolicy.dictationAudioCutoff(now: now) == now.addingTimeInterval(-14 * 86_400), "dictation audio 14 days")

    let ended31 = sampleMeeting(endedAt: now.addingTimeInterval(-31 * 86_400))
    let ended29 = sampleMeeting(endedAt: now.addingTimeInterval(-29 * 86_400))
    check(RetentionPolicy.shouldDeleteAudio(of: ended31, audioDays: 30, now: now), "audio older than 30 days goes")
    check(!RetentionPolicy.shouldDeleteAudio(of: ended29, audioDays: 30, now: now), "29 days stays")
    check(!RetentionPolicy.shouldDeleteAudio(of: ended31, audioDays: 0, now: now), "never delete audio")
    var deleted = ended31
    deleted.audioDeletedAt = now
    check(!RetentionPolicy.shouldDeleteAudio(of: deleted, audioDays: 30, now: now), "already deleted")
    check(!RetentionPolicy.shouldDeleteAudio(of: sampleMeeting(endedAt: nil), audioDays: 30, now: now), "a running meeting is never pruned")
    var untranscribed = ended31
    untranscribed.segments = []
    check(!RetentionPolicy.shouldDeleteAudio(of: untranscribed, audioDays: 30, now: now), "audio that is a meeting's only record is kept")
    check(!RetentionPolicy.shouldDeleteMeeting(ended31, transcriptDays: 0, now: now), "transcripts kept forever by default")
    check(RetentionPolicy.shouldDeleteMeeting(ended31, transcriptDays: 7, now: now) && !RetentionPolicy.shouldDeleteMeeting(ended29, transcriptDays: 30, now: now),
          "transcript retention")
    check(RetentionPolicy.label(days: 0) == "Never delete" && RetentionPolicy.label(days: 1) == "1 day" && RetentionPolicy.label(days: 30) == "30 days"
          && RetentionPolicy.label(days: 365) == "1 year", "labels")
}

private func coreThemeMetrics() {
    check(NSColor(hex: "#10b981").hexString == "#10B981" && NSColor(hex: "zzz").hexString == "#FF00FF", "hex colours")
    check(SFMetrics.FlowBar.radius == 22.5 && SFMetrics.FlowBar.height == 30 && SFMetrics.FlowBar.bottomWindowSize == NSSize(width: 512, height: 614),
          "Flow Bar geometry")
    check(SFMetrics.FlowBar.restingSize == NSSize(width: 40, height: 8) && SFMetrics.FlowBar.readySize == NSSize(width: 50, height: 30)
          && SFMetrics.FlowBar.handsFreeSize == NSSize(width: 102.5, height: 30) && SFMetrics.FlowBar.pushToTalkSize.width == 73, "pill sizes per state")
    check(SFMetrics.FlowBar.meetingBorderWidth == 2 && SFMetrics.FlowBar.meetingBorder.hexString == "#10B981", "meeting border")
    check(SFMetrics.Waveform.barCount == 10 && SFMetrics.Waveform.weights.count == 10, "ten bars")
    let w = SFMetrics.Waveform.weights
    check(abs(w[0] - 0.578) < 0.001 && abs(w[4] - 0.995) < 0.001 && w[0] == w[9] && w[4] == w[5], "bar weights centre-weighted")
    check(SFMetrics.Waveform.scale(level: 1, gain: 5) == 5 && SFMetrics.Waveform.scale(level: 0, gain: 5) == 1, "audio scale 1…5")
    check(SFMetrics.Waveform.level(dB: -40, floor: -60) == 1 && SFMetrics.Waveform.level(dB: -70, floor: -60) == 0 && SFMetrics.Waveform.level(dB: -50, floor: -60) == 0.5,
          "level from dB")
    check(SFMotion.snapDuration == 0.1 && SFMotion.springMorphDuration == 0.42 && SFMotion.meetingSizeDuration == 0.16, "timings")
    check(SFMetrics.Hub.defaultSize == NSSize(width: 1350, height: 850) && SFMetrics.Hub.minimumSize == NSSize(width: 1140, height: 750)
          && SFMetrics.Settings.size == NSSize(width: 960, height: 640), "hub and settings sizes")
    check(SFFont.size(.sm) == (15, 20) && SFFont.heading(1).pointSize == 32 && SFFont.display(4).pointSize == 28, "type scale")
    check(SFMetrics.spacing == [0, 2, 4, 8, 12, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112], "spacing scale")
    check(SFColor.background.hexString == "#FCFCFB" || SFColor.background.hexString == "#1A1A1A", "semantic colour resolves")
}

private func coreAppLists() {
    check(AppLists.category(bundleID: "com.apple.MobileSMS") == .personalMessaging, "Messages is personal")
    check(AppLists.category(bundleID: "com.tinyspeck.slackmacgap") == .work, "Slack is work")
    check(AppLists.category(bundleID: "com.apple.mail") == .email, "Mail is email")
    check(AppLists.category(bundleID: "com.apple.Terminal") == .terminal && AppLists.category(bundleID: "dev.warp.Warp-Stable") == .terminal, "terminals")
    check(AppLists.category(bundleID: "com.todesktop.230313mzl4w4u92") == .ai, "Cursor is ai")
    check(AppLists.category(bundleID: "com.google.Chrome", url: "https://mail.google.com/mail/u/0/") == .email, "Gmail in a browser")
    check(AppLists.category(bundleID: "com.apple.Safari", url: "https://web.whatsapp.com/") == .personalMessaging, "WhatsApp web")
    check(AppLists.category(bundleID: "com.apple.Safari", url: "https://example.com") == .other && AppLists.category(bundleID: "com.unknown") == .other, "unknown")
    check(AppCategory.personalMessaging.styleCategory == .personal && AppCategory.terminal.styleCategory == .other, "style category mapping")
    check(AppLists.conferencingApps["us.zoom.xos"] == .zoom && AppLists.platform(forJoinURL: URL(string: "https://meet.google.com/abc-defg-hij")!) == .googleMeet
          && AppLists.platform(forJoinURL: URL(string: "https://us02web.zoom.us/j/123")!) == .zoom && AppLists.platform(forJoinURL: URL(string: "https://example.com")!) == nil,
          "meeting platforms")
}

private func coreContractAdditions() {
    // A meeting row written before markers existed still decodes.
    let old = #"{"id":"6A0585D3-6ADB-4690-BA61-AD0FD3D70BDB","title":"Old","startedAt":1800000000,"platform":"zoom","participants":[],"speakers":[],"tracks":[],"segments":[],"notes":""}"#
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try? decoder.decode(Meeting.self, from: Data(old.utf8))
    check(decoded?.markers.isEmpty == true && decoded?.title == "Old", "meetings without markers decode")
    var meeting = Meeting(title: "M", markers: [MeetingMarker(time: 3725, label: "Pricing")])
    meeting.segments = [TranscriptSegment(channel: .system, start: 1, end: 2, text: "Hi")]
    let encoded = try? JSONEncoder().encode(meeting)
    check(encoded.flatMap { try? JSONDecoder().decode(Meeting.self, from: $0) }?.markers.first?.timestamp == "1:02:05", "markers round trip with a timestamp")
    check(MeetingExport.text(meeting, format: .markdown).contains("## Markers\n\n- 1:02:05 Pricing"), "export lists markers")
    check(MeetingExport.text(meeting, format: .plainText).contains("Them (00:01): Hi"), "plain-text transcript by channel label")
    check(HubPage(rawValue: "history") == .history && StoreChange.notes != .reloaded, "history page and notes change")
    check(TransformError.tooLong.recoverySuggestion?.contains("1000") == true && TransformError.modelNotReady.errorDescription?.contains("getting ready") == true,
          "transform errors in Core")
    check(AppContext(fieldRole: "AXTextField").isSingleLineField && !AppContext(fieldRole: "AXTextArea").isSingleLineField, "single-line fields by role")
    check(TranscriptionOptions().channel == .mic && TranscriptionOptions(channel: .system).channel == .system, "channel on options")
    check(SupportedLanguages.parakeetCovers(["en", "de"]) && !SupportedLanguages.parakeetCovers(["en", "ja"]) && !SupportedLanguages.parakeetCovers([])
              && SupportedLanguages.whisper.count == 100 && SupportedLanguages.all.contains("ja") && SupportedLanguages.base("pt_BR") == "pt",
          "language lists")
    check(AppLists.category(bundleID: "com.openai.chat") == .ai && AppLists.category(bundleID: "com.apple.Safari", url: "https://claude.ai/new") == .ai,
          "AI chat apps and sites are in Core")
    check(ModelCatalog.localVQE.repository == "FluidInference/localvqe-coreml" && ModelCatalog.all.filter { $0.repository != nil }.allSatisfy { $0.revision?.count == 40 },
          "Core ML sets pin a commit")
    check(DictationLimits.cleanupBudget(words: 5) == 1.0 && DictationLimits.cleanupBudget(words: 40) == 2.5, "cleanup budgets")
    check(MeetingBarPhase.recording(wordCount: 1, startedAt: Date(timeIntervalSince1970: 1)) == .recording(wordCount: 1, startedAt: Date(timeIntervalSince1970: 1)),
          "meeting phase carries its start")
    check(GlobeKey.Usage(rawValue: 3) == .startDictation && GlobeKey.Usage(rawValue: 0) == .doNothing, "globe key usages")
    check(ScratchNote(text: "Title\n\nbody line").title == "Title" && ScratchNote(text: "Title\n\nbody line").preview == "body line", "scratch note title and preview")
}

private func coreModelCatalog() {
    check(ModelCatalog.all.count == 13 && Set(ModelCatalog.all.map(\.id)).count == 13, "unique catalog ids")
    let nemotron = ModelCatalog.nemotronStreamingEN
    check(nemotron.bytes == 626_803_815 && nemotron.revision == "e673531caa6d25ab7baf5a8c14c9b99ba1551838" && nemotron.subfolder == "nemotron_coreml_1120ms"
          && nemotron.languages == ["en"] && nemotron.attribution.contains("Licensed by NVIDIA Corporation under the NVIDIA Open Model License"),
          "Nemotron: pinned tier, size and the NVIDIA notice")
    check(ModelCatalog.appleSpeech.isBuiltIn && ModelCatalog.appleSpeech.bytes == 0 && !ModelCatalog.parakeetV3.isBuiltIn, "Apple's engine is built in")
    check(ModelCatalog.dictationEngines(isAppleSilicon: true, hasAppleSpeech: false).map(\.id) == [ModelCatalog.parakeetV3.id, nemotron.id]
          && ModelCatalog.dictationEngines(isAppleSilicon: true, hasAppleSpeech: true).last?.id == ModelCatalog.appleSpeech.id
          && ModelCatalog.dictationEngines(isAppleSilicon: false, hasAppleSpeech: true).isEmpty, "dictation engine choices")
    check(ModelCatalog.cleanupModels(isAppleSilicon: true, memoryBytes: 16 << 30).isEmpty
          && ModelCatalog.cleanupModels(isAppleSilicon: true, memoryBytes: 24 << 30).map(\.id) == [ModelCatalog.qwen35_2B.id, ModelCatalog.qwen35_4B.id],
          "the 4B cleanup model is offered from 24 GB")
    check(Defaults.Keys.cleanupModelID.defaultValue == ModelCatalog.qwen35_2B.id && Defaults.Keys.asrModelID.defaultValue == ModelCatalog.parakeetV3.id,
          "defaults: Parakeet and Qwen3.5-2B")
    check(ModelCatalog.all.filter { $0.url != nil }.allSatisfy { $0.sha256?.count == 64 }, "every URL entry has a SHA-256")
    check(ModelCatalog.whisperLargeV3Turbo.fileName == "ggml-large-v3-turbo-q5_0.bin" && ModelCatalog.parakeetV3.fileName == "parakeet-tdt-0.6b-v3", "file names")
    check(ModelCatalog.all.allSatisfy { !$0.licence.isEmpty && !$0.attribution.isEmpty }, "licence and attribution on every model")
    let standard = ModelCatalog.preset(isAppleSilicon: true, memoryBytes: 16 << 30)
    check(standard.dictation.map(\.id) == [ModelCatalog.parakeetV3.id, ModelCatalog.whisperBase.id, ModelCatalog.qwen35_2B.id], "standard preset")
    check(standard.meetings.contains { $0.id == ModelCatalog.qwen35_4B.id }, "standard meetings pack")
    let light = ModelCatalog.preset(isAppleSilicon: true, memoryBytes: 8 << 30)
    check(light.dictation.contains { $0.id == ModelCatalog.qwen35_0_8B.id } && light.name == "Apple silicon, light", "light preset")
    let intel = ModelCatalog.preset(isAppleSilicon: false, memoryBytes: 16 << 30)
    check(intel.dictation.map(\.id) == [ModelCatalog.whisperSmall.id, ModelCatalog.whisperBase.id] && intel.dictation.allSatisfy { $0.engine == "whisper" }, "Intel preset")
    let order = AutoDownloadPolicy.order(for: standard).map(\.id)
    check(order.first == ModelCatalog.parakeetV3.id && order.firstIndex(of: ModelCatalog.qwen35_2B.id)! < order.firstIndex(of: ModelCatalog.qwen35_4B.id)!
          && Set(order).count == order.count, "automatic download order: speech, cleanup, notes")
    check(AutoDownloadPolicy.minimumFreeDisk == 10 << 30 && AutoDownloadPolicy.maxConcurrentDownloads == 1, "download policy constants")
    let progress = DownloadProgress(bytesReceived: 50, bytesExpected: 200, rate: 10)
    check(progress.fraction == 0.25 && progress.estimatedTimeRemaining == 15, "progress maths")
}
