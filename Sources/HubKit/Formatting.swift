import Foundation
import SuperFlowCore

/// Pure formatting and grouping rules the hub pages share. Public so the self-test can check them.
public enum HubFormat {
    // MARK: Dates

    /// "Today", "Yesterday", "Monday" within the week, then "March 4" (or "March 4, 2025" in another year).
    public static func dayTitle(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days > 0 && days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    /// Items grouped by day, newest day first, keeping the items' order inside a day.
    public static func groupByDay<T>(_ items: [T], date: (T) -> Date, now: Date = Date(),
                                     calendar: Calendar = .current) -> [(title: String, items: [T])] {
        var groups: [(day: Date, items: [T])] = []
        for item in items {
            let day = calendar.startOfDay(for: date(item))
            if let last = groups.indices.last, groups[last].day == day { groups[last].items.append(item) } else { groups.append((day, [item])) }
        }
        return groups.sorted { $0.day > $1.day }.map { (dayTitle($0.day, now: now, calendar: calendar), $0.items) }
    }

    /// "9:41 AM".
    public static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    /// "42 min", "1 h 5 min", "35 s".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(max(total, 0)) s" }
        let hours = total / 3600, minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    /// "03:07" or "1:02:45" for players and transcripts.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    // MARK: Numbers

    /// Words per minute of speech, nil without enough audio to say.
    public static func wordsPerMinute(words: Int, seconds: TimeInterval) -> Int? {
        seconds >= 10 ? Int((Double(words) / (seconds / 60)).rounded()) : nil
    }

    /// "1,204" in the user's locale.
    public static func count(_ n: Int) -> String { n.formatted(.number) }

    public static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    // MARK: Keys

    /// Labels for a chord in display order (Fn, Control, Command, Option, Shift, then the rest; §3.2).
    public static func keyLabels(_ chord: KeyChord) -> [String] {
        chord.keys.sorted { (KeyChord.displayRank($0), $0) < (KeyChord.displayRank($1), $1) }.map(KeyChord.label)
    }

    // MARK: Meetings

    public static func platformName(_ platform: MeetingPlatform) -> String {
        switch platform {
        case .zoom: "Zoom"
        case .teams: "Microsoft Teams"
        case .googleMeet: "Google Meet"
        case .slack: "Slack"
        case .webex: "Webex"
        case .discord: "Discord"
        case .whatsapp: "WhatsApp"
        case .facetime: "FaceTime"
        case .other: "Meeting"
        }
    }

    /// When a meeting's audio will be deleted under the retention, or nil when it is kept forever or already gone.
    public static func audioExpiry(of meeting: Meeting, days: Int) -> Date? {
        guard meeting.hasAudio, days > RetentionPolicy.keepForever else { return nil }
        return (meeting.endedAt ?? meeting.startedAt).addingTimeInterval(Double(days) * 86_400)
    }

    // MARK: Models

    /// One line for the automatic downloads (Settings › Models, onboarding footer); never a question.
    public static func autoDownloadText(_ status: AutoDownloadStatus, modelName: (String) -> String) -> String {
        switch status {
        case .idle: "Starting downloads…"
        case .downloading(let id, let progress):
            "Downloading \(modelName(id)) · \(Int((progress.fraction * 100).rounded())) %"
        case .upToDate: "All models are downloaded."
        case .disabled: "Automatic downloads are off."
        case .waitingForNetwork: "Waiting for a Wi‑Fi or wired connection."
        case .waitingForPower: "Paused in Low Power Mode."
        case .waitingForDisk(let free): "Paused: \(bytes(free)) free, needs \(bytes(AutoDownloadPolicy.minimumFreeDisk))."
        case .waitingWhileBusy: "Paused while you dictate or record."
        }
    }

    /// What a model is for, from the catalog kind and the current choices.
    public static func modelPurpose(_ model: ModelDescriptor) -> String {
        switch model.kind {
        case .asr:
            if model.id == Defaults[.asrModelID] { "Dictation" } else if model.id == Defaults[.fallbackASRModelID] { "Other languages" }
            else if model.id == ModelCatalog.whisperBase.id { "Starter dictation" } else { "Speech" }
        case .llm:
            if model.id == Defaults[.cleanupModelID] { "Cleanup" } else if model.id == Defaults[.notesModelID] { "Meeting notes" } else { "Text" }
        case .vad: "Voice detection"
        case .diarization: "Speakers"
        case .coremlEncoder: "Speech encoder"
        case .echoCancel: "Echo removal"
        }
    }

    // MARK: Languages

    public static func languageName(_ code: String) -> String { SupportedLanguages.name(code) }
}
