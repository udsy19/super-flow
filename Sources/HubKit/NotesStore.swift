import Combine
import Foundation
import SuperFlowCore

/// The Notes page's view of `HistoryStoring.notes` (behaviour.md §11.4): an observable list that follows the store's
/// change feed. Without a store (offscreen renders, the self-test) it keeps the notes in memory.
@MainActor
public final class NotesStore: ObservableObject {
    @Published public private(set) var notes: [ScratchNote] = []
    private let history: HistoryStoring?
    private var subscription: AnyCancellable?

    public init(history: HistoryStoring?) {
        self.history = history
        reload()
        subscription = history?.changes
            .filter { $0 == .notes || $0 == .reloaded }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    /// Newest edit first.
    public var sorted: [ScratchNote] { notes.sorted { $0.updatedAt > $1.updatedAt } }

    @discardableResult public func create() -> ScratchNote {
        let note = ScratchNote()
        persist(note)
        return note
    }

    /// The note a Quick note opens: the newest one while it is still blank (clicking again doesn't pile up empty
    /// notes), otherwise a new one.
    public func quickNote() -> ScratchNote {
        if let newest = sorted.first, newest.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return newest }
        return create()
    }

    public func update(_ id: UUID, text: String) {
        guard var note = notes.first(where: { $0.id == id }), note.text != text else { return }
        note.text = text
        note.updatedAt = Date()
        persist(note)
    }

    public func delete(_ id: UUID) {
        if let history {
            do { try history.deleteNote(id) } catch { Log.hub.error("Couldn't delete a note: \(error.localizedDescription, privacy: .public)") }
        }
        notes.removeAll { $0.id == id }
    }

    private func persist(_ note: ScratchNote) {
        if let history {
            do { try history.save(note) } catch { Log.hub.error("Couldn't save a note: \(error.localizedDescription, privacy: .public)") }
        }
        notes.removeAll { $0.id == note.id }
        notes.append(note)
    }

    private func reload() {
        guard let history else { return }
        notes = history.notes
    }
}
