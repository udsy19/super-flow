import AppKit
import SuperFlowCore
import FlowStore
import AudioKit
import SpeechKit
import CleanupKit
import InsertionKit
import FlowBarKit
import HubKit
import MeetingKit
import UpdateKit

/// The app shell (behaviour.md §1, owner decisions): a regular Dock app with the hub window and the floating Flow
/// Bar, no menu bar item. Everything else lives in the feature modules, reached through `Services`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dictation = DictationCoordinator()

    /// Installs the modules in dependency order (behaviour.md §22.2): the store first, then models and engines, the
    /// text pipeline, insertion and hotkeys, meetings, the Flow Bar, the hub, updates.
    func applicationWillFinishLaunching(_ notification: Notification) {
        FlowStoreModule.install()
        SpeechKitModule.install()
        AudioKitModule.install()
        CleanupKitModule.install()
        InsertionKitModule.install()
        MeetingKitModule.install()
        FlowBarKitModule.install()
        HubKitModule.install()
        UpdateKitModule.install()
        Services.dictation = dictation
        NSApp.mainMenu = MainMenu.make()
        NSApp.setActivationPolicy(Defaults[.hideAppInDock] ? .accessory : .regular)
    }

    /// The launch sequence: retention sweeps, automatic model downloads, hotkeys, meeting detection, the Flow Bar,
    /// onboarding until completed, background updates.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.app.info("Super Flow \(version, privacy: .public) launched")
        runRetention()
        Services.models.startAutomaticDownloads()
        do { try Services.hotkeys.start() } catch { Log.hotkeys.error("Hotkeys unavailable: \(error.localizedDescription, privacy: .public)") }
        if Defaults[.meetingDetection] == .notify { Services.meetingDetector.start() }
        Services.flowBar.setEdge(Defaults[.flowBarEdge])
        Services.flowBar.setState(Services.onboarding.isCompleted && !Defaults[.hideFlowBarPermanently] ? .resting : .hidden)
        if !Services.onboarding.isCompleted { Services.onboarding.show() } else { Services.hub.show(.home) }
        Services.updates.start()
    }

    /// Dictation history under the local data policy, dictation audio past 14 days, meeting audio past the retention
    /// (owner decision: 30 days), transcripts past theirs (never by default).
    private func runRetention() {
        let now = Date()
        if let cutoff = RetentionPolicy.dictationCutoff(policy: Defaults[.localDataPolicy], now: now) {
            _ = try? Services.history.pruneDictations(before: cutoff)
        }
        if let cutoff = RetentionPolicy.cutoff(days: Defaults[.meetingTranscriptRetentionDays], now: now) {
            _ = try? Services.meetings.pruneMeetings(before: cutoff)
        }
        Services.meetingRecorder.pruneAudio(now: now)
    }

    /// Reopening the app (Dock, Finder, Spotlight) shows the hub.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Services.hub.show(.home)
        return false
    }

    /// `superflow://` URLs (behaviour.md §1.3): `open`, `open/<page>`, `start-hands-free`, `stop-hands-free`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch AppRoute(url: url) {
            case .open(let page)?: Services.hub.show(page)
            case .startHandsFree?: if Services.dictation.status.canStart { Services.dictation.start(mode: .handsFree, source: .deeplink) }
            case .stopHandsFree?: if Services.dictation.status.isRecording { Services.dictation.finish() }
            case nil: Log.app.error("Ignored an unknown URL: \(url.absoluteString, privacy: .public)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
