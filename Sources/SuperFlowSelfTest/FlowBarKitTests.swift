import AppKit
import FlowBarKit
import SuperFlowCore

// Owned with FlowBarKit: the Flow Bar's state machine, geometry, motion maths, controller and offscreen renders.
func registerFlowBarKitTests() {
    SelfTest.cases.append(("FlowBarKit.stateMachine", { flowBarStateMachine() }))
    SelfTest.cases.append(("FlowBarKit.meetingLayer", { flowBarMeetingLayer() }))
    SelfTest.cases.append(("FlowBarKit.cards", { flowBarCards() }))
    SelfTest.cases.append(("FlowBarKit.layout", { MainActor.assumeIsolated { flowBarLayout() } }))
    SelfTest.cases.append(("FlowBarKit.motion", { flowBarMotion() }))
    SelfTest.cases.append(("FlowBarKit.controller", { MainActor.assumeIsolated { flowBarController() } }))
    SelfTest.cases.append(("FlowBarKit.renders", { MainActor.assumeIsolated { flowBarRenders() } }))
}

private let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000)

private func flowBarStateMachine() {
    var m = FlowBarModel()
    check(m.state == .hidden && m.scene(at: t0).pill == .hidden && !m.scene(at: t0).hasVisibleContent, "starts hidden")

    m.setState(.resting, now: t0)
    check(m.scene(at: t0).pill == .resting, "resting bar")
    m.pointerInside = true
    check(m.scene(at: t0).pill == .ready && m.scene(at: t0).showsPickers, "hover turns the resting bar into the ready pill with pickers")
    m.hovered = .picker(.notes)
    check(m.scene(at: t0).tooltip == [FlowBarCopy.Run("Take notes")], "picker tooltip")
    m.hovered = .cancel
    check(m.scene(at: t0).hovered == nil, "hover on something not showing is ignored")
    m.pointerInside = false

    m.restingVisible = false
    check(m.scene(at: t0).pill == .hidden, "Show Flow Bar at all times off hides the resting bar")
    m.setState(.listening(mode: .pushToTalk), now: t0)
    check(m.scene(at: t0).pill == .pushToTalk, "active states show even when the resting bar is hidden")
    m.restingVisible = true
    m.hiddenUntil = t0.addingTimeInterval(3600)
    m.setState(.resting, now: t0)
    check(m.scene(at: t0.addingTimeInterval(10)).pill == .hidden, "Hide for 1 hour")
    check(m.scene(at: t0.addingTimeInterval(3601)).pill == .resting, "the snooze runs out")
    m.hiddenUntil = .distantPast

    // Hands-free timer keeps counting through a push-to-talk → hands-free upgrade, and clears afterwards.
    m.setState(.listening(mode: .pushToTalk), now: t0)
    m.setState(.listening(mode: .handsFree), now: t0.addingTimeInterval(3))
    check(m.scene(at: t0.addingTimeInterval(42.7)).pill == .handsFree(elapsed: 42), "hands-free elapsed time from the first key-down, whole seconds")
    m.hovered = .finish
    check(m.scene(at: t0).tooltip == [FlowBarCopy.Run("Finish and paste")], "finish tooltip")
    m.setState(.processing, now: t0.addingTimeInterval(50))
    m.setState(.listening(mode: .handsFree), now: t0.addingTimeInterval(60))
    check(m.scene(at: t0.addingTimeInterval(65)).pill == .handsFree(elapsed: 5), "a new dictation starts a new timer")
    m.hovered = nil

    // Command Mode tint lasts through processing only.
    m.setState(.listening(mode: .command), now: t0)
    check(m.commandMode && m.scene(at: t0).pill == .pushToTalk, "command listening uses the push-to-talk pill with the amber overlay")
    m.setState(.processing, now: t0)
    check(m.scene(at: t0).commandMode, "command tint through processing")
    m.setState(.resting, now: t0)
    check(!m.commandMode, "cleared at rest")
    m.setState(.listening(mode: .command), now: t0)
    m.setState(.listening(mode: .pushToTalk), now: t0)
    check(!m.commandMode, "cleared by an ordinary dictation")

    m.setState(.preparing(fraction: 1.7), now: t0)
    check(m.scene(at: t0).pill == .preparing(fraction: 1), "preparing fraction clamps")
    m.setState(.transformProcessing(label: "Drafting"), now: t0)
    m.setState(.transformProcessing(label: "Tightening"), now: t0.addingTimeInterval(2))
    check(m.scene(at: t0).pill == .transformProcessing(label: "Tightening", startedAt: t0), "transform progress keeps its start across labels")
    m.setState(.ready, now: t0)
    check(m.scene(at: t0).pill == .ready, "explicit ready")
    m.setState(.error, now: t0)
    check(m.scene(at: t0).pill == .error && m.state == .error, "error")
}

