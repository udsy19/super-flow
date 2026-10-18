import Foundation
import SuperFlowCore

/// Meeting detection (behaviour.md §20.3): a conferencing app — or a browser showing a meeting page — capturing the
/// microphone for a few seconds is a meeting; the microphone staying released through a grace period ends it (and the
/// same meeting coming back inside the grace period cancels the end). Calendar events at that time give it a title and
/// attendees, and upcoming ones produce reminders. The detector only reports; asking and recording are
/// `MeetingPromptCoordinator`'s and `MeetingRecorder`'s.
@MainActor
public final class MeetingDetector: MeetingDetecting {
    public static let shared = MeetingDetector(environment: SystemMeetingEnvironment())

    /// A candidate must hold the mic this long before it is a meeting (short mic checks and voice notes are not).
    public var startDelay: TimeInterval = 3
    /// The mic must stay released this long before the meeting ends.
    public var endGrace: TimeInterval = 15
    public var pollInterval: TimeInterval = 2
    /// An event counts as "now" from this long before its start.
    static let calendarEarlyJoin: TimeInterval = 5 * 60

    private let environment: MeetingEnvironment
    private var pollTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<MeetingSignal>.Continuation] = [:]
    /// Candidates seen but not yet past `startDelay`: key → first seen.
    private var pending: [String: Date] = [:]
    private var active: [String: DetectedMeeting] = [:]
    private var missingSince: [String: Date] = [:]
    private var reminded: Set<String> = []

    public init(environment: MeetingEnvironment) {
        self.environment = environment
    }

    public var isRunning: Bool { pollTask != nil }

    public func start() {
        guard pollTask == nil else { return }
        Log.meetings.info("Meeting detection started")
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.poll()
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
            }
        }
    }

    /// Stops watching. Meetings in progress are forgotten without an `.ended` signal: turning detection off must not stop
    /// a recording.
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        active = [:]
        pending = [:]
        missingSince = [:]
    }

    public var activeMeetings: [DetectedMeeting] { active.values.sorted { $0.detectedAt < $1.detectedAt } }

    /// Every access is a new subscription that receives every later signal.
    public var signals: AsyncStream<MeetingSignal> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[id] = continuation
            continuation.onTermination = { _ in Task { @MainActor [weak self] in self?.subscribers[id] = nil } }
        }
    }

    public func upcomingEvents(within interval: TimeInterval) async -> [CalendarEvent] {
        let now = environment.now()
        return environment.calendarEvents(from: now, to: now.addingTimeInterval(interval))
            .filter { $0.start >= now && Self.isMeetingLike($0) }
            .sorted { $0.start < $1.start }
    }

    // MARK: Polling

    /// One detection pass (the timer calls it every `pollInterval`; tests call it directly).
    public func poll() {
        let now = environment.now()
        let candidates = currentCandidates()

        for (key, candidate) in candidates {
            missingSince[key] = nil
            guard active[key] == nil else { continue }
            let firstSeen = pending[key] ?? now
            pending[key] = firstSeen
            guard now.timeIntervalSince(firstSeen) >= startDelay else { continue }
            pending[key] = nil
            let event = calendarEvent(at: now, platform: candidate.platform)
            let meeting = DetectedMeeting(id: "\(key)#\(Int(firstSeen.timeIntervalSince1970))", platform: candidate.platform,
                                          title: event?.title ?? "Untitled meeting", bundleID: key, url: event?.joinURL?.absoluteString,
                                          calendarEvent: event, detectedAt: now)
            active[key] = meeting
            Log.meetings.info("Meeting detected: \(candidate.platform.rawValue, privacy: .public) via \(key, privacy: .public)")
            emit(.started(meeting))
        }
        for key in pending.keys where candidates[key] == nil { pending[key] = nil }

        for (key, meeting) in active where candidates[key] == nil {
            let since = missingSince[key] ?? now
            missingSince[key] = since
            guard now.timeIntervalSince(since) >= endGrace else { continue }
            active[key] = nil
            missingSince[key] = nil
            // A native app releasing the mic for the whole grace period has left the call; a browser that still shows the
            // meeting page (mic switched, rejoining) is less certain.
            let confident = !AppLists.browsers.contains(key) || Self.browserMeeting(in: environment.windowTitles(of: key)) == nil
            Log.meetings.info("Meeting ended via \(key, privacy: .public), confident: \(confident)")
            emit(.ended(id: meeting.id, confident: confident))
        }

        remindUpcoming(now: now)
    }

    private struct Candidate { var platform: MeetingPlatform }

    /// Apps in a meeting right now, keyed by the app's bundle id.
    private func currentCandidates() -> [String: Candidate] {
        var candidates: [String: Candidate] = [:]
        for holder in environment.microphoneHolders() {
            let app = resolveApp(holder.bundleID)
            if let platform = AppLists.conferencingApps[app] {
                candidates[app] = Candidate(platform: platform)
            } else if AppLists.browsers.contains(app), let platform = Self.browserMeeting(in: environment.windowTitles(of: app)) {
                candidates[app] = Candidate(platform: platform)
            }
        }
        return candidates
    }

    /// The app behind a capturing process: helpers ("com.google.Chrome.helper", "com.tinyspeck.slackmacgap.helper")
    /// belong to their app, FaceTime captures through `avconferenced`, and Safari through WebKit's processes.
    func resolveApp(_ bundleID: String) -> String {
        if AppLists.conferencingApps[bundleID] != nil || AppLists.browsers.contains(bundleID) { return bundleID }
        if bundleID == "com.apple.avconferenced" { return "com.apple.FaceTime" }
        if bundleID.hasPrefix("com.apple.WebKit."), environment.isRunning("com.apple.Safari") { return "com.apple.Safari" }
        let known = Array(AppLists.conferencingApps.keys) + Array(AppLists.browsers)
        return known.filter { bundleID.hasPrefix($0 + ".") }.max { $0.count < $1.count } ?? bundleID
    }

    /// Window-title patterns of meeting pages (oss-survey.md §6): only consulted for a browser that holds the mic.
    static let browserTitlePatterns: [(pattern: String, platform: MeetingPlatform)] = [
        ("Meet - ", .googleMeet), ("Google Meet", .googleMeet), ("meet.google.com", .googleMeet),
        ("Microsoft Teams", .teams), ("Zoom Meeting", .zoom), ("Zoom Workplace", .zoom), ("app.zoom.us", .zoom),
        ("Webex", .webex), ("Huddle", .slack), ("Whereby", .other), ("Jitsi Meet", .other),
    ]

    static func browserMeeting(in titles: [String]) -> MeetingPlatform? {
        for title in titles {
            if let match = browserTitlePatterns.first(where: { title.range(of: $0.pattern, options: .caseInsensitive) != nil }) {
                return match.platform
            }
        }
        return nil
    }

    // MARK: Calendar

    static func isMeetingLike(_ event: CalendarEvent) -> Bool { event.joinURL != nil || !event.attendees.isEmpty }

    /// The event happening now that matches the platform (or the only one happening now).
    private func calendarEvent(at now: Date, platform: MeetingPlatform) -> CalendarEvent? {
        let current = environment.calendarEvents(from: now, to: now.addingTimeInterval(Self.calendarEarlyJoin))
            .filter { $0.start.addingTimeInterval(-Self.calendarEarlyJoin) <= now && $0.end > now && Self.isMeetingLike($0) }
        return current.first { $0.platform == platform } ?? (current.count == 1 && current[0].platform == nil ? current[0] : nil)
    }

    private func remindUpcoming(now: Date) {
        let lead = Defaults[.meetingReminderLead]
        guard Defaults[.notetakerCalendarNotificationsEnabled], lead != .never else { return }
        let window = TimeInterval(lead.rawValue)
        for event in environment.calendarEvents(from: now, to: now.addingTimeInterval(window + pollInterval))
        where Self.isMeetingLike(event) && !reminded.contains(event.id) {
            let startsIn = event.start.timeIntervalSince(now)
            guard startsIn > 0, startsIn <= window else { continue }
            reminded.insert(event.id)
            emit(.calendarReminder(event, startsIn: startsIn))
        }
    }

    private func emit(_ signal: MeetingSignal) {
        for continuation in subscribers.values { continuation.yield(signal) }
    }
}
