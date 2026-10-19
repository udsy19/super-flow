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

    static func gettingReady(fraction: Double?, kept: Bool = false) -> FlowBarNotification {
        let progress = fraction.map { " \(Int(($0 * 100).rounded(.down)))% so far." } ?? ""
        return FlowBarNotification(id: "dictation.preparing", title: "Still getting ready",
                                   subtitle: "The speech model is downloading.\(progress) " + (kept ? "Your audio is saved in History; retry it from there once it's ready."
                                                                                                    : "Try again in a moment."),
                                   variant: .alert, actions: kept ? [openHistory] : [])
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

    static let copy = "Copy"

    /// The paste didn't land (no text field had focus, or the app didn't take it). The user's clipboard is untouched;
    /// the words are in History, on the paste-last shortcut, and one click away.
    static func pasteFailed(shortcut: String) -> FlowBarNotification {
        FlowBarNotification(id: "dictation.clipboard", title: "Click a textbox and use \(shortcut) to paste",
                            subtitle: "Nothing took the text, so your words are saved in History.", variant: .alert, timeout: 20, actions: [copy])
    }

    /// A Transform's result couldn't replace the selection.
    static func transformNotPasted() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.clipboard", title: "Super Flow can't paste right now",
                            subtitle: "Copy the result and paste it where you want it.", variant: .alert, timeout: 20, actions: [copy])
    }

    /// History couldn't save the dictation (a full disk, a broken store): the text stays on the paste-last shortcut.
    static func historyNotSaved(_ error: Error, shortcut: String) -> FlowBarNotification {
        let full = error as? StoreError == .storageFull
        return FlowBarNotification(id: "dictation.notSaved", title: full ? "Storage Full" : "Couldn't save to History",
                                   subtitle: (full ? "You are running out of space on your computer." : error.localizedDescription)
                                       + " \(shortcut) still pastes your last dictation.", variant: .error, timeout: nil)
    }

    /// The microphone stopped delivering audio mid-dictation.
    static func microphoneLost() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.micLost", title: "Microphone disconnected",
                            subtitle: "We kept what you said before it stopped. Check the microphone, then keep going.", variant: .alert)
    }

    /// Dictations a crash or force quit interrupted were found at launch.
    static func recovered(count: Int) -> FlowBarNotification {
        FlowBarNotification(id: "dictation.recovered", title: count == 1 ? "Recovered an interrupted dictation" : "Recovered \(count) interrupted dictations",
                            subtitle: "Super Flow stopped while you were dictating. Your audio was saved; retry it from History.",
                            variant: .success, timeout: nil, actions: [openHistory])
    }

    /// The chosen speech model is installed but won't load.
    static func speechModelFailed(fallback: Bool) -> FlowBarNotification {
        FlowBarNotification(id: "dictation.speechModel", title: "The speech model couldn't load",
                            subtitle: fallback ? "Dictation uses another downloaded model for now. Check it in Settings › Models."
                                               : "Dictation can't start until it's fixed. Check it in Settings › Models.",
                            variant: fallback ? .alert : .error, timeout: nil, actions: [openModels])
    }

    /// The cleanup model is installed but won't load.
    static func cleanupModelFailed() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.cleanupModel", title: "The cleanup model couldn't load",
                            subtitle: "Dictation keeps working with basic cleanup. Check it in Settings › Models.", variant: .alert, timeout: nil,
                            actions: [openModels])
    }

    static func blockedSecureInsert() -> FlowBarNotification {
        FlowBarNotification(id: "dictation.secureInsert", title: "That field is a password field",
                            subtitle: "Nothing was pasted. Your words are in History.", variant: .error, actions: [openHistory])
    }

    static func transcriptionFailed(_ message: String, kept: Bool = false) -> FlowBarNotification {
        FlowBarNotification(id: "dictation.failed", title: "Something's not right",
                            subtitle: message + (kept ? " Your audio is saved; you can recover it from History." : ""), variant: .error,
                            actions: kept ? [openHistory] : [])
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
