import Foundation

/// "Import from Super Flow (direct download)" for the Store edition (docs/app-store/architecture.md §Data import).
///
/// Non-destructive by construction: the direct edition's folder is only read (copied, never moved), and the Store
/// edition's own data is kept beside the imported copy. The database is open while the app runs, so an import is two
/// steps: `stage` copies the folder the user picked next to `support`, and `finishPending` (called at launch before the
/// store opens) swaps it in, keeping the previous folder as "Super Flow (before import <date>)".
public enum DataImport {
    public enum Failure: LocalizedError, Equatable {
        case notASuperFlowFolder

        public var errorDescription: String? {
            switch self {
            case .notASuperFlowFolder: "That folder has no Super Flow data (store.sqlite)."
            }
        }
    }

    /// Where a staged import waits for the next launch.
    public static var staging: URL {
        SuperFlowPaths.base.appendingPathComponent(SuperFlowPaths.supportFolderName + " (import)", isDirectory: true)
    }

    public static var hasPending: Bool { FileManager.default.fileExists(atPath: staging.path) }

    /// Copies `source` (the folder the user picked) to the staging folder. Throws when it isn't Super Flow data.
    public static func stage(from source: URL, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: source.appendingPathComponent("store.sqlite").path) else {
            throw Failure.notASuperFlowFolder
        }
        try? fileManager.removeItem(at: staging)
        try fileManager.copyItem(at: source, to: staging)
        // A crash-time lock or temporary file from the other edition means nothing here.
        for leftover in ["store.sqlite-shm"] { try? fileManager.removeItem(at: staging.appendingPathComponent(leftover)) }
    }

    /// Swaps a staged import in; returns where the previous data went (nil when nothing was pending). Call before the
    /// store opens.
    @discardableResult
    public static func finishPending(now: Date = Date(), fileManager: FileManager = .default) throws -> URL? {
        guard hasPending else { return nil }
        let current = SuperFlowPaths.base.appendingPathComponent(SuperFlowPaths.supportFolderName, isDirectory: true)
        var kept: URL?
        if fileManager.fileExists(atPath: current.path) {
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            let previous = SuperFlowPaths.base.appendingPathComponent("\(SuperFlowPaths.supportFolderName) (before import \(stamp))",
                                                                       isDirectory: true)
            try fileManager.moveItem(at: current, to: previous)
            kept = previous
        }
        try fileManager.moveItem(at: staging, to: current)
        return kept
    }

    /// Copies the direct edition's settings (its preferences plist, picked by the user) into this edition's defaults.
    /// Keys owned by the system are skipped. Returns how many settings were imported.
    @discardableResult
    public static func importSettings(from plist: URL, into defaults: UserDefaults = Defaults.store) throws -> Int {
        let data = try Data(contentsOf: plist)
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return 0 }
        let skipped = ["NS", "Apple", "com.apple.", "WebKit"]
        var count = 0
        for (key, value) in values where !skipped.contains(where: key.hasPrefix) {
            defaults.set(value, forKey: key)
            count += 1
        }
        return count
    }
}
