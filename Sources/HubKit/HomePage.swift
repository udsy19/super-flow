import AppKit
import SwiftUI
import SuperFlowCore

// MARK: - Home (behaviour.md §12: welcome, stats, recent dictations)

struct HomePage: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    @Default(.userFirstName) private var firstName
    @Default(.shortcuts) private var shortcuts

    var body: some View {
        let returning = !store.dictations.isEmpty
        PageScaffold(title: (returning ? "Welcome back" : "Welcome") + (firstName.isEmpty ? "" : ", \(firstName)")) {
            EmptyView()
        } content: {
            HoldHint(chord: shortcuts.chords(for: .pushToTalk).first)
                .padding(.top, -16)
            let _ = store.modelRevision
            if let summary = ModelSummary.current(), !summary.speechReady {
                ModelBanner(summary: summary)
            }
            if returning { StatsRow() }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent dictations").hubHeading(5)
                    Spacer()
                    if !store.dictations.isEmpty {
                        Button("See all") { state.go(.history) }.buttonStyle(HubButtonStyle(variant: .ghost, size: .xs))
                    }
                }
                if store.dictations.isEmpty {
                    EmptyState(symbol: "waveform", title: "No dictations yet", message: "What you dictate in any app shows up here.")
                        .borderedBox()
                } else {
                    BorderedList(items: Array(store.dictations.prefix(6))) { DictationRow(dictation: $0) }
                }
            }
        }
    }
}

/// "Hold [fn] in any app and start talking."
struct HoldHint: View {
    let chord: KeyChord?

    var body: some View {
        HStack(spacing: 8) {
            if let chord {
                Text("Hold").hubText(.sm, .regular, HubColor.tertiary)
                ChordView(chord: chord)
                Text("in any app and start talking.").hubText(.sm, .regular, HubColor.tertiary)
            } else {
                Text("Set a dictation shortcut in Settings › General to start.").hubText(.sm, .regular, HubColor.tertiary)
            }
        }
    }
}

struct StatsRow: View {
    @EnvironmentObject private var store: HubStore

    var body: some View {
        let _ = store.dictations.count
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().addingTimeInterval(-7 * 86_400)
        let none: (dictations: Int, words: Int, seconds: TimeInterval) = (0, 0, 0)
        let stats = Services.history?.statistics(since: week) ?? none
        let all = Services.history?.statistics(since: .distantPast) ?? none
        HStack(spacing: 12) {
            StatTile(label: "Words this week", value: HubFormat.count(stats.words))
            StatTile(label: "Dictations this week", value: HubFormat.count(stats.dictations))
            StatTile(label: "Speaking speed", value: HubFormat.wordsPerMinute(words: all.words, seconds: all.seconds).map { "\($0)" } ?? "–",
                     unit: "wpm")
            StatTile(label: "Words in total", value: HubFormat.count(all.words))
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).hubText(.xs, .strong, HubColor.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).hubDisplay(36).monospacedDigit()
                if let unit { Text(unit).hubText(.sm, .regular, HubColor.tertiary) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SFMetrics.Radius.xl, style: .continuous).fill(HubColor.backgroundTertiary))
    }
}

/// Dictation needs its speech model: progress, never a question.
struct ModelBanner: View {
    @EnvironmentObject private var state: HubState
    let summary: ModelSummary

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.down.circle").font(.system(size: 20, weight: .regular)).foregroundStyle(HubColor.neutral600)
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.headline).hubText(.sm, .emphasis)
                Text("\(summary.detail). Dictation starts working as soon as the speech model is on this Mac.")
                    .hubText(.sm, .regular, HubColor.tertiary)
                if let fraction = summary.fraction { ProgressLine(fraction: fraction).frame(maxWidth: 360).padding(.top, 2) }
            }
            Spacer()
            Button("Details") { state.settingsPane = .models }.buttonStyle(HubButtonStyle(variant: .outline))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: SFMetrics.Radius.xl, style: .continuous).fill(HubColor.backgroundTertiary))
    }
}

// MARK: - History (behaviour.md §11.1)

