import AppKit
import SwiftUI
import SuperFlowCore

/// Filtering and ordering of the Dictionary page (behaviour.md §8.5). Public for the self-test.
public enum DictionaryListing {
    public enum Filter: String, CaseIterable, Sendable {
        case all, words, replacements, learned

        var title: String {
            switch self {
            case .all: "All"
            case .words: "Words"
            case .replacements: "Replacements"
            case .learned: "Learned"
            }
        }

        public func matches(_ entry: DictionaryEntry) -> Bool {
            switch self {
            case .all: true
            case .words: entry.replacement == nil
            case .replacements: entry.replacement != nil
            case .learned: entry.source == .learned
            }
        }
    }

    /// The stored `dictionarySort` values and their labels.
    public static let sorts: [(value: String, title: String)] = [
        ("Newest", "Newest first"), ("Oldest", "Oldest first"), ("Alphabetical", "Alphabetical (A–Z)"), ("Starred", "Starred first"),
    ]

    public static func items(_ entries: [DictionaryEntry], filter: Filter, sort: String, query: String) -> [DictionaryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matching = entries.filter { entry in
            filter.matches(entry) && (q.isEmpty || entry.phrase.localizedCaseInsensitiveContains(q)
                || (entry.replacement?.localizedCaseInsensitiveContains(q) ?? false))
        }
        switch sort {
        case "Oldest": return matching.sorted { $0.createdAt < $1.createdAt }
        case "Alphabetical": return matching.sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
        case "Starred": return matching.sorted { ($0.isStarred ? 0 : 1, $1.createdAt) < ($1.isStarred ? 0 : 1, $0.createdAt) }
        default: return matching.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Whether `phrase` is already an entry (ignoring case), other than `excluding`.
    public static func duplicate(_ phrase: String, in entries: [DictionaryEntry], excluding: UUID? = nil) -> DictionaryEntry? {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.first { $0.id != excluding && $0.phrase.compare(p, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }
}

extension DictionaryEntry {
    /// What the row shows first: the written form.
    var display: String { replacement ?? phrase }
}

// MARK: - Page

struct DictionaryPage: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    @Default(.dictionarySort) private var sort
    @Default(.shouldAutoLearnWords) private var autoLearn
    @State private var query = ""
    @State private var filter = DictionaryListing.Filter.all

    var body: some View {
        PageScaffold(title: "Dictionary", subtitle: "Names, jargon and spellings Super Flow should always get right.") {
            HubTextField(placeholder: "Search your dictionary", text: $query, symbol: "magnifyingglass").frame(width: 240)
            Button { state.modal = .word(nil) } label: { Label("Add word", systemImage: "plus") }
                .buttonStyle(HubButtonStyle(variant: .primary, size: .md))
        } content: {
            if store.dictionary.isEmpty {
                EmptyState(symbol: "character.book.closed", title: "Your dictionary is empty",
                           message: "Add names, product words and anything Super Flow should spell your way, in dictations and meeting notes.",
                           actionTitle: "Add a word") { state.modal = .word(nil) }
                    .borderedBox()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        ForEach(DictionaryListing.Filter.allCases, id: \.self) { f in
                            FilterChip(title: f.title, count: store.dictionary.filter(f.matches).count, selected: filter == f) { filter = f }
                        }
                        Spacer()
                        MenuPicker(options: DictionaryListing.sorts, selection: $sort, width: 170)
                    }
                    let items = DictionaryListing.items(store.dictionary, filter: filter, sort: sort, query: query)
                    if items.isEmpty {
                        EmptyState(symbol: "magnifyingglass", title: "Nothing here", message: emptyMessage).borderedBox()
                    } else {
                        BorderedList(items: items) { DictionaryRow(entry: $0) }
                    }
                    Text(autoLearn ? "When you fix a word right after dictating, it's added here and marked Learned."
                                   : "Learning from your corrections is off. Turn it on in Settings › System.")
                        .hubText(.xs, .regular, HubColor.tertiary)
                }
            }
        }
    }

    private var emptyMessage: String {
        query.isEmpty ? "No \(filter.title.lowercased()) in your dictionary yet." : "No words match “\(query)”."
    }
}

struct DictionaryRow: View {
    @EnvironmentObject private var state: HubState
    let entry: DictionaryEntry

