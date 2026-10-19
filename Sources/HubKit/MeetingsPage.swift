import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import SuperFlowCore

// MARK: - Transcript blocks (behaviour.md §20.7.5; the export itself is `MeetingExport` in Core)

/// Consecutive final segments by one speaker.
public struct TranscriptGroup: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var speaker: String
    /// Index of the speaker in order of first appearance, for the label colour.
    public var ordinal: Int
    public var start: TimeInterval
    public var lines: [String]

    public static func make(_ meeting: Meeting) -> [TranscriptGroup] {
        var groups: [TranscriptGroup] = []
        var order: [String] = []
        for segment in meeting.segments.filter(\.isFinal).sorted(by: { $0.start < $1.start }) {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let name = meeting.speakerLabel(for: segment)
            if !order.contains(name) { order.append(name) }
            if let last = groups.indices.last, groups[last].speaker == name {
                groups[last].lines.append(text)
            } else {
                groups.append(TranscriptGroup(id: segment.id, speaker: name, ordinal: order.firstIndex(of: name) ?? 0, start: segment.start,
                                              lines: [text]))
            }
        }
        return groups
    }
}

// MARK: - Library (§20.8, ui-reference.md §10.4)

struct MeetingsPage: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    @Default(.meetingAudioRetentionDays) private var audioDays
    @State private var query = ""
    @State private var results: [Meeting]?

    var body: some View {
        PageScaffold(title: "Meetings", subtitle: subtitle) {
            HubTextField(placeholder: "Search meetings", text: $query, symbol: "magnifyingglass").frame(width: 260)
        } content: {
            let meetings = results ?? store.meetings
            if store.meetings.isEmpty {
                EmptyState(symbol: "record.circle", title: "No meetings yet",
                           message: "When a call starts, Super Flow asks whether to take notes. Transcripts, summaries and action items land here.")
                    .borderedBox()
            } else if meetings.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "No results", message: "No meetings match “\(query)”.").borderedBox()
            } else {
                ForEach(HubFormat.groupByDay(meetings, date: \.startedAt), id: \.title) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title).sectionLabelStyle()
                        BorderedList(items: group.items) { MeetingRow(meeting: $0) }
                    }
                }
            }
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { results = nil; return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            results = Services.meetings?.meetings(matching: q, limit: 300, offset: 0) ?? []
        }
    }

    private var subtitle: String {
        audioDays > RetentionPolicy.keepForever
            ? "Recorded on this Mac. Audio is kept for \(RetentionPolicy.label(days: audioDays)); transcripts and notes stay."
            : "Recorded on this Mac. Audio, transcripts and notes stay until you delete them."
    }
}