struct HistoryPage: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    @Default(.localDataPolicy) private var policy
    @State private var query = ""
    @State private var results: [Dictation]?

    var body: some View {
        PageScaffold(title: "History", subtitle: subtitle) {
            if policy != .never {
                HubTextField(placeholder: "Search past transcripts", text: $query, symbol: "magnifyingglass").frame(width: 280)
            }
        } content: {
            if policy == .never {
                EmptyState(symbol: "clock.badge.xmark", title: "History is off",
                           message: "Dictations aren't saved on this Mac. You can change that in Settings › Privacy.",
                           actionTitle: "Open Privacy settings") { state.settingsPane = .dataAndPrivacy }
            } else if let results, results.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "No results", message: "No transcripts match “\(query)”.")
            } else if (results ?? store.dictations).isEmpty {
                EmptyState(symbol: "waveform", title: "No dictations yet",
                           message: "Once you dictate in your apps, every transcript shows up here.")
            } else {
                ForEach(HubFormat.groupByDay(results ?? store.dictations, date: \.createdAt), id: \.title) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title).sectionLabelStyle()
                        BorderedList(items: group.items) { DictationRow(dictation: $0) }
                    }
                }
            }
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { results = nil; return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            results = Services.history?.dictations(matching: trimmed, limit: 300, offset: 0) ?? []
        }
        .onChange(of: store.dictations) { _, _ in
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { results = Services.history?.dictations(matching: trimmed, limit: 300, offset: 0) ?? [] }
        }
    }

    private var subtitle: String {
        switch policy {
        case .store: "Every dictation, kept on this Mac."
        case .autoDelete24h: "Dictations are deleted from this Mac after 24 hours."
        case .never: "Dictations aren't saved."
        }
    }
}

/// One dictation: a 98 pt time column, the text, and copy / paste again / more on hover (§11 gap 1).
struct DictationRow: View {
    @EnvironmentObject private var state: HubState
    let dictation: Dictation

    var body: some View {
        HoverRow { hovering in
            HStack(alignment: .top, spacing: 16) {
                Text(HubFormat.time(dictation.createdAt))
                    .hubText(.sm, .regular, HubColor.tertiary)
                    .monospacedDigit()
                    .frame(width: 82, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    if let notice = DictationActions.notice(for: dictation) {
                        Text(notice).hubText(.sm, .regular, HubColor.tertiary).italic()
                    } else {
                        Text(dictation.displayText).hubText(.sm).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if let app = dictation.app?.name {
                        Text(app + (dictation.usesRawText ? " · original wording" : "")).hubText(.xs, .regular, HubColor.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 2) {
                    IconButton(symbol: "doc.on.doc", help: "Copy transcript") { DictationActions.copy(dictation, state: state) }
                    IconButton(symbol: "arrow.uturn.forward", help: "Paste into the last app") { DictationActions.reinsert(dictation) }
                    Menu {
                        if dictation.rawText != dictation.cleanedText {
                            Button(dictation.usesRawText ? "Redo AI edit" : "Undo AI edit") { DictationActions.toggleAIEdit(dictation, state: state) }
                        }
                        Button("Delete transcript", role: .destructive) { DictationActions.delete(dictation, state: state) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).foregroundStyle(HubColor.neutral600)
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 28)
                    .help("More options")
                }
                .opacity(hovering ? 1 : 0)
                .disabled(DictationActions.notice(for: dictation) != nil && dictation.displayText.isEmpty)
            }
        }
    }
}

@MainActor
enum DictationActions {
    /// What a row says instead of text when the dictation produced none.
    static func notice(for d: Dictation) -> String? {
        guard d.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch d.outcome {
        case .noAudio, .empty: return "No speech was heard."
        case .dismissed: return "This dictation was cancelled."
        case .error, .timeout, .verificationFailed: return "This dictation didn't finish."
        case .processing: return "Still processing…"
        case .rawTranscript, .formatted, .fallback: return "Empty transcript."
        }
    }

    static func copy(_ d: Dictation, state: HubState) {
        Clipboard.copy(d.displayText)
        state.showToast("Transcript copied")
    }

    /// Hides the hub so the previous app is frontmost again, then inserts there.
    static func reinsert(_ d: Dictation) {
        let text = d.displayText
        NSApp.hide(nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            _ = await Services.insertion?.insert(text, actions: [], method: Defaults[.insertionMethod])
        }
    }

    static func toggleAIEdit(_ d: Dictation, state: HubState) {
        var changed = d
        changed.usesRawText.toggle()
        do { try Services.history?.save(changed) } catch { state.showToast("Couldn't change the transcript.", isError: true) }
    }

    static func delete(_ d: Dictation, state: HubState) {
        state.confirm("Delete this transcript?", "It will be removed from this Mac and can't be recovered.") {
            do {
                try Services.history?.deleteDictation(d.id)
                state.showToast("Transcript deleted")
            } catch {
                state.showToast("Couldn't delete the transcript.", isError: true)
            }
        }
    }
}