    var body: some View {
        HoverRow(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) { hovering in
            HStack(spacing: 12) {
                Button { toggleStar() } label: {
                    Image(systemName: entry.isStarred ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(entry.isStarred ? Color(nsColor: SFColor.glow300) : HubColor.tertiary.opacity(hovering ? 1 : 0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.isStarred ? "Unstar" : "Star: always prefer this spelling")
                if let replacement = entry.replacement {
                    HStack(spacing: 8) {
                        Text(entry.phrase).hubText(.sm, .regular, HubColor.tertiary).strikethrough(color: HubColor.tertiary)
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(HubColor.tertiary)
                        Text(replacement).hubText(.sm, .emphasis)
                    }
                } else {
                    Text(entry.phrase).hubText(.sm, .emphasis)
                }
                if entry.source == .learned { Chip(text: "Learned", symbol: "sparkles", tint: HubColor.dawnStrong, fill: HubColor.dawnTint) }
                Spacer()
                HStack(spacing: 2) {
                    IconButton(symbol: "pencil", help: "Edit") { state.modal = .word(entry) }
                    IconButton(symbol: "trash", help: "Delete") { delete() }
                }
                .opacity(hovering ? 1 : 0)
            }
        }
    }

    private func toggleStar() {
        var changed = entry
        changed.isStarred.toggle()
        do { try Services.history?.save(changed) } catch {
            state.showToast("“\(entry.display)” couldn't be updated.", isError: true)
        }
    }

    private func delete() {
        state.confirm("Delete “\(entry.display)”?", "It will be removed from your dictionary.") {
            do {
                try Services.history?.deleteDictionaryEntry(entry.id)
                state.showToast("“\(entry.display)” deleted")
            } catch {
                state.showToast("“\(entry.display)” couldn't be deleted.", isError: true)
            }
        }
    }
}

/// Add or edit a word (behaviour.md §8.5): a word, or a correction rule misspelling → spelling.
struct WordEditor: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    let entry: DictionaryEntry?
    @State private var word = ""
    @State private var correct = false
    @State private var spelling = ""

    var body: some View {
        ModalChrome(width: 460) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry == nil ? "Add to dictionary" : "Edit word").hubHeading(5)
                Text("Super Flow will use this spelling in dictations and meeting notes.").hubText(.sm, .regular, HubColor.tertiary)
            }
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(correct ? "Heard as" : "Word or phrase").hubText(.xs, .strong, HubColor.tertiary)
                    HubTextField(placeholder: correct ? "e.g. super base" : "e.g. Priya, Kubernetes, OKRs", text: $word, onSubmit: save)
                }
                HStack(spacing: 10) {
                    Toggle("", isOn: $correct.animation(.easeOut(duration: 0.15))).hubSwitch()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Correct a misspelling").hubText(.sm, .emphasis)
                        Text("Replace what's heard with your spelling.").hubText(.xs, .regular, HubColor.tertiary)
                    }
                }
                if correct {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Write it as").hubText(.xs, .strong, HubColor.tertiary)
                        HubTextField(placeholder: "e.g. Supabase", text: $spelling, onSubmit: save)
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { state.modal = nil }.buttonStyle(HubButtonStyle(variant: .ghost)).keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Add word" : "Save changes", action: save)
                    .buttonStyle(HubButtonStyle(variant: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            guard let entry else { return }
            word = entry.phrase
            correct = entry.replacement != nil
            spelling = entry.replacement ?? ""
        }
    }

    private func save() {
        let phrase = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !correct || !replacement.isEmpty else {
            state.showToast(correct ? "Enter both the misspelling and the spelling." : "The word can't be empty.", isError: true)
            return
        }
        if let existing = DictionaryListing.duplicate(phrase, in: store.dictionary, excluding: entry?.id) {
            state.showToast("“\(existing.phrase)” is already in your dictionary.", isError: true)
            return
        }
        var saved = entry ?? DictionaryEntry(phrase: phrase)
        saved.phrase = phrase
        saved.replacement = correct ? replacement : nil
        do {
            try Services.history?.save(saved)
            state.modal = nil
            state.showToast(entry == nil ? "“\(saved.display)” added" : "“\(saved.display)” updated")
        } catch {
            state.showToast("Couldn't save the word. Try again.", isError: true)
        }
    }
}

// MARK: - Snippets (behaviour.md §8.6)

/// Snippet checks shared by the editor and the self-test.
public enum SnippetRules {
    /// Lower-cased, punctuation-free, single-spaced: how triggers are compared.
    public static func normalized(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// An existing snippet whose trigger is the same or contains / is contained in this one.
    public static func similar(to trigger: String, in snippets: [Snippet], excluding: UUID? = nil) -> Snippet? {
        let t = normalized(trigger)
        guard !t.isEmpty else { return nil }
        return snippets.first { s in
            guard s.id != excluding else { return false }
            let other = normalized(s.trigger)
            return other == t || (" \(other) ").contains(" \(t) ") || (" \(t) ").contains(" \(other) ")
        }
    }
}

struct SnippetsPage: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    @State private var query = ""

