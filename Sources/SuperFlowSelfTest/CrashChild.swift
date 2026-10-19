import Foundation
import SuperFlowCore

/// Crash tests run the self-test binary a second time as a child (`--crash-child <scenario> <base folder> <defaults
/// suite>`): the child records with fakes into the parent's throwaway folder, prints `ready` and a value, and the parent
/// kills exactly that process with SIGKILL, then checks what the next launch recovers from the folder.
enum CrashChild {
    static let flag = "--crash-child"
    static let ready = "CRASH-CHILD-READY "

    /// In the child: runs the scenario; never returns.
    @MainActor static func run(_ scenario: String) -> Never {
        switch scenario {
        case "meeting": meetingCrashChild()
        default:
            print("unknown crash scenario \(scenario)")
            exit(2)
        }
    }

    /// In the parent: starts the child on `base`, waits for its ready line, kills it with SIGKILL and returns the value
    /// it printed; nil when it never got ready.
    static func runAndKill(_ scenario: String, base: URL, timeout: TimeInterval = 60) -> String? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let child = Process()
        child.executableURL = executable
        child.arguments = [flag, scenario, base.path, defaultsSuite]
        child.environment = ProcessInfo.processInfo.environment.filter { $0.key != "SUPERFLOW_SELFTEST_ONLY" }
        let output = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { return nil }
        let lines = LineCollector()
        output.fileHandleForReading.readabilityHandler = { handle in lines.add(handle.availableData) }
        let deadline = Date().addingTimeInterval(timeout)
        var value: String?
        while value == nil, child.isRunning, Date() < deadline {
            value = lines.first { $0.hasPrefix(ready) }.map { String($0.dropFirst(ready.count)) }
            if value == nil { Thread.sleep(forTimeInterval: 0.02) }
        }
        // Only the process this test started is ever signalled.
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        child.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        return value
    }
}

/// Collects a pipe's output as lines, from the pipe's own queue.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var lines: [String] = []

    func add(_ data: Data) {
        lock.withLock {
            buffer += String(decoding: data, as: UTF8.self)
            while let newline = buffer.firstIndex(of: "\n") {
                lines.append(String(buffer[..<newline]))
                buffer = String(buffer[buffer.index(after: newline)...])
            }
        }
    }

    func first(where match: (String) -> Bool) -> String? {
        lock.withLock { lines.first(where: match) }
    }
}
