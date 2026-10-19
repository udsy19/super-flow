import AppKit

/// An editor's save after a pause in typing, and at once when the editor goes away or the app quits, so the last
/// keystrokes before ⌘Q are never lost.
@MainActor
public final class DebouncedSave: ObservableObject {
    private let delay: TimeInterval
    private var pending: (() -> Void)?
    private var timer: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    public init(delay: TimeInterval) {
        self.delay = delay
        observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Runs `save` after the delay, unless a newer change replaces it first.
    public func schedule(_ save: @escaping () -> Void) {
        pending = save
        timer?.cancel()
        let delay = delay
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Saves whatever is waiting, now.
    public func flush() {
        timer?.cancel()
        timer = nil
        let save = pending
        pending = nil
        save?()
    }
}