    var body: some View {
        PageScaffold(title: "Snippets", subtitle: "Say a short cue and Super Flow types the full text.") {
            HubTextField(placeholder: "Search your snippets", text: $query, symbol: "magnifyingglass").frame(width: 240)
            Button { state.modal = .snippet(nil) } label: { Label("Add snippet", systemImage: "plus") }
                .buttonStyle(HubButtonStyle(variant: .primary, size: .md))
        } content: {
            if store.snippets.isEmpty {
                EmptyState(symbol: "text.append", title: "No snippets yet",
                           message: "Save text you type often, like an intro, an address or a link, then say its cue to drop it in.",
                           actionTitle: "Add a snippet") { state.modal = .snippet(nil) }
                    .borderedBox()
            } else {
                let items = filtered
                if items.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "No results", message: "No snippets match “\(query)”.").borderedBox()
                } else {
                    BorderedList(items: items) { SnippetRow(snippet: $0) }
                }
            }
        }
    }

    private var filtered: [Snippet] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.snippets
            .filter { q.isEmpty || $0.trigger.localizedCaseInsensitiveContains(q) || $0.expansion.localizedCaseInsensitiveContains(q) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct SnippetRow: View {
    @EnvironmentObject private var state: HubState
    let snippet: Snippet

    var body: some View {
        HoverRow { hovering in
            HStack(alignment: .top, spacing: 16) {
                Text(snippet.trigger).hubText(.sm, .emphasis).frame(width: 200, alignment: .leading)
                Text(snippet.expansion).hubText(.sm, .regular, HubColor.tertiary).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 2) {
                    IconButton(symbol: "pencil", help: "Edit") { state.modal = .snippet(snippet) }
                    IconButton(symbol: "trash", help: "Delete") {
                        state.confirm("Delete “\(snippet.trigger)”?", "The snippet will be removed.") {
                            do {
                                try Services.history?.deleteSnippet(snippet.id)
                                state.showToast("“\(snippet.trigger)” deleted")
                            } catch {
                                state.showToast("“\(snippet.trigger)” couldn't be deleted.", isError: true)
                            }
                        }
                    }
                }
                .opacity(hovering ? 1 : 0)
            }
        }
    }
}

struct SnippetEditor: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    let snippet: Snippet?
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        ModalChrome(width: 520) {
            VStack(alignment: .leading, spacing: 6) {
                Text(snippet == nil ? "Add snippet" : "Edit snippet").hubHeading(5)
                Text("When you say the cue, Super Flow writes the text instead.").hubText(.sm, .regular, HubColor.tertiary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Cue").hubText(.xs, .strong, HubColor.tertiary)
                HubTextField(placeholder: "e.g. my calendar link", text: $trigger)
                HStack {
                    Text("Text").hubText(.xs, .strong, HubColor.tertiary)
                    Spacer()
                    Text("\(expansion.count)/\(Snippet.maxExpansionLength)")
                        .hubText(.xs, .regular, expansion.count > Snippet.maxExpansionLength ? HubColor.destructive : HubColor.tertiary)
                        .monospacedDigit()
                }
                .padding(.top, 8)
                HubTextArea(placeholder: "e.g. https://cal.com/you/30min", text: $expansion, minHeight: 120)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { state.modal = nil }.buttonStyle(HubButtonStyle(variant: .ghost)).keyboardShortcut(.cancelAction)
                Button(snippet == nil ? "Add snippet" : "Save changes", action: save)
                    .buttonStyle(HubButtonStyle(variant: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            trigger = snippet?.trigger ?? ""
            expansion = snippet?.expansion ?? ""
        }
    }

    private func save() {
        let cue = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cue.isEmpty, !text.isEmpty else { state.showToast("Enter a cue and its text.", isError: true); return }
        guard text.count <= Snippet.maxExpansionLength else { state.showToast("This text is too long. Shorten it and try again.", isError: true); return }
        let similar = SnippetRules.similar(to: cue, in: store.snippets, excluding: snippet?.id)
        var saved = snippet ?? Snippet(trigger: cue, expansion: text)
        saved.trigger = cue
        saved.expansion = text
        do {
            try Services.history?.save(saved)
            state.modal = nil
            if let similar {
                state.showToast("Saved. “\(similar.trigger)” sounds alike; distinct cues work best.")
            } else {
                state.showToast(snippet == nil ? "“\(cue)” added" : "“\(cue)” updated")
            }
        } catch {
            state.showToast("Couldn't save the snippet. Try again.", isError: true)
        }
    }
}