private func flowBarMeetingLayer() {
    var m = FlowBarModel()
    m.setState(.meeting(.pending), now: t0)
    check(m.meetingStartedAt == nil, "the clock waits for the recording to start")
    m.setState(.meeting(.recording(wordCount: 12)), now: t0.addingTimeInterval(2))
    check(m.scene(at: t0.addingTimeInterval(754.9)).pill == .meeting(.recording(wordCount: 12), elapsed: 752), "meeting elapsed time")
    m.setState(.meeting(.recording(wordCount: 40)), now: t0.addingTimeInterval(10))
    check(m.meetingStartedAt == t0.addingTimeInterval(2), "word-count updates keep the start")

    // Dictation wins over meeting chrome, which comes back when the dictation ends (§10.2).
    m.setState(.listening(mode: .handsFree), now: t0.addingTimeInterval(20))
    check(m.scene(at: t0.addingTimeInterval(21)).pill == .handsFree(elapsed: 1), "dictation state wins")
    m.setState(.processing, now: t0.addingTimeInterval(25))
    m.setState(.resting, now: t0.addingTimeInterval(26))
    check(m.state == .meeting(.recording(wordCount: 40)), "the coordinator's resting brings the meeting back")
    check(m.scene(at: t0.addingTimeInterval(62)).pill == .meeting(.recording(wordCount: 40), elapsed: 60), "same meeting clock")
    m.setState(.meeting(.reconnecting), now: t0.addingTimeInterval(70))
    m.hovered = .meetingBody
    check(m.scene(at: t0).tooltip == [FlowBarCopy.Run("Still recording · Reconnecting…")], "reconnecting tooltip")
    m.setState(.meeting(.recording(wordCount: 1_284)), now: t0.addingTimeInterval(71))
    check(m.scene(at: t0).tooltip?.first?.text.hasSuffix("words") == true && m.meetingStartedAt == t0.addingTimeInterval(2), "word count tooltip")
    m.setState(.meeting(.stopping), now: t0.addingTimeInterval(80))
    m.setState(.resting, now: t0.addingTimeInterval(90))
    check(m.state == .resting && m.meetingPhase == nil && m.meetingStartedAt == nil, "the Notetaker's resting ends the meeting chrome")
    m.setState(.meeting(.recording(wordCount: 0)), now: t0.addingTimeInterval(100))
    m.setState(.hidden, now: t0.addingTimeInterval(101))
    check(m.state == .hidden && m.meetingPhase == nil, "hidden from meeting chrome ends it too")
}

