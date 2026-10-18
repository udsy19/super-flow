import AppKit
import AVFoundation
import Combine
import EventKit
import IOKit.hid
import SuperFlowCore

/// The permissions onboarding and Settings ask for (behaviour.md §15), with live status.
enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone, accessibility, inputMonitoring, systemAudio, calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .systemAudio: "System audio"
        case .calendar: "Calendar"
        }
    }

    var purpose: String {
        switch self {
        case .microphone: "Only while you dictate or record a meeting."
        case .accessibility: "Puts your words into the field you're typing in."
        case .inputMonitoring: "Notices when you hold Fn or press a shortcut."
        case .systemAudio: "Hears the other people on a call while recording."
        case .calendar: "Meeting titles and attendees. Read-only."
        }
    }

    var symbol: String {
        switch self {
        case .microphone: "mic"
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard"
        case .systemAudio: "speaker.wave.2"
        case .calendar: "calendar"
        }
    }

    var isRequired: Bool { self == .microphone || self == .accessibility || self == .inputMonitoring }

    var pane: Permissions.Pane {
        switch self {
        case .microphone: .microphone
        case .accessibility: .accessibility
        case .inputMonitoring: .inputMonitoring
        case .systemAudio: .audioCapture
        case .calendar: .calendars
        }
    }
}

enum PermissionStatus: Equatable {
    case granted, denied, notDetermined, unavailable
}

/// Polls the permissions once a second while something shows them (System Settings changes don't notify).
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    @Published private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    /// Fixed statuses for the offscreen renders; nil reads the system.
    var fixed: [PermissionKind: PermissionStatus]?
    private var timer: Timer?
    private var watchers = 0
    private var askedAccessibility = false
    private static let systemAudioAllowedKey = Defaults.Key<Bool>("hubKit.systemAudioAllowed", default: false)

    init(fixed: [PermissionKind: PermissionStatus]? = nil) {
        self.fixed = fixed
        refresh()
    }

    func status(_ kind: PermissionKind) -> PermissionStatus { statuses[kind] ?? .notDetermined }

    var requiredGranted: Bool { PermissionKind.allCases.filter(\.isRequired).allSatisfy { status($0) == .granted } }

    func watch() {
        watchers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { timer?.invalidate(); timer = nil }
    }

    func refresh() {
        if let fixed { statuses = fixed; return }
        var s: [PermissionKind: PermissionStatus] = [:]
        switch Permissions.microphone {
        case .authorized: s[.microphone] = .granted
        case .denied, .restricted: s[.microphone] = .denied
        default: s[.microphone] = .notDetermined
        }
        s[.accessibility] = Permissions.isAccessibilityTrusted ? .granted : .notDetermined
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: s[.inputMonitoring] = .granted
        case kIOHIDAccessTypeDenied: s[.inputMonitoring] = .denied
        default: s[.inputMonitoring] = .notDetermined
        }
        if Services.audio?.systemAudioMethod == .unsupported {
            s[.systemAudio] = .unavailable
        } else {
            s[.systemAudio] = Defaults[Self.systemAudioAllowedKey] ? .granted : .notDetermined
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: s[.calendar] = .granted
        case .denied, .restricted, .writeOnly: s[.calendar] = .denied
        default: s[.calendar] = .notDetermined
        }
        if s != statuses { statuses = s }
    }

    /// Asks once where macOS allows it, otherwise opens the right System Settings pane.
    func request(_ kind: PermissionKind) {
        switch kind {
        case .microphone:
            if status(.microphone) == .notDetermined {
                Task { @MainActor in _ = await Permissions.requestMicrophone(); refresh() }
            } else { Permissions.open(.microphone) }
        case .accessibility:
            // The system prompt offers System Settings itself; later clicks go straight there.
            if askedAccessibility { Permissions.open(.accessibility) } else { askedAccessibility = true; Permissions.requestAccessibility() }
        case .inputMonitoring:
            if status(.inputMonitoring) == .notDetermined { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) } else { Permissions.open(.inputMonitoring) }
        case .systemAudio:
            guard let audio = Services.audio else { Permissions.open(.audioCapture); return }
            Task { @MainActor in
                do {
                    try await audio.startSystemAudio()
                    audio.stopSystemAudio()
                    Defaults[Self.systemAudioAllowedKey] = true
                } catch {
                    Permissions.open(.audioCapture)
                }
                refresh()
            }
        case .calendar:
            Defaults[.calendarAccessRequested] = true
            if status(.calendar) == .notDetermined {
                Task { @MainActor in
                    _ = try? await EKEventStore().requestFullAccessToEvents()
                    refresh()
                }
            } else { Permissions.open(.calendars) }
        }
        refresh()
    }
}