struct MeetingRow: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    let meeting: Meeting

    var body: some View {
        Button { state.openMeeting(meeting.id) } label: {
            HoverRow(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 16)) { hovering in
                HStack(spacing: 14) {
                    PlatformTile(platform: meeting.platform)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title).hubText(.sm, .emphasis).lineLimit(1)
                        Text(meta).hubText(.xs, .regular, HubColor.tertiary).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    if MeetingRecordingState.isActive(meeting.id) {
                        Chip(text: "Recording", symbol: "circle.fill", tint: HubColor.recording, fill: HubColor.recording.opacity(0.12))
                    }
                    let open = store.actionItems.filter { $0.meetingID == meeting.id && !$0.isCompleted }.count
                    if open > 0 { Chip(text: open == 1 ? "1 action item" : "\(open) action items") }
                    if meeting.hasAudio { Image(systemName: "waveform").font(.system(size: 12)).foregroundStyle(HubColor.tertiary).help("Audio kept") }
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HubColor.tertiary.opacity(hovering ? 1 : 0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var meta: String {
        var parts = [HubFormat.time(meeting.startedAt)]
        if meeting.endedAt != nil { parts.append(HubFormat.duration(meeting.duration)) }
        if meeting.platform != .other { parts.append(HubFormat.platformName(meeting.platform)) }
        let people = max(meeting.participants.count, meeting.speakers.count)
        if people > 1 { parts.append("\(people) people") }
        return parts.joined(separator: " · ")
    }
}

struct PlatformTile: View {
    let platform: MeetingPlatform
    var body: some View {
        Image(systemName: platform == .other ? "mic" : "video")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(HubColor.neutral600)
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(HubColor.backgroundTertiary))
    }
}

extension MeetingRecordingState {
    @MainActor static func isActive(_ id: UUID) -> Bool {
        switch Services.meetingRecorder?.state {
        case .recording(let m)?, .stopping(let m)?: m == id
        default: false
        }
    }

    @MainActor static func stage(of id: UUID) -> String? {
        if case .processing(let m, let stage)? = Services.meetingRecorder?.state, m == id { return stage }
        return nil
    }
}

// MARK: - Detail (§20.7, ui-reference.md §10.1 and §10.4 L2 page)

struct MeetingDetailPage: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    let meetingID: UUID

    var body: some View {
        if let meeting = store.meeting(meetingID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button { state.meetingID = nil } label: {
                        Label("Meetings", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(HubButtonStyle(variant: .ghost, size: .xs))
                    .padding(.leading, -10)
                    .padding(.bottom, 16)

                    MeetingHeader(meeting: meeting)
                    if !meeting.tracks.isEmpty { MeetingAudioBar(meeting: meeting).padding(.top, 20) }
                    UnderlineTabs(tabs: MeetingTab.allCases.map { ($0, $0.title) }, selection: $state.meetingTab)
                        .padding(.top, 28)
                    Group {
                        switch state.meetingTab {
                        case .summary: MeetingSummaryView(meeting: meeting)
                        case .transcript: MeetingTranscriptView(meeting: meeting)
                        case .notes: MeetingNotesView(meeting: meeting).id(meeting.id)
                        }
                    }
                    .padding(.top, 24)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, SFMetrics.Hub.pagePadding.left)
                .padding(.top, 28)
                .padding(.bottom, 56)
                .frame(maxWidth: .infinity)
            }
        } else {
            EmptyState(symbol: "questionmark.circle", title: "This meeting is gone", message: "It may have been deleted.",
                       actionTitle: "Back to Meetings") { state.meetingID = nil }
        }
    }
}

struct MeetingHeader: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(meeting.title).hubDisplay(36).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(meta).hubText(.sm, .regular, HubColor.tertiary)
                if MeetingRecordingState.isActive(meeting.id) {
                    Chip(text: "Recording", symbol: "circle.fill", tint: HubColor.recording, fill: HubColor.recording.opacity(0.12))
                }
                Spacer()
                Button { copyMarkdown() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
                    .help("Copy summary, notes and transcript as Markdown")
                Button { export() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
                    .help("Save as a Markdown file")
                Menu {
                    Button("Delete meeting", role: .destructive) { delete() }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).foregroundStyle(HubColor.neutral600)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 28)
                .help("More options")
            }
            let names = people
            if !names.isEmpty {
                HStack(spacing: 6) {
                    ForEach(names.prefix(8), id: \.self) { Chip(text: $0, symbol: "person") }
                    if names.count > 8 { Chip(text: "+\(names.count - 8)") }
                }
            }
        }
    }

    private var meta: String {
        var parts = [meeting.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())]
        if let end = meeting.endedAt {
            parts.append("\(HubFormat.time(meeting.startedAt))–\(HubFormat.time(end))")
            parts.append(HubFormat.duration(meeting.duration))
        } else {
            parts.append(HubFormat.time(meeting.startedAt))
        }
        if meeting.platform != .other { parts.append(HubFormat.platformName(meeting.platform)) }
        return parts.joined(separator: " · ")
    }

    private var people: [String] {
        let named = meeting.participants.map(\.name)
        return named.isEmpty ? meeting.speakers.map(\.displayName) : named
    }

    private var actionItems: [ActionItem] { MeetingActionItems.items(for: meeting, store: store.actionItems) }

    private func copyMarkdown() {
        Clipboard.copy(MeetingExport.text(meeting, format: .markdown, actionItems: actionItems))
        state.showToast("Copied as Markdown")
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = MeetingExport.fileName(for: meeting, format: .markdown)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MeetingExport.write(meeting, format: .markdown, to: url, actionItems: actionItems)
            state.showToast("Saved \(url.lastPathComponent)")
        } catch {
            state.showToast("Couldn't save the file.", isError: true)
        }
    }

    private func delete() {
        state.confirm("Delete this meeting?", "Its audio, transcript, notes and summary will be removed from this Mac.") {
            do {
                try Services.meetings?.deleteMeeting(meeting.id)
                state.meetingID = nil
                state.showToast("Meeting deleted")
            } catch {
                state.showToast("Couldn't delete the meeting.", isError: true)
            }
        }
    }
}