private func flowBarCards() {
    var m = FlowBarModel()
    m.setState(.resting, now: t0)
    let card = FlowBarNotification(id: "paste", title: "Couldn’t paste here.", variant: .condensed, timeout: 10, actions: ["Paste again"])
    m.show(card, now: t0)
    var updated = card
    updated.title = "Still couldn’t paste."
    m.show(updated, now: t0.addingTimeInterval(4))
    check(m.notification == updated && m.notificationShownAt == t0, "updating a card keeps its clock")
    check(m.expiredNotification(at: t0.addingTimeInterval(9)) == nil && m.expiredNotification(at: t0.addingTimeInterval(10)) == "paste", "timeout")
    check(!m.dismissNotification(id: "other") && m.dismissNotification(id: "paste") && m.notification == nil, "dismiss by id")
    m.show(FlowBarNotification(id: "sticky", title: "Error", variant: .error, timeout: nil), now: t0)
    check(m.expiredNotification(at: t0.addingTimeInterval(1e6)) == nil, "no timeout stays")

    m.showPrompt(MeetingPrompt(title: "Design review", platform: .zoom, timeout: 30), now: t0)
    check(!m.promptExpired(at: t0.addingTimeInterval(29)) && m.promptExpired(at: t0.addingTimeInterval(30)), "prompt timeout")
    let elements = FlowBarModel.elements(in: m.scene(at: t0))
    check(elements.isSuperset(of: [.prompt(.record), .prompt(.notNow), .prompt(.neverForApp), .cardClose(id: "sticky")]), "card elements")
    m.clearPrompt()
    check(m.prompt == nil, "prompt cleared")
    m.liveText = ""
    check(m.scene(at: t0).liveText == nil, "empty live text shows nothing")

    check(FlowBarCopy.promptSubtitle(MeetingPrompt(title: "Design review", platform: .zoom)) == "“Design review” on Zoom. Notes stay on this Mac.",
          "prompt subtitle")
    check(FlowBarCopy.promptSubtitle(MeetingPrompt(title: "", platform: .googleMeet)) == "On Google Meet. Notes stay on this Mac.", "untitled")
    check(FlowBarCopy.dontAsk(.other) == "Don’t ask for this app" && FlowBarCopy.dontAsk(.teams) == "Don’t ask for Teams", "don't ask")
    check(FlowBarCopy.percent(0.429) == "42%" && FlowBarCopy.words(1) == "1 word", "labels")
}

