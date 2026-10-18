import Foundation
import SuperFlowCore

/// Registers this module's services in `Services` (called once at launch).
public enum MeetingKitModule {
    @MainActor public static func install() {
        Services.meetingDetector = MeetingDetector.shared
        Services.meetingRecorder = MeetingRecorder.shared
        Services.summarizer = MeetingSummarizer.shared
        MeetingPromptCoordinator.shared.start()
        // After the launch sequence has installed every service: finish meetings a crash or quit interrupted.
        Task { @MainActor in MeetingRecorder.shared.recoverInterruptedMeetings() }
    }
}
