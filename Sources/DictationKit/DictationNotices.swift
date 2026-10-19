import Foundation
import SuperFlowCore

/// The cards the coordinator shows above the Flow Bar (behaviour.md §18; wording from strings.md rewritten for Super
/// Flow): every failure mapped to a plain explanation and, where there is one, the fix.
enum DictationNotices {
    static let openSettings = "Open Settings"
    static let openHistory = "Open History"
    static let openModels = "Open Models"
    static let turnOn = "Turn on"

    static func noSpeechModel() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.noModel", title: "No speech model yet",
                            subtitle: "Automatic downloads are off. Download one in Settings › Models to dictate.", variant: .error, timeout: nil,
                            actions: [openModels])
    }

    static func secureField() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.secureField", title: "Can't dictate into a password field",
                            subtitle: "Click into another field and try again.", variant: .error)
    }

    static func microphoneDenied() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.micDenied", title: "Microphone access required",
                            subtitle: "Allow Super Flow in System Settings › Privacy & Security › Microphone.", variant: .error, timeout: nil,
                            actions: [openSettings])
    }

    static func microphoneFailed(_ message: String) -> FlowBarNotification {
        FlowBarNotification(id: "dictation.micFailed", title: "Microphone error",
                            subtitle: "\(message) Try another microphone from the Flow Bar's menu.", variant: .error)
    }

    static func noAudio() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.noAudio", title: "We're not hearing anything",
                            subtitle: "Check that the right microphone is selected and not muted.", variant: .error)
    }

    static func noSpeech() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.noSpeech", title: "We couldn't hear you", subtitle: "We didn't pick up any speech from your microphone.",
                            variant: .mini, timeout: 5)
    }

    static func gettingReady(fraction: Double?) -> FlowBarNotification {
        let progress = fraction.map { " \(Int(($0 * 100).rounded(.down)))% so far." } ?? ""
        return FlowBarNotification(id: "dictation.preparing", title: "Still getting ready",
                                   subtitle: "The speech model is downloading.\(progress) Try again in a moment.", variant: .alert)
    }

    static func otherKey(shortcut: String) -> FlowBarNotification {
        FlowBarNotification(id: "dictation.otherKey", title: "Another key was pressed while starting",
                            subtitle: "Hold only \(shortcut) to dictate.", variant: .alert, timeout: 6)
    }

    static func tooLong() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.tooLong", title: "Dictation stopped at 20 minutes",
                            subtitle: "Super Flow supports up to 20 minutes per session. What you said has been inserted.", variant: .alert)
    }

    static func almostTooLong() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.almostTooLong", title: "Less than a minute left",
                            subtitle: "A session ends at 20 minutes; start another afterwards.", variant: .alert, timeout: 20)
    }

    static func accessibilityRequired() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.accessibility", title: "Accessibility access required",
                            subtitle: "Your text is on the clipboard. Allow Super Flow in Privacy & Security › Accessibility to paste it for you.",
                            variant: .error, timeout: nil, actions: [openSettings])
    }

    static func leftOnClipboard() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.clipboard", title: "Copied to the clipboard",
                            subtitle: "Nothing was selected to paste into. Press ⌘V where you want the text.", variant: .alert)
    }

    static func blockedSecureInsert() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.secureInsert", title: "That field is a password field",
                            subtitle: "Nothing was pasted. Your words are in History.", variant: .error, actions: [openHistory])
    }

    static func transcriptionFailed(_ message: String) -> FlowBarNotification {
        FlowBarNotification(id: "dictation.failed", title: "Something's not right", subtitle: message, variant: .error)
    }

    static func secureInput(owner: String?) -> FlowBarNotification {
        let who = owner ?? "Another app"
        return FlowBarNotification(id: "dictation.secureInput", title: "Super Flow's shortcuts are blocked",
                                   subtitle: "\(who) has Secure Keyboard Entry turned on. Quit or restart it to clear the block.",
                                   variant: .alert, timeout: nil)
    }

    static func commandModeOff() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.commandModeOff", title: "Command Mode is turned off",
                            subtitle: "Turn it on in Settings › Experimental to edit selected text by voice.", variant: .alert, actions: [turnOn])
    }

    static func firstCommandMode() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.commandModeFirst", title: "Using Command Mode (beta)",
                            subtitle: "Say what to do with the selected text, then let go.", variant: .mini, timeout: 6)
    }

    static func transformNoSelection(shortcut: String) -> FlowBarNotification {
        FlowBarNotification(id: "transform.noSelection", title: "Select text to apply a transform",
                            subtitle: "Highlight any text, then press \(shortcut).", variant: .alert)
    }

    static func transformDuringDictation(_ name: String) -> FlowBarNotification {
        FlowBarNotification(id: "transform.dictating", title: "\(name) doesn't work while dictating", variant: .alert, timeout: 5)
    }

    static func dictationDuringTransform(_ name: String) -> FlowBarNotification {
        FlowBarNotification(id: "transform.running", title: "Can't dictate while \(name) is running", variant: .alert, timeout: 5)
    }

    static func transformUnchanged() -> FlowBarNotification {
        FlowBarNotification(id: "transform.unchanged", title: "Your text looks good!", variant: .success, timeout: 5)
    }

    static func transformCopied() -> FlowBarNotification {
        FlowBarNotification(id: "transform.copied", title: "Copied!", subtitle: "Press ⌘V to paste the result.", variant: .success, timeout: 5)
    }

    static func transformFailed(_ error: Error) -> FlowBarNotification {
        let transform = error as? TransformError
        return FlowBarNotification(id: "transform.failed", title: error.localizedDescription,
                                   subtitle: transform?.recoverySuggestion, variant: transform == .modelNotReady ? .alert : .error)
    }

    static func notetakerFailed(_ error: Error) -> FlowBarNotification {
        FlowBarNotification(id: "notetaker.failed", title: "Couldn't start the Notetaker", subtitle: error.localizedDescription, variant: .error)
    }

    static func learned(_ words: [String]) -> FlowBarNotification {
        FlowBarNotification(id: "dictation.learned", title: "Added \(words.joined(separator: ", ")) to your Dictionary",
                            subtitle: "Super Flow learned this from your edit.", variant: .mini, timeout: 6)
    }

    static func globeKey() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.globeKey", title: "The 🌐 key also starts Apple's Dictation",
                            subtitle: "Set \"Press 🌐 key to\" to Do Nothing in System Settings › Keyboard so a double tap doesn't open it.",
                            variant: .alert, timeout: nil, actions: [openSettings])
    }
}