@MainActor private func flowBarLayout() {
    let bounds = CGRect(origin: .zero, size: SFMetrics.FlowBar.bottomWindowSize)
    func frames(_ pill: FlowBarScene.Pill, edge: FlowBarEdge = .bottom, _ edit: (inout FlowBarScene) -> Void = { _ in }) -> FlowBarFrames {
        var scene = FlowBarScene()
        scene.pill = pill; scene.edge = edge
        edit(&scene)
        let b = edge == .bottom ? bounds : CGRect(x: 0, y: 0, width: SFMetrics.FlowBar.sideWindowWidth, height: 700)
        return FlowBarLayout.frames(for: scene, in: b)
    }
    check(frames(.resting).pill == CGRect(x: 236, y: 14, width: 40, height: 8), "resting 40 × 8, 14 above the usable area, centred")
    check(frames(.ready).pill == CGRect(x: 231, y: 14, width: 50, height: 30), "ready 50 × 30")
    check(frames(.pushToTalk).pill.size == CGSize(width: 73, height: 30) && frames(.initializing).pill.width == 73, "push-to-talk 73 × 30")
    check(frames(.processing).pill.width == 98 && frames(.error).pill.width == 91, "processing 98, error 91")
    check(frames(.transformProcessing(label: "Polishing", startedAt: t0)).pill.width == 136 && frames(.transformCompleted).pill.width == 152,
          "transform pills 136 and 152")
    let handsFree = frames(.handsFree(elapsed: 42))
    check(handsFree.pill.width > 102.5 + 8 && handsFree.pill.width < 102.5 + 8 + 40, "hands-free 102.5 plus the timer slot")
    if let cancel = handsFree.item(.cancel), let finish = handsFree.item(.finish), let wave = handsFree.item(.waveform) {
        check(cancel.size == CGSize(width: 18, height: 18) && finish.size == cancel.size && wave.size == CGSize(width: 46, height: 18),
              "18 pt buttons and the 46 × 18 waveform box")
        check(abs((cancel.minX - handsFree.pill.minX) - (handsFree.pill.maxX - finish.maxX)) < 0.01, "buttons sit symmetrically")
    } else { check(false, "hands-free items") }
    let error = frames(.error)
    check(error.look.border.hexString == "#EE6A6A" && error.look.borderWidth == 1.5, "error rim 1.5 pt #ee6a6a")
    let meeting = frames(.meeting(.recording(wordCount: 3), elapsed: 754))
    check(meeting.look.borderWidth == 2 && meeting.look.border.hexString == "#10B981" && meeting.item(.stop)?.width == 19, "meeting chrome")
    check(frames(.meeting(.pending, elapsed: 0)).look.border.hexString == "#5B5B59" && frames(.meeting(.pending, elapsed: 0)).item(.timer) == nil,
          "pending meeting: grey rim, no clock yet")
    check(frames(.meeting(.reconnecting, elapsed: 9)).look.border.hexString == "#047857", "reconnecting rim")
    check(frames(.meeting(.stopping, elapsed: 9)).contentOpacity == 0.4 && frames(.meeting(.stopping, elapsed: 9)).item(.flushSpinner) != nil,
          "wrapping up dims the row and spins")
    check(frames(.pushToTalk) { $0.commandMode = true }.look.border.hexString == "#FFA946", "command amber rim")
    check(frames(.ready) { $0.hovered = .pill }.look.fill.hexString == "#30302F", "ready hover fill")

    // Pickers: 8 from the pill, 2 apart, 30 pt circles, and the pill does not move.
    let ready = frames(.ready)
    if let language = ready.pickers[.language], let hub = ready.pickers[.hub], let notes = ready.pickers[.notes], let sounds = ready.pickers[.sounds] {
        check(language.maxX == ready.pill.minX - 8 && hub.maxX == language.minX - 2 && notes.minX == ready.pill.maxX + 8
              && sounds.minX == notes.maxX + 2, "picker spacing")
        check([language, hub, notes, sounds].allSatisfy { $0.size == CGSize(width: 30, height: 30) && $0.midY == ready.pill.midY }, "picker size")
    } else { check(false, "four pickers on hover") }
    check(frames(.resting).pill.midX == ready.pill.midX && frames(.resting).pickers.isEmpty, "pickers only when ready; pill stays centred")

    // Side edges: transposed, 6 in from the edge.
    let left = frames(.pushToTalk, edge: .left)
    check(left.pill == CGRect(x: 6, y: 350 - 36.5, width: 30, height: 73), "left edge pill transposed")
    check(frames(.pushToTalk, edge: .right).pill.maxX == SFMetrics.FlowBar.sideWindowWidth - 6, "right edge inset")
    check(frames(.preparing(fraction: 0.4), edge: .left).pill.height == 30, "text pills stay horizontal on the sides")

    // Hot area: generous around the resting bar, nothing when hidden.
    let restingFrames = frames(.resting)
    check(restingFrames.hotRects.contains { $0.contains(CGPoint(x: 256, y: 40)) } && !restingFrames.hotRects.contains { $0.contains(CGPoint(x: 256, y: 80)) }
          && !restingFrames.hotRects.contains { $0.contains(CGPoint(x: 150, y: 20)) }, "resting hover zone")
    check(frames(.hidden).hotRects.isEmpty, "hidden bar takes no clicks")

    // Cards stack above the bar, clear of an active pill.
    let stacked = frames(.handsFree(elapsed: 3)) { scene in
        scene.liveText = "Hello"
        scene.prompt = MeetingPrompt(title: "Standup", platform: .teams)
        scene.notification = FlowBarNotification(id: "n", title: "Couldn’t paste here.", subtitle: "The text is on your clipboard.",
                                                  variant: .error, timeout: nil, actions: ["Paste again", "Dismiss"])
    }
    if let live = stacked.liveText, let prompt = stacked.prompt, let card = stacked.notification {
        check(live.frame.minY == 14 + 30 + 12 && live.frame.size == CGSize(width: 400, height: 200), "live text 400 × 200, 12 above the pill")
        check(prompt.frame.minY == live.frame.maxY + 8 && card.frame.minY == prompt.frame.maxY + 8, "cards stack 8 apart")
        check(card.frame.width >= 340 && card.frame.width <= 440 && card.frame.height <= 294, "standard card bounds")
        check(card.buttons.last?.title == "Paste again" && card.buttons.last?.style == .softDark, "first action is the primary, on the right")
        check(prompt.buttons.map(\.element) == [.prompt(.neverForApp), .prompt(.notNow), .prompt(.record)], "prompt choices, Record rightmost")
        if let record = prompt.buttons.last {
            check(stacked.element(at: CGPoint(x: record.rect.midX, y: record.rect.midY), in: scene(stacked: true)) == .prompt(.record), "hit-test Record")
        }
    } else { check(false, "stacked cards") }
    if let cancel = handsFree.item(.cancel) {
        var scene = FlowBarScene(); scene.pill = .handsFree(elapsed: 42)
        check(handsFree.element(at: CGPoint(x: cancel.midX, y: cancel.midY), in: scene) == .cancel, "hit-test cancel")
    }

    // Tooltips sit 4 above the hovered element (10 for the hands-free buttons).
    let tip = frames(.ready) { $0.hovered = .pill }
    check(tip.tooltip?.minY == tip.pill.maxY + 4, "tooltip offset")
    let finishTip = frames(.handsFree(elapsed: 1)) { $0.hovered = .finish }
    if let finish = finishTip.item(.finish), let r = finishTip.tooltip { check(r.minY == (finish.maxY + 10).rounded(), "button tooltip offset") }

    // Every size change animates with the 100 ms snap (§2.3); meeting chrome takes 160 ms (§10.2).
    var resting = FlowBarScene(); resting.pill = .resting
    var talking = FlowBarScene(); talking.pill = .pushToTalk
    check(FlowBarSnapshot.pillFrame(from: resting, to: talking, after: 0).width == 40, "starts from the resting size")
    let mid = FlowBarSnapshot.pillFrame(from: resting, to: talking, after: 0.05)
    check(mid.width > 56.5 && mid.width < 73 && mid.midX == 256, "half way in time, most of the way in size, centred")
    check(FlowBarSnapshot.pillFrame(from: resting, to: talking, after: 0.1).size == CGSize(width: 73, height: 30), "settles at 100 ms")
    var recording = FlowBarScene(); recording.pill = .meeting(.recording(wordCount: 1), elapsed: 5)
    let recordingWidth = frames(recording.pill).pill.width
    check(FlowBarSnapshot.pillFrame(from: talking, to: recording, after: 0.1).width != recordingWidth
          && FlowBarSnapshot.pillFrame(from: talking, to: recording, after: 0.16).width == recordingWidth, "meeting morph 160 ms")

    // The window (§2.2).
    let usable = CGRect(x: 0, y: 80, width: 1512, height: 900)
    check(FlowBarLayout.windowFrame(edge: .bottom, visibleFrame: usable) == CGRect(x: 500, y: 80, width: 512, height: 614), "bottom window")
    check(FlowBarLayout.windowFrame(edge: .left, visibleFrame: usable) == CGRect(x: 0, y: 80, width: 490, height: 900), "left window")
    check(FlowBarLayout.windowFrame(edge: .right, visibleFrame: CGRect(x: 0, y: 0, width: 3000, height: 2000)).height == 1144, "side window caps at 1144")
}

