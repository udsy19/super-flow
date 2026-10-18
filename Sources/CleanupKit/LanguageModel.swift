import Foundation

/// The local LLM cleanup, Transforms and Command Mode run on: `LlamaEngine` in the app, a scripted model in the
/// self-test. Prompts arrive fully templated (ChatML); the model only prefills, decodes and stops.
public protocol CleanupLanguageModel: AnyObject, Sendable {
    /// Prefills `prefix` (the system part of a prompt) and keeps its state, so later requests that start with the same
    /// prefix only prefill their own turn (local-models.md §3.4 "Prefix reuse").
    func warm(prefix: String) async throws
    /// Greedy completion of `prefix + turn`, ending at the end-of-turn token, `maxTokens`, or `deadline`.
    func complete(_ request: LLMRequest) async throws -> LLMResult
    func unload() async
}

public struct LLMRequest: Sendable, Equatable {
    /// The cached part: system prompt and few-shot turns.
    public var prefix: String
    /// The user turn and the opening of the assistant turn.
    public var turn: String
    public var maxTokens: Int
    public var deadline: Date

    public init(prefix: String, turn: String, maxTokens: Int, deadline: Date) {
        self.prefix = prefix; self.turn = turn; self.maxTokens = maxTokens; self.deadline = deadline
    }
}

public struct LLMResult: Sendable, Equatable {
    public var text: String
    /// Tokens prefilled for this request (the turn, plus the prefix when it was not cached).
    public var prefilledTokens: Int
    public var generatedTokens: Int
    public var prefillSeconds: Double
    public var decodeSeconds: Double
    /// The deadline passed before the end of the turn; `text` is incomplete.
    public var timedOut: Bool

    public init(text: String, prefilledTokens: Int = 0, generatedTokens: Int = 0, prefillSeconds: Double = 0, decodeSeconds: Double = 0,
                timedOut: Bool = false) {
        self.text = text; self.prefilledTokens = prefilledTokens; self.generatedTokens = generatedTokens
        self.prefillSeconds = prefillSeconds; self.decodeSeconds = decodeSeconds; self.timedOut = timedOut
    }
}
