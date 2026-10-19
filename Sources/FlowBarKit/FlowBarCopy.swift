import Foundation
import SuperFlowCore

/// Every word the Flow Bar shows, in one place (wording from docs/specs/strings.md, rewritten for Super Flow).
public enum FlowBarCopy {
    /// A run of tooltip text; `emphasised` runs are keytips drawn bold (ui-reference.md §2.10).
    public struct Run: Equatable, Sendable {
        public var text: String
        public var emphasised: Bool
        public init(_ text: String, emphasised: Bool = false) { self.text = text; self.emphasised = emphasised }
    }

    // MARK: Tooltips

    public static func dictateTooltip(shortcut: String) -> [Run] {
        [Run("Click or hold "), Run(shortcut, emphasised: true), Run(" to dictate")]
    }
    public static let cancel = "Cancel"
    public static let finish = "Finish and paste"
    public static let openHub = "Open Super Flow"
    public static let quickNote = "Quick note"
    public static let muteSounds = "Mute sounds"
    public static let unmuteSounds = "Turn sounds on"
    public static let stopNotetaker = "Stop Notetaker"
    public static let meetingStarting = "Starting…"
    public static let meetingReconnecting = "Still recording · Reconnecting…"
    public static let meetingWrappingUp = "Wrapping up…"
    public static let preparingTooltip = "Downloading the speech model. This happens once."

    public static func words(_ count: Int) -> String {
        let number = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return count == 1 ? "\(number) word" : "\(number) words"
    }

    // MARK: Pill labels

    public static let gettingReady = "Getting ready…"
    public static func percent(_ fraction: Double) -> String { "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down)))%" }
    public static let transformDone = "Done."
    public static let seeChanges = " See changes"
    public static let cleanedUp = "Cleaned up!"
    public static let seeWhatChanged = " See what’s changed"

    // MARK: Meeting-detected prompt

    public static let promptTitle = "Meeting detected — Record?"
    public static let record = "Record"
    public static let notNow = "Not now"

    public static func platformName(_ platform: MeetingPlatform) -> String? {
        switch platform {
        case .zoom: "Zoom"
        case .teams: "Teams"
        case .googleMeet: "Google Meet"
        case .slack: "Slack"
        case .webex: "Webex"
        case .discord: "Discord"
        case .whatsapp: "WhatsApp"
        case .facetime: "FaceTime"
        case .other: nil
        }
    }

    public static func promptSubtitle(_ prompt: MeetingPrompt) -> String {
        let title = prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = platformName(prompt.platform)
        let lead: String
        switch (title.isEmpty || title == app, app) {
        case (true, let app?): lead = "On \(app)."
        case (true, nil): lead = "A call is using your microphone."
        case (false, let app?): lead = "“\(title)” on \(app)."
        case (false, nil): lead = "“\(title)”."
        }
        return lead + " Notes stay on this Mac."
    }

    public static func dontAsk(_ platform: MeetingPlatform) -> String {
        "Don’t ask for \(platformName(platform) ?? "this app")"
    }

    // MARK: Menu and notices

    public static let pasteLast = "Paste last transcript"
    public static let history = "Transcript history"
    public static let microphone = "Microphone"
    public static let languages = "Languages"
    public static let detectAutomatically = "Detect automatically"
    public static let manageLanguages = "Manage languages…"
    public static let hideForHour = "Hide for 1 hour"
    public static let settings = "Settings…"
    public static let hiddenForHour = "Flow Bar hidden for an hour"
    public static let undo = "Undo"
}