private func scene(stacked: Bool) -> FlowBarScene {
    var s = FlowBarScene()
    s.pill = .handsFree(elapsed: 3)
    s.prompt = MeetingPrompt(title: "Standup", platform: .teams)
    return s
}

private func flowBarMotion() {
    let snap = TimingCurve.snap
    check(snap(0) == 0 && abs(snap(1) - 1) < 1e-6 && snap(0.5) > 0.75, "snap curve starts fast")
    check(stride(from: 0.0, through: 1, by: 0.05).map { snap($0) }.adjacentPairsIncrease, "snap is monotonic")
    check(abs(TimingCurve.cubicBezier(0, 0, 1, 1)(0.3) - 0.3) < 1e-4, "linear bezier")
    check(abs(TimingCurve.spring(0.135) - 0.476) < 1e-9 && abs(TimingCurve.spring(0.009) - 0.005) < 1e-9 && TimingCurve.spring(1) == 1,
          "spring stops, including the unpositioned one")

    let keyframes: [(Double, CGFloat)] = [(0, 1), (0.2, 1.2), (0.4, 1.5), (0.8, 1.1), (0.9, 1.3), (1.4, 1.5)]
    check(keyframes.allSatisfy { abs(FlowBarMotion.oscillation(phase: $0.0) - $0.1) < 1e-9 }, "wave keyframes, repeating")
    let silent = FlowBarMotion.dictationBars(audioScale: 5, time: 0.3, speaking: false, reduceMotion: false)
    check(silent.count == 10 && silent.allSatisfy { $0 == 2 }, "silence: ten 2 pt dots")
    let loud = FlowBarMotion.dictationBars(audioScale: 5, time: 0.3, speaking: true, reduceMotion: true)
    check(abs(loud[4] - 2 * 5 * SFMetrics.Waveform.weights[4]) < 1e-9 && abs(loud[0] - 2 * 5 * SFMetrics.Waveform.weights[0]) < 1e-9, "level × weight")
    check(FlowBarMotion.dictationBars(audioScale: 5, time: 0.4, speaking: true, reduceMotion: false).max()! <= 15.0, "15 pt maximum")
    check(FlowBarMotion.meetingBars(audioScale: 2, time: 0, speaking: true, reduceMotion: true) == [3, 7.5, 12, 7.5, 3], "meeting bulge")
    check(FlowBarMotion.meetingBars(audioScale: 5, time: 0, speaking: true, reduceMotion: true)[2] == 18
          && FlowBarMotion.meetingBars(audioScale: 5, time: 0, speaking: false, reduceMotion: false) == [2, 2, 2, 2, 2], "18 pt cap, 2 pt when silent")
    check(abs(FlowBarMotion.spinnerAlpha(spoke: 7, time: 0) - 0.88) < 1e-9 && abs(FlowBarMotion.spinnerAlpha(spoke: 6, time: 0) - 0.78875) < 1e-9,
          "spinner fade walks clockwise")
    check(FlowBarMotion.reconnectPulse(time: 0) == 1 && abs(FlowBarMotion.reconnectPulse(time: 0.7) - 0.6) < 1e-9, "reconnect pulse 1 ↔ .6")
    check(FlowBarMotion.elapsed(7) == "0:07" && FlowBarMotion.elapsed(754) == "12:34" && FlowBarMotion.elapsed(3725) == "1:02:05"
          && FlowBarMotion.elapsed(-3) == "0:00", "elapsed format")

    var level = LevelSmoother()
    level.target = 1
    level.step(dt: 1.0 / 60)
    check(abs(level.value - 1.6 / 60) < 1e-9, "slew limit 1.6 per second")
    for _ in 0..<60 { level.step(dt: 1.0 / 60) }
    check(level.value > 0.9 && level.speaking && level.audioScale(gain: 5) > 4.5, "rises and speaks")
    level.target = 0
    for _ in 0..<120 { level.step(dt: 1.0 / 60) }
    check(level.value == 0 && level.isSettled && !level.speaking && level.audioScale(gain: 5) == 1, "falls to rest and stops ticking")
}

