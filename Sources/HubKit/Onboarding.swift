import AppKit
import Combine
import SwiftUI
import SuperFlowCore

/// Onboarding in the hub window (behaviour.md §14, rebuilt for a local app): welcome, privacy by design,
/// permissions with live status, then a practice step with the dictation key. The models download in the background
/// from launch; every step shows their progress in the footer.
@MainActor
final class Onboarding: OnboardingPresenting {
    static let shared = Onboarding()

    var isCompleted: Bool { Defaults[.isOnboardingCompleted] }

    func show() {
        Hub.shared.presentOnboarding(from: .welcome, steps: OnboardingStep.allCases)
    }

    /// "Restart tutorial" (§13.2): permissions, then the practice step.
    func restartTutorial() {
        Hub.shared.presentOnboarding(from: .permissions, steps: [.permissions, .tryIt])
    }

    func finish() {
        if !Defaults[.isOnboardingCompleted] {
            Defaults[.isOnboardingCompleted] = true
            LoginItem.apply(Defaults[.openAtLogin])
            Services.flowBar?.setState(Defaults[.hideFlowBarPermanently] ? .hidden : .resting)
        }
        Hub.shared.show(.home)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var state: HubState

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTitleBar()
            Group {
                switch state.onboardingStep {
                case .welcome: WelcomeStep()
                case .privacy: PrivacyStep()
                case .permissions: PermissionsStep()
                case .tryIt: TryItStep()
                }
            }
            .id(state.onboardingStep)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ModelFooter().padding(.bottom, 20)
        }
        .animation(.easeOut(duration: 0.2), value: state.onboardingStep)
        .background(Color(nsColor: SFColor.sand600))
        .ignoresSafeArea()
    }
}

extension HubState {
    func advanceOnboarding() {
        guard let i = onboardingSteps.firstIndex(of: onboardingStep) else { return }
        if i + 1 < onboardingSteps.count { onboardingStep = onboardingSteps[i + 1] } else { Onboarding.shared.finish() }
    }

    func backOnboarding() {
        guard let i = onboardingSteps.firstIndex(of: onboardingStep), i > 0 else { return }
        onboardingStep = onboardingSteps[i - 1]
    }
}

/// The 60 pt title bar (§5.1): Back, the step tracker with a 2 pt progress rule, Skip.
struct OnboardingTitleBar: View {
    @EnvironmentObject private var state: HubState

    var body: some View {
        let steps = state.onboardingSteps
        let index = steps.firstIndex(of: state.onboardingStep) ?? 0
        ZStack {
            HStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(HubColor.tertiary.opacity(0.6)) }
                    Text(step.title).sectionLabelStyle(i == index ? HubColor.foreground : HubColor.tertiary.opacity(i < index ? 1 : 0.7))
                }
            }
            HStack {
                Spacer().frame(width: 72)
                if index > 0 {
                    Button { state.backOnboarding() } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(HubButtonStyle(variant: .ghost, size: .xs))
                }
                Spacer()
                if state.onboardingStep != .welcome && index < steps.count - 1 {
                    Button("Skip") { state.advanceOnboarding() }
                        .buttonStyle(HubButtonStyle(variant: .ghost, size: .xs))
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: SFMetrics.Hub.headerHeight)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(nsColor: SFColor.vast50))
                    Rectangle().fill(HubColor.dawnStrong).frame(width: geo.size.width * CGFloat(index + 1) / CGFloat(max(steps.count, 1)))
                }
            }
            .frame(height: 2)
        }
    }
}

/// Header group (§5.1): 32/40 600 centred, subheading 18/28 up to 520 wide.
struct OnboardingHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.system(size: 32, weight: .semibold)).foregroundStyle(HubColor.foreground).multilineTextAlignment(.center)
            Text(subtitle).hubText(.lg, .regular, HubColor.neutral600).multilineTextAlignment(.center).frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 112)
    }
}

/// Step frame: content padding 40 108, top 32, main column 560, footer button up to 300.
struct OnboardingStepFrame<Main: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var main: Main
    @ViewBuilder var footer: Footer

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 40) {
                    OnboardingHeader(title: title, subtitle: subtitle)
                    main.frame(maxWidth: 560)
                    Spacer(minLength: 0)
                    VStack(spacing: 12) { footer }.frame(maxWidth: 320)
                }
                .padding(.horizontal, 108)
                .padding(.top, 40)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollIndicators(.never)
        }
    }
}