/// "Retry transcript" and "Generate summary" for a finished meeting whose transcription or notes failed.
@MainActor
public enum MeetingRetry {
    /// "Generate summary" is offered: no summary, enough transcript and notes for one, and nothing running on the meeting.
    public static func canSummarize(_ meeting: Meeting) -> Bool {
        let words = MeetingExport.finalSegments(meeting.segments).reduce(0) { $0 + Dictation.countWords($1.text) } + Dictation.countWords(meeting.notes)
        return meeting.summary == nil && words >= MeetingSummary.minimumWords && isIdle(meeting)
    }

    /// "Retry transcript" is offered: nothing was transcribed, the audio is still there, and nothing is running on it.
    public static func canRetryTranscript(_ meeting: Meeting) -> Bool {
        MeetingExport.finalSegments(meeting.segments).isEmpty && meeting.hasAudio && isIdle(meeting)
    }

    private static func isIdle(_ meeting: Meeting) -> Bool {
        !MeetingRecordingState.isActive(meeting.id) && MeetingRecordingState.stage(of: meeting.id) == nil
    }

    static func transcript(of id: UUID, state: HubState) {
        Task { @MainActor in
            do {
                try await Services.meetingRecorder?.retryTranscript(of: id)
                state.showToast("Transcript ready")
            } catch {
                state.showToast(error.localizedDescription, isError: true)
            }
        }
    }

    static func notes(of id: UUID, state: HubState) {
        Task { @MainActor in
            do {
                try await Services.meetingRecorder?.regenerateNotes(of: id)
                state.showToast("Your summary is ready!")
            } catch {
                state.showToast(error.localizedDescription, isError: true)
            }
        }
    }
}

/// Action items live as rows in the store (My Tasks); the summary's copy is the fallback before they're saved.
enum MeetingActionItems {
    static func items(for meeting: Meeting, store: [ActionItem]) -> [ActionItem] {
        let saved = store.filter { $0.meetingID == meeting.id && !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
        return saved.isEmpty ? (meeting.summary?.actionItems ?? []) : saved
    }

    @MainActor static func toggle(_ item: ActionItem, in meeting: Meeting, store: [ActionItem]) {
        var changed = item
        changed.isCompleted.toggle()
        changed.meetingID = meeting.id
        if store.contains(where: { $0.id == item.id }) {
            try? Services.meetings?.save(changed)
        } else if var fresh = Services.meetings?.meeting(meeting.id), var summary = fresh.summary,
                  let i = summary.actionItems.firstIndex(where: { $0.id == item.id }) {
            summary.actionItems[i] = changed
            fresh.summary = summary
            try? Services.meetings?.save(fresh)
        }
    }
}

struct MeetingSummaryView: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    let meeting: Meeting

    var body: some View {
        if let summary = meeting.summary {
            VStack(alignment: .leading, spacing: 28) {
                if !summary.summary.isEmpty {
                    SummarySection(title: "Summary") {
                        Text(summary.summary.trimmingCharacters(in: .whitespacesAndNewlines)).hubBody().textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !summary.decisions.isEmpty {
                    SummarySection(title: "Key decisions") { Bullets(items: summary.decisions) }
                }
                let items = MeetingActionItems.items(for: meeting, store: store.actionItems)
                if !items.isEmpty {
                    SummarySection(title: "Action items") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(items) { item in ActionItemRow(item: item, meeting: meeting) }
                        }
                        .padding(.horizontal, -10)
                    }
                }
                if !summary.followUps.isEmpty {
                    SummarySection(title: "Follow-ups") { Bullets(items: summary.followUps) }
                }
                Text(attribution(summary)).hubText(.xs, .regular, HubColor.tertiary)
            }
        } else if let stage = MeetingRecordingState.stage(of: meeting.id) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(stage).hubText(.sm, .emphasis)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HubColor.backgroundTertiary))
        } else if MeetingRetry.canSummarize(meeting) {
            // The notes model failed or wasn't ready when the meeting ended; the transcript and notes are kept.
            EmptyState(symbol: "text.alignleft", title: "No summary yet",
                       message: "The summary couldn't be written when the meeting ended. Your transcript and notes are saved.",
                       actionTitle: "Generate summary") { MeetingRetry.notes(of: meeting.id, state: state) }
        } else {
            EmptyState(symbol: "text.alignleft", title: "No summary",
                       message: meeting.segments.isEmpty ? "There's no transcript to summarize." : "The meeting was too short to summarize.")
        }
    }

    private func attribution(_ summary: MeetingSummary) -> String {
        let model = ModelCatalog.descriptor(summary.modelID)?.name
        let when = summary.generatedAt.formatted(date: .abbreviated, time: .shortened)
        return model.map { "Written on this Mac by \($0), \(when)." } ?? "Written on this Mac, \(when)."
    }
}