private extension Array where Element == Double {
    var adjacentPairsIncrease: Bool { zip(self, dropFirst()).allSatisfy { $0 <= $1 } }
}

@MainActor private func flowBarController() {
    var clock = t0
    let bar = FlowBar(showsPanel: false)
    bar.now = { clock }
    check(bar.state == .hidden, "starts hidden")

    bar.setState(.meeting(.recording(wordCount: 3)))
    bar.setState(.listening(mode: .handsFree))
    check(bar.state == .listening(mode: .handsFree), "dictation over the meeting")
    bar.setState(.resting)
    check(bar.state == .meeting(.recording(wordCount: 3)), "meeting chrome returns")
    bar.setState(.resting)
    check(bar.state == .resting, "then rests")

    var answers: [MeetingPromptAnswer] = []
    bar.showMeetingPrompt(MeetingPrompt(title: "A", platform: .zoom)) { answers.append($0) }
    bar.showMeetingPrompt(MeetingPrompt(title: "B", platform: .teams)) { answers.append($0) }
    check(answers == [.dismissed] && bar.model.prompt?.title == "B", "a new prompt replaces the old one, which is dismissed")
    bar.answerPrompt(.record)
    bar.answerPrompt(.notNow)
    check(answers == [.dismissed, .record] && bar.model.prompt == nil, "Record answers once")
    bar.showMeetingPrompt(MeetingPrompt(title: "C", platform: .slack, timeout: 30)) { answers.append($0) }
    clock = t0.addingTimeInterval(29)
    bar.expireTimedOut()
    check(answers.count == 2, "not yet")
    clock = t0.addingTimeInterval(31)
    bar.expireTimedOut()
    check(answers.last == .dismissed && bar.model.prompt == nil, "timeout dismisses")
    bar.showMeetingPrompt(MeetingPrompt(title: "D", platform: .zoom)) { answers.append($0) }
    bar.answerPrompt(.neverForApp)
    check(answers.last == .notThisOne, "Don't ask for this app declines this meeting")

    var actions: [String] = []
    bar.show(FlowBarNotification(id: "x", title: "Hidden", timeout: 5, actions: ["Undo", "Open"])) { actions.append($0) }
    bar.performNotificationAction(id: "x", index: 1)
    check(actions == ["Open"] && bar.model.notification == nil, "card action runs and closes the card")
    bar.show(FlowBarNotification(id: "y", title: "Tip", timeout: 5)) { actions.append($0) }
    clock = clock.addingTimeInterval(6)
    bar.expireTimedOut()
    check(bar.model.notification == nil && actions == ["Open"], "timeout closes without an action")
    bar.dismiss(notificationID: "missing")
    bar.showLiveText("Hello there")
    check(bar.model.liveText == "Hello there", "live text")
    bar.showLiveText(nil)
    bar.setEdge(.left)
    check(bar.model.edge == .left, "edge")
    bar.pointer(inside: true, over: .pill)
    check(bar.model.scene(at: clock).pill == .ready, "hover readies the bar")

    Defaults[.autoDetectLanguage] = true
    check(FlowBar(showsPanel: false).model.languageCode == nil, "auto-detect shows the globe")
    Defaults.reset(.autoDetectLanguage)
    check(FlowBar(showsPanel: false).model.languageCode == Defaults[.selectedLanguages].first, "language code")
}

