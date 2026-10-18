import Foundation
import SuperFlowCore

/// Registers this module's service in `Services` (called once at launch).
public enum CleanupKitModule {
    @MainActor public static func install() {
        Services.cleanup = TextCleaner.shared
    }
}

/// The cleanup pipeline (behaviour.md §8, §10; local-models.md §3): rules → optional local LLM → rules, with the
/// guardrails and latency budget deciding whether the model's text is used. Never loses text: every failure falls back
/// to the rules-only result with its skip reason.
@MainActor
public final class TextCleaner: TextCleaning {
    static let shared = TextCleaner()

    private var model: CleanupLanguageModel?
    private var modelID: String
    /// Measured speeds in tokens per second (moving averages), for skipping the LLM when it cannot finish in budget.
    private var prefillRate: Double?
    private var decodeRate: Double?
    /// Wall-time cap for Transforms, Command Mode and MeetingKit's notes chunks (longer outputs than cleanup,
    /// local-models.md §3.4); it stops runaway generation, it is not a target.
    static let transformBudget: TimeInterval = 60

    /// `model` is an already-loaded model (the self-test passes its own); the app loads one with `prepare(modelID:)`.
    public init(model: CleanupLanguageModel? = nil, modelID: String = ModelCatalog.qwen35_2B.id) {
        self.model = model
        self.modelID = modelID
    }

    public var isModelReady: Bool { model != nil }

    public func prepare(modelID: String) async throws {
        guard let url = Services.models.location(of: modelID) else { throw SpeechError.modelNotInstalled(modelID) }
        let engine = LlamaEngine(modelURL: url)
        try await engine.load()
        let previous = model
        model = engine
        self.modelID = modelID
        prefillRate = nil
        decodeRate = nil
        await previous?.unload()
        // Compiles the Metal pipelines and caches the most common prefix (local-models.md §4 "Warm Metal pipelines").
        try? await engine.warm(prefix: Prompts.cleanupPrefix(style: .formal, level: .light, category: .other))
        Log.cleanup.info("Loaded \(modelID, privacy: .public)")
    }

    public func unload() {
        let model = model
        self.model = nil
        Task { await model?.unload() }
    }

    public func warm(style: WritingStyle, level: CleanupLevel, category: AppCategory) async {
        guard let model, level != .none else { return }
        do { try await model.warm(prefix: Prompts.cleanupPrefix(style: style, level: level, category: category)) }
        catch { Log.cleanup.error("Warm-up failed: \(error.localizedDescription, privacy: .public)") }
    }

    public func clean(_ input: CleanupInput, budget: TimeInterval) async -> CleanupOutput {
        let raw = input.transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return skipped(CleanupOutput(text: "", skipReason: .emptyTranscript)) }
        let pass = RulePass(input, pressEnterEnabled: Defaults[.pressEnterCommandEnabled])
        let prepared = pass.prepare(raw)
        let rulesOnly = { (reason: CleanupSkipReason) in
            self.skipped(CleanupOutput(text: pass.finish(prepared.text, prepared, context: input.context), skipReason: reason,
                                       actions: prepared.actions))
        }
        if prepared.text.isEmpty { return rulesOnly(.insufficientInput) }
        if pass.isVerbatim || Defaults[.cleanupModelID] == nil { return rulesOnly(.clientDisabled) }
        // Snippet- or command-only and very short dictations: the rules are enough, and the LLM would only cost time.
        if prepared.wordCount <= 3 { return rulesOnly(.insufficientInput) }
        guard let model else { return rulesOnly(.error) }