struct OnboardingCard<Content: View>: View {
    var padding: CGFloat = 8
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: SFColor.sand50)))
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }
}

// MARK: - Steps

struct WelcomeStep: View {
    @EnvironmentObject private var state: HubState

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            BrandMark(height: 44)
            VStack(spacing: 20) {
                (Text("Your voice, ").font(Font(HubType.serif(64)))
                 + Text("typed anywhere.").font(Font(HubType.serif(64, italic: true))).foregroundColor(HubColor.dawnStrong))
                    .tracking(-0.04 * 64)
                    .foregroundStyle(HubColor.foreground)
                    .multilineTextAlignment(.center)
                Text("Hold a key, talk, let go. Super Flow types it into any app and takes notes in your meetings. Everything runs on this Mac.")
                    .hubText(.lg, .regular, HubColor.neutral600)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Get started") { state.advanceOnboarding() }
                .buttonStyle(HubButtonStyle(variant: .primary, size: .lg, fullWidth: true))
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: 300)
                .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 108)
    }
}

struct PrivacyStep: View {
    @EnvironmentObject private var state: HubState

    var body: some View {
        OnboardingStepFrame(title: "Everything stays on this Mac",
                            subtitle: "The speech and text models run right here. Nothing you say is uploaded.") {
            VStack(spacing: 16) {
                OnboardingCard(padding: 24) {
                    VStack(alignment: .leading, spacing: 20) {
                        PrivacyFact(symbol: "cpu", title: "Local models",
                                    detail: "Speech recognition, cleanup and meeting summaries run on this Mac.")
                        PrivacyFact(symbol: "person.crop.circle.badge.xmark", title: "No account, no tracking",
                                    detail: "There's nothing to sign in to. No analytics or crash reports are sent.")
                        PrivacyFact(symbol: "arrow.down.circle", title: "Only two things go online",
                                    detail: "Model files from Hugging Face, and update checks with GitHub.")
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield").font(.system(size: 15)).foregroundStyle(HubColor.neutral600).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not notarized by Apple").hubText(.sm, .emphasis)
                        Text("If macOS blocks Super Flow, click Open Anyway in System Settings › Privacy & Security. You only need to do this once.")
                            .hubText(.sm, .regular, HubColor.neutral600).fixedSize(horizontal: false, vertical: true)
                        Button("Open Privacy & Security") { NSWorkspace.shared.open(AppInfo.securitySettings) }
                            .buttonStyle(HubButtonStyle(variant: .outline, size: .xs))
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
        } footer: {
            Button("Continue") { state.advanceOnboarding() }
                .buttonStyle(HubButtonStyle(variant: .primary, size: .lg, fullWidth: true))
                .keyboardShortcut(.defaultAction)
        }
    }
}

struct PermissionsStep: View {
    @EnvironmentObject private var state: HubState
    @ObservedObject var center: PermissionCenter

    init(center: PermissionCenter? = nil) {
        self.center = center ?? PermissionCenter.shared
    }

    var body: some View {
        OnboardingStepFrame(title: "Allow a few permissions",
                            subtitle: "macOS asks for each one. Here's what they're for.") {
            VStack(alignment: .leading, spacing: 20) {
                OnboardingCard {
                    ForEach(PermissionKind.allCases.filter(\.isRequired)) { kind in
                        PermissionRow(kind: kind, center: center)
                    }
                }
                Text("For meetings · optional").sectionLabelStyle().padding(.leading, 8)
                OnboardingCard {
                    ForEach(PermissionKind.allCases.filter { !$0.isRequired }) { kind in
                        PermissionRow(kind: kind, center: center)
                    }
                }
            }
        } footer: {
            Button("Continue") { state.advanceOnboarding() }
                .buttonStyle(HubButtonStyle(variant: .primary, size: .lg, fullWidth: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!center.requiredGranted)
            Text(center.requiredGranted ? "You can change these any time in System Settings."
                                        : "Microphone, Accessibility and Input Monitoring are needed to dictate.")
                .hubText(.xs, .regular, HubColor.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { center.watch() }
        .onDisappear { center.unwatch() }
    }
}

struct PermissionRow: View {
    let kind: PermissionKind
    @ObservedObject var center: PermissionCenter

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(HubColor.foreground)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: SFColor.sand500)))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).hubText(.sm, .strong)
                Text(kind.purpose).hubText(.sm, .regular, HubColor.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            PermissionControl(kind: kind, center: center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Watches the dictation key in the practice step: lit while held or while a dictation records.
@MainActor
final class PracticeKeyWatcher: ObservableObject {
    @Published private(set) var lit = false
    private var monitor: Any?
    private var held: Set<UInt16> = []
    private var cancellable: AnyCancellable?
    private var recording = false

    func start(chord: KeyChord?) {
        stop()
        cancellable = Services.dictation?.statusChanges.receive(on: DispatchQueue.main).sink { [weak self] status in
            self?.recording = status.isRecording
            self?.update(chord)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.held.contains(event.keyCode) { self.held.remove(event.keyCode) } else { self.held.insert(event.keyCode) }
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty { self.held = [] }
                self.update(chord)
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        cancellable = nil
        held = []
    }

    private func update(_ chord: KeyChord?) {
        let pressed = chord.map { !$0.keys.isEmpty && $0.keys.isSubset(of: held) } ?? false
        lit = recording || pressed
    }
}

struct TryItStep: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore
    @Default(.shortcuts) private var shortcuts
    @StateObject private var watcher = PracticeKeyWatcher()
    @State private var text = ""

    var body: some View {
        let chord = shortcuts.chords(for: .pushToTalk).first
        let _ = store.modelRevision
        let summary = ModelSummary.current()
        OnboardingStepFrame(title: "Try it out",
                            subtitle: "Click in the box, hold the key and talk. Let go to insert.") {
            VStack(spacing: 28) {
                HStack(spacing: 10) {
                    if let chord {
                        ForEach(Array(HubFormat.keyLabels(chord).enumerated()), id: \.offset) { i, label in
                            if i > 0 { Text("+").hubText(.lg, .regular, HubColor.tertiary) }
                            KeyPill(label: label == "Fn" ? "fn" : label, large: true, lit: watcher.lit)
                        }
                    }
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Try: “Let's grab lunch at noon tomorrow, my treat.”").hubBody(HubColor.tertiary)
                            .padding(.horizontal, 21).padding(.vertical, 18).allowsHitTesting(false)
                    }
                    TextEditor(text: $text).hubBody().scrollContentBackground(.hidden).padding(16)
                }
                .frame(height: 168)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: SFColor.sand50)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(watcher.lit ? HubColor.dawnStrong : Color.clear, lineWidth: 2))
                if let summary, !summary.speechReady {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The speech model is still downloading").hubText(.sm, .emphasis)
                        Text("You can try it as soon as it's ready: \(summary.detail).").hubText(.xs, .regular, HubColor.tertiary)
                        if let fraction = summary.fraction { ProgressLine(fraction: fraction, tint: HubColor.neutral600).padding(.top, 4) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: SFColor.sand500)))
                }
            }
        } footer: {
            Button("Finish") { Onboarding.shared.finish() }
                .buttonStyle(HubButtonStyle(variant: .primary, size: .lg, fullWidth: true))
            Text("The Flow Bar at the bottom of your screen shows when Super Flow is listening.")
                .hubText(.xs, .regular, HubColor.tertiary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            if let hotkeys = Services.hotkeys, !hotkeys.isRunning { try? hotkeys.start() }
            watcher.start(chord: chord)
        }
        .onDisappear { watcher.stop() }
    }
}

/// The automatic model downloads, inline at the bottom of every step (owner decision: status, never a question).
struct ModelFooter: View {
    @EnvironmentObject private var state: HubState
    @EnvironmentObject private var store: HubStore

    var body: some View {
        let _ = store.modelRevision
        // The practice step shows the speech model's progress itself.
        if let summary = ModelSummary.current(), state.onboardingStep != .tryIt || summary.speechReady {
            HStack(spacing: 10) {
                Image(systemName: summary.isComplete ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(summary.isComplete ? HubColor.success : HubColor.tertiary)
                Text(summary.isComplete ? summary.headline : "\(summary.headline) · \(summary.detail)")
                    .hubText(.xs, .regular, HubColor.tertiary)
                    .monospacedDigit()
                if let fraction = summary.fraction {
                    ProgressLine(fraction: fraction, height: 3, tint: HubColor.neutral600, track: Color(nsColor: SFColor.vast50)).frame(width: 120)
                }
            }
            .frame(height: 20)
        }
    }
}