@MainActor private func flowBarRenders() {
    func rgb(_ rep: NSBitmapImageRep, _ p: CGPoint) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let x = Int(p.x * 2), y = Int((rep.size.height - p.y) * 2)
        let c = rep.colorAt(x: min(max(x, 0), rep.pixelsWide - 1), y: min(max(y, 0), rep.pixelsHigh - 1))?.usingColorSpace(.deviceRGB) ?? .magenta
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }
    func luma(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

    let catalogue = FlowBarSnapshot.catalogue()
    check(catalogue.count >= 30, "a render for every state")
    for item in catalogue {
        let pill = FlowBarSnapshot.pillRect(item.scene)
        for backdrop in FlowBarSnapshot.Backdrop.allCases {
            let rep = FlowBarSnapshot.render(item.scene, level: item.level, time: item.time, backdrop: backdrop)
            let name = "\(item.name)/\(backdrop.rawValue)"
            check(rep.pixelsWide == Int(rep.size.width * 2) && rep.size.width >= 60 && rep.size.height >= 40, "\(name): 2× render")
            let ground = luma(rgb(rep, CGPoint(x: 2, y: rep.size.height - 2)))
            check(backdrop == .light ? ground > 0.8 : ground < 0.2, "\(name): backdrop")
            switch item.scene.pill {
            case .hidden: break
            case .resting:
                check(luma(rgb(rep, CGPoint(x: pill.midX, y: pill.midY))) < ground - 0.04, "\(name): the resting capsule shows on the backdrop")
            default:
                let inside = luma(rgb(rep, CGPoint(x: pill.midX, y: pill.minY + 3.5)))
                check(inside < 0.22, "\(name): the pill is black on every appearance (\(inside))")
            }
            let rim = rgb(rep, CGPoint(x: pill.minX + 0.75, y: pill.midY))
            switch item.scene.pill {
            case .error: check(rim.r > 0.7 && rim.g < 0.55, "\(name): red rim")
            case .meeting(.recording, _) where item.scene.hovered == nil: check(rim.g > rim.r + 0.2 && rim.g > rim.b, "\(name): green rim")
            case .pushToTalk where item.scene.commandMode: check(rim.r > 0.8 && rim.b < 0.45, "\(name): amber rim")
            default: break
            }
        }
    }
    if let dir = ProcessInfo.processInfo.environment["SUPERFLOW_RENDER_DIR"] {
        let files = (try? FlowBarSnapshot.writeCatalogue(to: URL(fileURLWithPath: dir))) ?? []
        check(files.count == catalogue.count * 2, "renders written to \(dir)")
    }
}