        let category = input.context.app?.category ?? .other
        let inputTokens = Prompts.estimatedTokens(prepared.text)
        let turn = Prompts.cleanupTurn(prepared.text, hints: pass.vocabulary.hints, beforeCursor: input.context.textBefore,
                                       thinkBlock: Prompts.usesThinkBlock(modelID: modelID))
        if budget <= 0 || expectedSeconds(prefill: Prompts.estimatedTokens(turn), decode: inputTokens) > budget {
            return rulesOnly(.timeout)
        }
        let request = LLMRequest(prefix: Prompts.cleanupPrefix(style: input.style, level: input.level, category: category), turn: turn,
                                 maxTokens: Int(Double(inputTokens) * 1.5) + 16, deadline: Date().addingTimeInterval(budget))
        let result: LLMResult
        do { result = try await model.complete(request) } catch {
            Log.cleanup.error("Cleanup LLM failed: \(error.localizedDescription, privacy: .public)")
            return rulesOnly(.error)
        }
        measure(result)
        if result.timedOut { return rulesOnly(.timeout) }
        switch Guardrails.checkCleanup(result.text, input: prepared.text, level: input.level, hints: pass.vocabulary.hints) {
        case .failure(let rejection):
            Log.cleanup.info("LLM output rejected: \(rejection.detail, privacy: .private)")
            return rulesOnly(rejection.reason)
        case .success(let text):
            return CleanupOutput(text: pass.finish(text, prepared, context: input.context), actions: prepared.actions)
        }
    }

    public func transform(_ text: String, instruction: String) async throws -> String {
        let selection = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = Self.spokenInstruction(instruction)
        guard !instruction.isEmpty else { throw TransformError.failed }
        guard Dictation.countWords(selection) <= DictationLimits.transformMaxWords else { throw TransformError.tooLong }
        let intent = CommandIntent(instruction)
        if !selection.isEmpty, let result = intent.applyWithoutModel(selection, modelAvailable: model != nil) { return result }
        guard let model else { throw TransformError.modelNotReady }

        let inputTokens = Prompts.estimatedTokens(selection + instruction)
        let request = LLMRequest(prefix: Prompts.transformPrefix(intent, hasText: !selection.isEmpty),
                                 turn: Prompts.transformTurn(selection, instruction: instruction, thinkBlock: Prompts.usesThinkBlock(modelID: modelID)),
                                 maxTokens: Int(Double(inputTokens) * intent.outputFactor) + 64,
                                 deadline: Date().addingTimeInterval(Self.transformBudget))
        let result: LLMResult
        do { result = try await model.complete(request) } catch {
            Log.cleanup.error("Transform failed: \(error.localizedDescription, privacy: .public)")
            throw TransformError.failed
        }
        measure(result)
        if result.timedOut { throw TransformError.timedOut }
        return try Guardrails.checkTransform(result.text, input: selection, intent: intent).get()
    }

    // MARK: Internals

    /// A spoken instruction without fillers and stutters ("um make this uh more formal"). Saved prompts and MeetingKit's
    /// notes instructions are longer and pass verbatim.
    private static func spokenInstruction(_ instruction: String) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Dictation.countWords(trimmed) <= CommandIntent.maxRecognisedWords else { return trimmed }
        var words = Words(trimmed)
        Disfluency.removeFillers(&words)
        Disfluency.collapseRepeats(&words)
        return Casing.tidy(words.text)
    }

    private func skipped(_ output: CleanupOutput) -> CleanupOutput {
        if let reason = output.skipReason { Log.cleanup.info("Rules only: \(reason.rawValue, privacy: .public)") }
        return output
    }

    /// Seconds the model is expected to need; 0 until it has been measured once.
    private func expectedSeconds(prefill: Int, decode: Int) -> TimeInterval {
        guard let prefillRate, let decodeRate, prefillRate > 0, decodeRate > 0 else { return 0 }
        return Double(prefill) / prefillRate + Double(decode) / decodeRate
    }

    private func measure(_ result: LLMResult) {
        func average(_ old: Double?, _ new: Double) -> Double { old.map { 0.7 * $0 + 0.3 * new } ?? new }
        if result.prefilledTokens > 0, result.prefillSeconds > 0 { prefillRate = average(prefillRate, Double(result.prefilledTokens) / result.prefillSeconds) }
        if result.generatedTokens > 0, result.decodeSeconds > 0 { decodeRate = average(decodeRate, Double(result.generatedTokens) / result.decodeSeconds) }
    }
}
