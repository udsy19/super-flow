import AppKit

/// Everything on a pasteboard: every item with the data of every type, in order, so a paste can put back exactly what
/// the user had copied (rich text, images, files, private types).
public struct PasteboardSnapshot: Equatable {
    public struct Entry: Equatable {
        public let type: NSPasteboard.PasteboardType
        public let data: Data
    }

    public let items: [[Entry]]

    public init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { Entry(type: type, data: $0) } }
        }
    }

    /// Replaces the pasteboard's contents with the snapshot's (an empty snapshot leaves it empty).
    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.filter { !$0.isEmpty }.map { entries in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

/// One paste's turn on the pasteboard (behaviour.md §9.1). The text goes on as a lazily provided item, so the swap
/// learns whether the target app actually asked for it; marker types tell clipboard managers to leave it alone; and
/// afterwards the user's own clipboard comes back, unless something new was copied in between.
@MainActor
public final class PasteboardSwap {
    /// nspasteboard.org markers: don't record (transient), don't show (concealed); plus our own.
    public static let markerTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.TransientType"), .init("org.nspasteboard.ConcealedType"), .init("com.udsy.superflow.insertion"),
    ]

    public let text: String
    private let pasteboard: NSPasteboard
    private let saved: PasteboardSnapshot?
    private let provider: TextProvider
    private var changeCount: Int

    /// Saves what is on `pasteboard` when `restoring`, then puts `text` on it. Without `restoring` nothing is given
    /// back, so the text carries no markers: it simply becomes the clipboard.
    public init(text: String, pasteboard: NSPasteboard = .general, restoring: Bool) {
        self.text = text
        self.pasteboard = pasteboard
        saved = restoring ? PasteboardSnapshot(of: pasteboard) : nil
        provider = TextProvider(text: text)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        if restoring { for marker in Self.markerTypes { item.setData(Data(), forType: marker) } }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        changeCount = pasteboard.changeCount
    }

    /// Whether any app has asked for the text since it went on.
    public var wasRead: Bool { provider.wasRead }

    /// Nothing else has been copied since the swap.
    public var isCurrent: Bool { pasteboard.changeCount == changeCount }

    /// Puts the saved contents back, unless something else was copied since. Returns whether it did.
    @discardableResult
    public func restore() -> Bool {
        guard let saved, isCurrent else { return false }
        saved.restore(to: pasteboard)
        return true
    }

    /// Takes the text off the pasteboard (unless something else was copied since), so a ⌘V that arrives late finds
    /// nothing to paste. `restore` and `keepText` still work afterwards.
    public func withdraw() {
        guard isCurrent else { return }
        pasteboard.clearContents()
        changeCount = pasteboard.changeCount
    }

    /// Leaves the text on the clipboard as plain, lasting text (failed paste, or restoring is off), unless something
    /// else was copied since. Returns whether it did.
    @discardableResult
    public func keepText() -> Bool {
        guard isCurrent else { return false }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        changeCount = pasteboard.changeCount
        return true
    }
}

/// Hands the text over when an app asks for it, and remembers that it did.
private final class TextProvider: NSObject, NSPasteboardItemDataProvider {
    let text: String
    private(set) var wasRead = false

    init(text: String) { self.text = text }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        wasRead = true
        item.setString(text, forType: type)
    }
}
