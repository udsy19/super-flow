import Foundation
import Combine
import SuperFlowCore

/// A Notes page entry (behaviour.md §11.4 Scratchpad, without the floating window).
public struct ScratchNote: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), text: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// The first non-empty line, or "New note".
    public var title: String {
        text.split(whereSeparator: \.isNewline).lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "New note"
    }

    /// The text after the title line, flattened to one line.
    public var preview: String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.dropFirst().joined(separator: " ")
    }
}

/// The notes, kept as one JSON file next to the store until FlowStore carries notes (contract proposal in the
/// HubKit report). Writes are atomic; a damaged file is set aside rather than overwritten.
@MainActor
public final class NotesStore: ObservableObject {
    @Published public private(set) var notes: [ScratchNote] = []
    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? SuperFlowPaths.support.appendingPathComponent("notes.json")
        load()
    }

    /// Newest edit first.
    public var sorted: [ScratchNote] { notes.sorted { $0.updatedAt > $1.updatedAt } }

    @discardableResult public func create() -> ScratchNote {
        let note = ScratchNote()
        notes.append(note)
        persist()
        return note
    }

    public func update(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].text != text else { return }
        notes[i].text = text
        notes[i].updatedAt = Date()
        persist()
    }

    public func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            notes = try JSONDecoder.notes.decode([ScratchNote].self, from: data)
        } catch {
            Log.hub.error("Notes file unreadable, set aside: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("damaged-\(Int(Date().timeIntervalSince1970))"))
        }
    }

    private func persist() {
        do {
            try JSONEncoder.notes.encode(notes).write(to: url, options: .atomic)
        } catch {
            Log.hub.error("Couldn't save notes: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension JSONEncoder {
    static var notes: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

private extension JSONDecoder {
    static var notes: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
