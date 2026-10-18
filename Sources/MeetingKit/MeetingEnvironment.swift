import AppKit
import ApplicationServices
import CoreAudio
import EventKit
import Foundation
import SuperFlowCore

// What the meeting detector reads from the Mac (behaviour.md §20.3, oss-survey.md §6). Read-only: nothing here opens
// a microphone, records, or asks for a permission; without Accessibility or Calendar access the answers are empty.

/// A process that is capturing audio input right now.
public struct MicrophoneHolder: Hashable, Sendable {
    public var pid: pid_t
    public var bundleID: String

    public init(pid: pid_t, bundleID: String) {
        self.pid = pid; self.bundleID = bundleID
    }
}

@MainActor
public protocol MeetingEnvironment: AnyObject {
    /// Processes capturing audio input, other than Super Flow.
    func microphoneHolders() -> [MicrophoneHolder]
    /// Whether an app with this bundle id is running.
    func isRunning(_ bundleID: String) -> Bool
    /// Titles of the app's windows (Accessibility); empty without the permission.
    func windowTitles(of bundleID: String) -> [String]
    /// Calendar events overlapping the range (EventKit, read-only); empty without Calendar access.
    func calendarEvents(from: Date, to: Date) -> [CalendarEvent]
    func now() -> Date
}

/// The real Mac: Core Audio process objects (macOS 14+), NSWorkspace, Accessibility and EventKit.
@MainActor
final class SystemMeetingEnvironment: MeetingEnvironment {
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private lazy var eventStore = EKEventStore()
    private var eventCache: (range: ClosedRange<Date>, fetched: Date, events: [CalendarEvent])?

    func now() -> Date { Date() }

    func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func microphoneHolders() -> [MicrophoneHolder] {
        guard CoreAudioProbe.anyInputDeviceRunning() else { return [] }
        return CoreAudioProbe.processObjects().compactMap { object in
            guard CoreAudioProbe.uint32(object, kAudioProcessPropertyIsRunningInput) == 1,
                  let pid = CoreAudioProbe.pid(object), pid != ownPID else { return nil }
            let bundleID = CoreAudioProbe.string(object, kAudioProcessPropertyBundleID)
                ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            return bundleID.map { MicrophoneHolder(pid: pid, bundleID: $0) }
        }
    }

    func windowTitles(of bundleID: String) -> [String] {
        guard AXIsProcessTrusted() else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).flatMap { app -> [String] in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.25)
            var windows: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
                  let list = windows as? [AXUIElement] else { return [] }
            return list.compactMap { window in
                var title: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success else { return nil }
                return title as? String
            }
        }
    }

    func calendarEvents(from start: Date, to end: Date) -> [CalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        // One EventKit query a minute covers the detector's polling.
        if let cache = eventCache, cache.range.contains(start), cache.range.contains(end), Date().timeIntervalSince(cache.fetched) < 60 {
            return cache.events.filter { $0.end > start && $0.start < end }
        }
        let rangeEnd = max(end, start.addingTimeInterval(3600))
        let predicate = eventStore.predicateForEvents(withStart: start.addingTimeInterval(-3600), end: rangeEnd, calendars: nil)
        let events = eventStore.events(matching: predicate).filter { !$0.isAllDay }.map(Self.calendarEvent)
        eventCache = (start.addingTimeInterval(-3600)...rangeEnd, Date(), events)
        return events.filter { $0.end > start && $0.start < end }
    }

    private static func calendarEvent(_ event: EKEvent) -> CalendarEvent {
        let attendees = (event.attendees ?? []).map { participant in
            let email = participant.url.absoluteString.hasPrefix("mailto:") ? String(participant.url.absoluteString.dropFirst(7)) : nil
            return Participant(name: participant.name ?? email ?? "", email: email)
        }
        let joinURL = CalendarLinks.joinURL(in: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 })
        return CalendarEvent(id: event.eventIdentifier ?? event.calendarItemIdentifier, title: event.title ?? "", start: event.startDate,
                             end: event.endDate, attendees: attendees, joinURL: joinURL,
                             platform: joinURL.flatMap(AppLists.platform(forJoinURL:)))
    }
}

/// Conference links in a calendar event's URL, location or notes (§20.10).
enum CalendarLinks {
    static func joinURL(in texts: [String]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let url = match.url, AppLists.platform(forJoinURL: url) != nil { return url }
            }
        }
        return nil
    }
}

/// Core Audio's process objects: who is capturing input (kAudioProcessPropertyIsRunningInput, macOS 14+).
enum CoreAudioProbe {
    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func objects(_ owner: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(owner, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(owner, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func processObjects() -> [AudioObjectID] {
        objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    }

    /// The cheap pre-check: is any input device running for some process?
    static func anyInputDeviceRunning() -> Bool {
        objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).contains { device in
            var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr, size > 0 else { return false }
            return uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
        }
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func pid(_ object: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }
}
