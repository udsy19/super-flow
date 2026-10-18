import Combine
import Foundation
import SuperFlowCore

/// The dictation state machine (behaviour.md §2.2) that will drive capture → transcribe → cleanup → insert → history.
/// This foundation version keeps the status and the transitions every surface relies on; the pipeline body is the
/// app target's next step once AudioKit and SpeechKit deliver audio and text.
@MainActor
final class DictationCoordinator: DictationControlling {
    private let statusSubject = CurrentValueSubject<DictationStatus, Never>(.idle)
    private(set) var mode: DictationMode?

    var status: DictationStatus { statusSubject.value }
    var statusChanges: AnyPublisher<DictationStatus, Never> { statusSubject.eraseToAnyPublisher() }

    func start(mode: DictationMode, source: DictationSource) {
        guard status.canStart else { return }
        self.mode = mode
        Services.models.setUserBusy(true)
        statusSubject.send(.initializing)
        if let fraction = Services.models.readiness(of: Defaults[.asrModelID]) {
            Services.flowBar.setState(.preparing(fraction: fraction))
        } else {
            Services.flowBar.setState(.listening(mode: mode))
            statusSubject.send(.listening)
        }
    }

    func finish() {
        guard status.isRecording else { return }
        statusSubject.send(.stopping)
        Services.flowBar.setState(.processing)
        statusSubject.send(.processing)
        end()
    }

    func dismiss(_ reason: DismissReason) {
        guard !status.canStart else { return }
        Log.app.info("Dictation dismissed: \(reason.rawValue, privacy: .public)")
        statusSubject.send(.dismissed)
        end()
    }

    private func end() {
        mode = nil
        Services.models.setUserBusy(false)
        Services.flowBar.setState(Defaults[.hideFlowBarPermanently] ? .hidden : .resting)
        if status != .dismissed { statusSubject.send(.idle) }
    }

    func pasteLastTranscript() {
        guard let last = Services.history.lastDictation else { return }
        Task { _ = await Services.insertion.insert(last.displayText, actions: [], method: Defaults[.insertionMethod]) }
    }

    func copyLastTranscript() {
        guard let last = Services.history.lastDictation else { return }
        Services.insertion.copyToClipboard(last.displayText)
    }
}
