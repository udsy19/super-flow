import AppKit
import Combine
import SuperFlowCore

/// The hub's own places. Richer than `HubPage` (History is its own page here); `HubPage` maps onto it.
public enum HubSection: String, CaseIterable, Sendable {
    case home, history, dictionary, snippets, style, notes, meetings

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .snippets: "Snippets"
        case .style: "Style"
        case .notes: "Notes"
        case .meetings: "Meetings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .snippets: "text.append"
        case .style: "textformat"
        case .notes: "note.text"
        case .meetings: "record.circle"
        }
    }

    /// Where a `HubPage` opens; nil for Settings, which is a modal over the current page.
    public static func section(for page: HubPage) -> HubSection? {
        switch page {
        case .home, .insights: .home
        case .notetaker, .tasks: .meetings
        case .dictionary: .dictionary
        case .snippets: .snippets
        case .style, .transforms: .style
        case .scratchpad: .notes
        case .settings: nil
        }
    }
}

/// Onboarding steps (behaviour.md §14, rebuilt for a local app).
public enum OnboardingStep: String, CaseIterable, Sendable {
    case welcome, privacy, permissions, tryIt

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .privacy: "Privacy"
        case .permissions: "Permissions"
        case .tryIt: "Try it"
        }
    }
}

enum MeetingTab: String, CaseIterable {
    case summary, transcript, notes

    var title: String {
        switch self {
        case .summary: "Summary"
        case .transcript: "Transcript"
        case .notes: "My notes"
        }
    }
}

/// A modal drawn inside the hub window (§3.3 Modal).
enum HubModal: Identifiable {
    case word(DictionaryEntry?)
    case snippet(Snippet?)
    case confirm(Confirmation)

    var id: String {
        switch self {
        case .word(let entry): "word-\(entry?.id.uuidString ?? "new")"
        case .snippet(let snippet): "snippet-\(snippet?.id.uuidString ?? "new")"
        case .confirm(let confirmation): "confirm-\(confirmation.title)"
        }
    }
}

struct Confirmation {
    var title: String
    var message: String
    var confirmTitle = "Yes, delete it"
    var action: () -> Void
}

struct HubToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var isError = false
}

/// Navigation and transient UI of one hub window.
@MainActor
final class HubState: ObservableObject {
    enum Mode: Equatable { case hub, onboarding }

    @Published var mode: Mode = .hub
    @Published var section: HubSection = .home
    /// The meeting open as an L2 page over the Meetings library.
    @Published var meetingID: UUID?
    @Published var meetingTab: MeetingTab = .summary
    @Published var styleTab: StyleTab = .category(.personal)
    /// The Settings modal; nil when closed.
    @Published var settingsPane: SettingsPane?
    @Published var onboardingSteps: [OnboardingStep] = OnboardingStep.allCases
    @Published var onboardingStep: OnboardingStep = .welcome
    @Published var modal: HubModal?
    @Published var toast: HubToast?

    func go(_ section: HubSection) {
        self.section = section
        if section != .meetings { meetingID = nil }
    }

    func open(_ page: HubPage) {
        if let section = HubSection.section(for: page) { go(section) } else { settingsPane = .general }
    }

    func openMeeting(_ id: UUID, tab: MeetingTab = .summary) {
        section = .meetings
        meetingID = id
        meetingTab = tab
    }

    func showToast(_ message: String, isError: Bool = false) {
        let toast = HubToast(message: message, isError: isError)
        self.toast = toast
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.toast?.id == toast.id { self?.toast = nil }
        }
    }

    func confirm(_ title: String, _ message: String, confirmTitle: String = "Yes, delete it", action: @escaping () -> Void) {
        modal = .confirm(Confirmation(title: title, message: message, confirmTitle: confirmTitle, action: action))
    }
}

/// A snapshot of the stores the pages show, refreshed on `HistoryStoring.changes` and model changes.
@MainActor
final class HubStore: ObservableObject {
    @Published private(set) var dictations: [Dictation] = []
    @Published private(set) var dictionary: [DictionaryEntry] = []
    @Published private(set) var snippets: [Snippet] = []
    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var actionItems: [ActionItem] = []
    /// Bumped whenever a model's state changes, so model rows redraw.
    @Published private(set) var modelRevision = 0
    let notes: NotesStore

    /// How many dictations the pages keep in memory; search goes to the store.
    static let recentLimit = 500
    private var cancellables: Set<AnyCancellable> = []

    init(notes: NotesStore? = nil) {
        self.notes = notes ?? NotesStore()
        reload(.reloaded)
        Services.history?.changes.receive(on: DispatchQueue.main).sink { [weak self] in self?.reload($0) }.store(in: &cancellables)
        Services.models?.changes.receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.modelRevision += 1 }.store(in: &cancellables)
    }

    func reload(_ change: StoreChange) {
        guard let history = Services.history else { return }
        switch change {
        case .dictations: dictations = history.dictations(matching: "", limit: Self.recentLimit, offset: 0)
        case .dictionary: dictionary = history.dictionary
        case .snippets: snippets = history.snippets
        case .meetings, .actionItems: reloadMeetings()
        case .reloaded:
            dictations = history.dictations(matching: "", limit: Self.recentLimit, offset: 0)
            dictionary = history.dictionary
            snippets = history.snippets
            reloadMeetings()
        }
    }

    private func reloadMeetings() {
        guard let store = Services.meetings else { return }
        meetings = store.meetings(matching: "", limit: 1000, offset: 0)
        actionItems = store.actionItems
    }

    func meeting(_ id: UUID) -> Meeting? { Services.meetings?.meeting(id) ?? meetings.first { $0.id == id } }
}
