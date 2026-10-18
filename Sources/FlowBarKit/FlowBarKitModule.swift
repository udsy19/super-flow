import AppKit
import SuperFlowCore

/// Registers this module's service in `Services` (called once at launch).
public enum FlowBarKitModule {
    @MainActor public static func install() {
        Services.flowBar = FlowBar.shared
    }
}

/// Placeholder Flow Bar (behaviour.md §5, ui-reference.md §2): keeps the state and logs what it would show. The
/// non-activating panel, the pill states, waveform, cards and the meeting prompt are the module's next step.
@MainActor
final class FlowBar: FlowBarPresenting {
    static let shared = FlowBar()
    private(set) var state: FlowBarState = .hidden

    func setState(_ state: FlowBarState) { self.state = state }
    func setLevel(_ level: Float) {}
    func setEdge(_ edge: FlowBarEdge) {}
    func setRestingVisible(_ visible: Bool) {}

    func show(_ notification: FlowBarNotification, onAction: @escaping (String) -> Void) {
        Log.bar.info("Notification \(notification.id, privacy: .public): \(notification.title, privacy: .public)")
    }

    func dismiss(notificationID: String) {}

    func showMeetingPrompt(_ prompt: MeetingPrompt, onAnswer: @escaping (MeetingPromptAnswer) -> Void) {
        Log.bar.info("Meeting detected: \(prompt.title, privacy: .public)")
        onAnswer(.dismissed)
    }

    func showLiveText(_ text: String?) {}
}