struct SummarySection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).hubText(.sm, .bold)
            content
        }
    }
}

struct Bullets: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(HubColor.tertiary).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 5 }
                    Text(item).hubBody().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Task row (§10.1): checkbox, 15/24 text, owner and due date on the right; done rows fade.
struct ActionItemRow: View {
    @EnvironmentObject private var store: HubStore
    let item: ActionItem
    let meeting: Meeting

    var body: some View {
        HoverRow(padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)) { _ in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                CheckBox(checked: item.isCompleted) { MeetingActionItems.toggle(item, in: meeting, store: store.actionItems) }
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                Text(item.text).hubBody().strikethrough(item.isCompleted, color: HubColor.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    if let owner = item.owner, !owner.isEmpty { Text(owner).hubText(.xs, .emphasis, HubColor.neutral600) }
                    if let due = item.due { Text(due.formatted(.dateTime.month(.abbreviated).day())).hubText(.xs, .regular, HubColor.tertiary) }
                }
            }
            .opacity(item.isCompleted ? 0.45 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MeetingTranscriptView: View {
    @EnvironmentObject private var state: HubState
    let meeting: Meeting

    var body: some View {
        let groups = TranscriptGroup.make(meeting)
        if groups.isEmpty, MeetingRetry.canRetryTranscript(meeting) {
            // The speech engine failed or wasn't ready: the audio is kept, so it can be transcribed again.
            EmptyState(symbol: "text.quote", title: "No transcript",
                       message: "Nothing was transcribed for this meeting. The audio is saved, so you can try again.",
                       actionTitle: "Retry transcript") { MeetingRetry.transcript(of: meeting.id, state: state) }
        } else if groups.isEmpty {
            EmptyState(symbol: "text.quote", title: "No transcript", message: "Nothing was transcribed for this meeting.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(groups.count == 1 ? "1 turn" : "\(groups.count) turns") · \(HubFormat.count(wordCount)) words")
                        .hubText(.xs, .regular, HubColor.tertiary)
                    Spacer()
                    Button { Clipboard.copy(meeting.transcriptText); state.showToast("Transcript copied") } label: {
                        Label("Copy transcript", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(HubButtonStyle(variant: .ghost, size: .xs))
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.speaker).hubText(.sm, .emphasis, HubColor.speakers[group.ordinal % HubColor.speakers.count])
                            Text(HubFormat.clock(group.start)).hubText(.xs, .regular, HubColor.tertiary).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(group.lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(Font(SFFont.text(.sm, weight: .medium)))
                                    .foregroundStyle(HubColor.foreground)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(BubbleShape(index: index, count: group.lines.count).fill(HubColor.backgroundTertiary))
                            }
                        }
                    }
                }
            }
        }
    }

    private var wordCount: Int { meeting.segments.filter(\.isFinal).reduce(0) { $0 + Dictation.countWords($1.text) } }
}

/// Grouped bubbles square their inner corners to 4 (§10.1): first bottom-start, middle both start corners, last top-start.
struct BubbleShape: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let topStart: CGFloat = index == 0 ? 12 : 4
        let bottomStart: CGFloat = index == count - 1 ? 12 : 4
        return UnevenRoundedRectangle(topLeadingRadius: topStart, bottomLeadingRadius: bottomStart, bottomTrailingRadius: 12,
                                      topTrailingRadius: 12, style: .continuous).path(in: rect)
    }
}

