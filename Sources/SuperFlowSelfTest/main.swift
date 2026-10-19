import AppKit
import SuperFlowCore

// Headless logic checks (the Command Line Tools have no XCTest). Run: swift run SuperFlowSelfTest
setvbuf(stdout, nil, _IOLBF, 0)   // results stay in order with the engines' stderr logs, and survive a crash
var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, file: String = #fileID, line: Int = #line) {
    if !cond() { failures += 1; print("✗ \(file):\(line) \(msg)") }
}
enum SelfTest { nonisolated(unsafe) static var cases: [(String, () -> Void)] = [] }

/// Runs async work to completion while the main run loop keeps turning.
@MainActor
func complete<T>(_ seconds: TimeInterval = 300, _ work: @escaping @MainActor () async throws -> T) -> Result<T, Error>? {
    var result: Result<T, Error>?
    Task { @MainActor in
        do { result = .success(try await work()) } catch { result = .failure(error) }
    }
    let deadline = Date().addingTimeInterval(seconds)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return result
}

// Files and settings live in throwaway places, never the real Application Support folder or preferences.
SuperFlowPaths.base = FileManager.default.temporaryDirectory.appendingPathComponent("superflow-selftest-\(UUID().uuidString)")
let defaultsSuite = "superflow-selftest-\(UUID().uuidString)"
Defaults.store = UserDefaults(suiteName: defaultsSuite)!

// A crash-test child (see `CrashChild`): the parent's folder and settings suite, one scenario, killed by the parent.
if let i = CommandLine.arguments.firstIndex(of: CrashChild.flag), CommandLine.arguments.count > i + 3 {
    SuperFlowPaths.base = URL(fileURLWithPath: CommandLine.arguments[i + 2])
    Defaults.store = UserDefaults(suiteName: CommandLine.arguments[i + 3])!
    MainActor.assumeIsolated { CrashChild.run(CommandLine.arguments[i + 1]) }
}

// Each module owns Sources/SuperFlowSelfTest/<Module>Tests.swift and its register function.
registerCoreTests()
registerFlowStoreTests()
registerUpdateKitTests()
registerAudioKitTests()
registerSpeechKitTests()
registerInsertionKitTests()
registerFlowBarKitTests()
registerCleanupKitTests()
registerCleanupEvalTests()
registerMeetingKitTests()
registerHubKitTests()
registerEndToEndTests()
registerNativeSmokeTests()

// `SUPERFLOW_SELFTEST_ONLY=FlowStore.,MeetingKit.crash` runs only the cases whose names start with one of the prefixes.
let only = ProcessInfo.processInfo.environment["SUPERFLOW_SELFTEST_ONLY"]?.split(separator: ",").map(String.init) ?? []
for (name, run) in SelfTest.cases where only.isEmpty || only.contains(where: name.hasPrefix) {
    let before = failures; run()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}
try? FileManager.default.removeItem(at: SuperFlowPaths.base)
UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
// cfprefsd leaves the emptied domain behind as a plist named after this run's suite; remove exactly that file.
CFPreferencesAppSynchronize(defaultsSuite as CFString)
try? FileManager.default.removeItem(at: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Preferences/\(defaultsSuite).plist"))
print(failures == 0 ? "All self-tests passed." : "\(failures) failure(s).")
exit(failures == 0 ? 0 : 1)
