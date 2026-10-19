import AppKit
import SwiftUI
import SuperFlowCore

/// Notes (behaviour.md §11.4): a list of quick notes and an editor you can dictate into.
struct NotesPage: View {
    @EnvironmentObject private var notes: NotesStore
    @EnvironmentObject private var state: HubState
    @State private var selection: UUID?
    /// The note whose editor takes the keyboard once it shows (a Quick note).
    @State private var focusNoteID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageTitle(title: "Notes", subtitle: "Ideas, lists and drafts. Hold the shortcut to dictate into a note.") {
                Button { selection = notes.create().id } label: { Label("New note", systemImage: "square.and.pencil") }
                    .buttonStyle(HubButtonStyle(variant: .primary, size: .md))
            }
            .padding(.bottom, SFMetrics.Hub.titleBottomMargin)

            if notes.notes.isEmpty {
                EmptyState(symbol: "note.text", title: "No notes yet",
                           message: "Jot down an idea, a to-do list or a message you want to get right before sending.",
                           actionTitle: "New note") { selection = notes.create().id }
                    .borderedBox()
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 16) {
                    NoteList(selection: $selection).frame(width: 280)
                    if let id = selection ?? notes.sorted.first?.id, let note = notes.notes.first(where: { $0.id == id }) {
                        NoteEditor(note: note, focusNoteID: $focusNoteID) {
                            notes.delete(note.id)
                            selection = notes.sorted.first?.id
                        }
                        .id(note.id)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: SFMetrics.Hub.contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, SFMetrics.Hub.pagePadding.left)
        .padding(.top, SFMetrics.Hub.pagePadding.top)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: openQuickNote)
        .onChange(of: state.quickNoteID) { _, _ in openQuickNote() }
    }

    private func openQuickNote() {
        guard let id = state.quickNoteID else { return }
        state.quickNoteID = nil
        selection = id
        focusNoteID = id
    }
}

struct NoteList: View {
    @EnvironmentObject private var notes: NotesStore
    @Binding var selection: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(notes.sorted) { note in
                    let selected = note.id == (selection ?? notes.sorted.first?.id)
                    Button { selection = note.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).hubText(.sm, .emphasis).lineLimit(1)
                            Text(note.preview.isEmpty ? "No more text" : note.preview).hubText(.xs, .regular, HubColor.tertiary).lineLimit(2)
                            Text(HubFormat.dayTitle(note.updatedAt) + " · " + HubFormat.time(note.updatedAt))
                                .hubText(.xs, .regular, HubColor.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? HubColor.backgroundTertiary : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NoteEditor: View {
    @EnvironmentObject private var notes: NotesStore
    let note: ScratchNote
    @Binding var focusNoteID: UUID?
    let onDelete: () -> Void
    @State private var text = ""
    @FocusState private var editing: Bool
    @StateObject private var saver = DebouncedSave(delay: 0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edited \(HubFormat.dayTitle(note.updatedAt).lowercasedIfRelative) at \(HubFormat.time(note.updatedAt))")
                    .hubText(.xs, .regular, HubColor.tertiary)
                Spacer()
                IconButton(symbol: "doc.on.doc", help: "Copy note") { Clipboard.copy(text) }
                IconButton(symbol: "trash", help: "Delete note", action: onDelete)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Rule()
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Start typing, or hold the shortcut and talk.").hubBody(HubColor.tertiary)
                        .padding(.horizontal, 21).padding(.vertical, 16).allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($editing)
                    .hubBody()
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .borderedBox()
        .onAppear {
            text = note.text
            takeFocusIfAsked()
        }
        .onChange(of: focusNoteID) { _, _ in takeFocusIfAsked() }
        .onChange(of: text) { _, new in
            let id = note.id
            saver.schedule { [notes] in notes.update(id, text: new) }
        }
        .onDisappear {
            saver.flush()
            notes.update(note.id, text: text)
        }
    }
}

extension NoteEditor {
    /// Focuses the editor when its note is the one asked for, once the window has made it to the front.
    private func takeFocusIfAsked() {
        guard focusNoteID == note.id else { return }
        focusNoteID = nil
        DispatchQueue.main.async { editing = true }
    }
}

private extension String {
    /// "today" / "yesterday" mid-sentence; dates and weekdays keep their case.
    var lowercasedIfRelative: String { self == "Today" || self == "Yesterday" ? lowercased() : "on " + self }
}