/// The user's own notes for the meeting, kept verbatim and saved as they type.
struct MeetingNotesView: View {
    @EnvironmentObject private var state: HubState
    let meeting: Meeting
    @State private var text = ""
    @StateObject private var saver = DebouncedSave(delay: 0.5)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Write your notes here. They're kept as written, next to the summary.").hubBody(HubColor.tertiary)
                    .padding(.horizontal, 5).allowsHitTesting(false)
            }
            TextEditor(text: $text).hubBody().scrollContentBackground(.hidden).frame(minHeight: 320)
        }
        .onAppear { text = meeting.notes }
        .onChange(of: text) { _, new in saver.schedule { persist(new) } }
        .onDisappear { saver.flush(); persist(text) }
    }

    private func persist(_ notes: String) {
        guard var fresh = Services.meetings?.meeting(meeting.id), fresh.notes != notes else { return }
        fresh.notes = notes
        do { try Services.meetings?.save(fresh) } catch {
            state.showToast("Couldn't save your notes: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - Audio (kept while retained; §20.9)

/// Plays a meeting's channels together (mic and system audio are separate files).
@MainActor
final class MeetingAudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    let duration: TimeInterval
    private var players: [AVAudioPlayer] = []
    private var timer: Timer?

    init(meeting: Meeting) {
        duration = meeting.tracks.map(\.duration).max() ?? 0
        guard meeting.hasAudio else { return }
        let folder = SuperFlowPaths.meetingAudio.appendingPathComponent(meeting.id.uuidString, isDirectory: true)
        players = meeting.tracks.compactMap { try? AVAudioPlayer(contentsOf: folder.appendingPathComponent($0.file)) }
        players.forEach { $0.prepareToPlay() }
    }

    var isAvailable: Bool { !players.isEmpty }
    var playableDuration: TimeInterval { players.map(\.duration).max() ?? duration }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        guard let first = players.first else { return }
        let start = first.deviceCurrentTime + 0.05
        for p in players { p.currentTime = currentTime; p.play(atTime: start) }
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func pause() {
        players.forEach { $0.pause() }
        timer?.invalidate()
        isPlaying = false
    }

    func seek(to fraction: Double) {
        currentTime = playableDuration * min(max(fraction, 0), 1)
        players.forEach { $0.currentTime = currentTime }
    }

    private func tick() {
        currentTime = players.map(\.currentTime).max() ?? 0
        if !players.contains(where: \.isPlaying) { pause(); if currentTime < 0.5 { currentTime = 0 } }
    }

    deinit { timer?.invalidate() }
}

struct MeetingAudioBar: View {
    let meeting: Meeting
    @StateObject private var player: MeetingAudioPlayer
    @Default(.meetingAudioRetentionDays) private var audioDays

    init(meeting: Meeting) {
        self.meeting = meeting
        _player = StateObject(wrappedValue: MeetingAudioPlayer(meeting: meeting))
    }

    var body: some View {
        HStack(spacing: 14) {
            if meeting.hasAudio {
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HubColor.primaryForeground)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(HubColor.primary))
                }
                .buttonStyle(.plain)
                .disabled(!player.isAvailable)
                .help(player.isPlaying ? "Pause" : "Play recording")
                GeometryReader { geo in
                    ProgressLine(fraction: player.playableDuration > 0 ? player.currentTime / player.playableDuration : 0, height: 4)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { player.seek(to: $0.location.x / geo.size.width) })
                }
                .frame(height: 20)
                Text("\(HubFormat.clock(player.currentTime)) / \(HubFormat.clock(player.playableDuration))")
                    .hubText(.xs, .regular, HubColor.tertiary).monospacedDigit()
                Rectangle().fill(HubColor.border).frame(width: 1, height: 20)
                Text(retention).hubText(.xs, .regular, HubColor.tertiary)
            } else {
                Image(systemName: "waveform.slash").foregroundStyle(HubColor.tertiary)
                Text("Audio deleted\(meeting.audioDeletedAt.map { " on " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""). The transcript and notes are kept.")
                    .hubText(.xs, .regular, HubColor.tertiary)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HubColor.backgroundTertiary))
    }

    private var retention: String {
        guard let expiry = HubFormat.audioExpiry(of: meeting, days: audioDays) else { return "Audio kept until you delete it" }
        return "Audio kept until \(expiry.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
