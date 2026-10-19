import Foundation
import SuperFlowCore

/// The cards the recorder shows above the Flow Bar (behaviour.md §18 Notetaker; wording from strings.md rewritten for
/// Super Flow): what happened to a recording and, where there is one, the fix.
enum MeetingNotices {
    static let turnOn = "Turn on"
    static let viewMeeting = "View meeting"
    static let microphoneSettings = "Microphone settings"

    /// System audio couldn't be captured: the meeting records the microphone only.
    static func systemAudioOff(canTurnOn: Bool) -> FlowBarNotification {
        FlowBarNotification(id: "meeting.systemAudioOff", title: "System audio turned off",
                            subtitle: "You're recording your mic only. Turn system audio back on and restart the meeting to capture others.",
                            variant: .alert, timeout: nil, actions: canTurnOn ? [turnOn] : [])
    }

    /// The disk filled up (or nearly): the recording stopped and kept everything so far.
    static func storageFull() -> FlowBarNotification {
        FlowBarNotification(id: "meeting.storageFull", title: "Storage Full",
                            subtitle: "Your Mac is almost out of space, so the Notetaker stopped. Everything recorded so far is saved.",
                            variant: .error, timeout: nil, actions: [viewMeeting])
    }

    /// The Mac went to sleep or another user took over the screen during a recording.
    static func stoppedForSleep() -> FlowBarNotification {
        FlowBarNotification(id: "meeting.stoppedForSleep", title: "Notetaker stopped",
                            subtitle: "Your Mac went to sleep, so the recording stopped. Everything recorded so far is saved.",
                            variant: .alert, timeout: nil, actions: [viewMeeting])
    }

    /// The microphone stopped delivering audio and couldn't be restarted.
    static func microphoneLost() -> FlowBarNotification {
        FlowBarNotification(id: "meeting.micLost", title: "Notetaker isn't hearing audio from your mic",
                            subtitle: "Check that the right mic is connected and not muted. System audio is still being recorded.",
                            variant: .alert, timeout: nil, actions: [microphoneSettings])
    }

    /// A recording a crash or quit interrupted was found at launch and is being finished.
    static func recovered(startedAt: Date) -> FlowBarNotification {
        FlowBarNotification(id: "meeting.recovered", title: MeetingNotices.recoveredTitle(startedAt),
                            subtitle: "Super Flow stopped while it was recording. The audio was kept; the transcript and notes follow shortly.",
                            variant: .success, timeout: nil, actions: [viewMeeting])
    }

    /// "Recovered recording from Oct 19, 3:42 PM": the card's title and the title of a recording whose row was lost.
    static func recoveredTitle(_ startedAt: Date) -> String {
        "Recovered recording from \(startedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
