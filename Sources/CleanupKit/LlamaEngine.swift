import Foundation
import llama
import SuperFlowCore

/// A llama.cpp model + context (local-models.md §3). Owns the C handles; all calls run on the actor.
///
/// Prefix reuse works for every architecture the catalog ships: after a prefix is prefilled, the state of sequence 0
/// is snapshotted (`llama_state_seq_get_data`); a later request with the same prefix drops the sequence and restores
/// the snapshot instead of prefilling again. Hybrid models (Qwen3.5's Gated DeltaNet layers) cannot trim their
/// recurrent state back to the prefix, so trimming the KV cache alone would leak earlier turns (local-models.md §3.2).
public actor LlamaEngine: CleanupLanguageModel {
    public let modelURL: URL
    private var model: OpaquePointer?
    private var context: OpaquePointer?

    private struct Snapshot { var prefix: String; var tokens: Int; var state: [UInt8] }
    /// Most recently used last; one per (style, level, app category) in use, so switching apps stays cheap.
    private var snapshots: [Snapshot] = []
    private static let maxSnapshots = 4
    /// The prefix the context holds right now with nothing after it, so the next request needs no restore.
    private var heldPrefix: String?

    /// Initialises the backend once and routes llama.cpp's own log to the cleanup log (errors only).
    public static let backendReady: Void = {
        llama_log_set({ level, text, _ in
            guard level == GGML_LOG_LEVEL_ERROR, let text else { return }
            Log.cleanup.error("llama: \(String(cString: text), privacy: .public)")
        }, nil)
        llama_backend_init()
    }()

    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    /// Whether this process can offload layers to Metal.
    public static var supportsGPUOffload: Bool { llama_supports_gpu_offload() }

    /// Loads the GGUF with every layer on the GPU and creates a context of `contextSize` tokens.
    public func load(contextSize: UInt32 = 4096) throws {
        _ = LlamaEngine.backendReady
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 999
        guard let model = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw SpeechError.failed("Couldn't load \(modelURL.lastPathComponent)")
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = contextSize
        contextParams.n_batch = min(contextSize, 512)
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw SpeechError.failed("Couldn't create a context for \(modelURL.lastPathComponent)")
        }
        self.model = model
        self.context = context
    }

    public var isLoaded: Bool { context != nil }
    public var contextSize: Int { context.map { Int(llama_n_ctx($0)) } ?? 0 }
    public var vocabularySize: Int {
        guard let model, let vocab = llama_model_get_vocab(model) else { return 0 }
        return Int(llama_vocab_n_tokens(vocab))
    }

    /// Tokenises `text` with the model's vocabulary; special tokens written in the text (`<|im_start|>`) are parsed.
    public func tokenize(_ text: String) -> [Int32] {
        guard let model, let vocab = llama_model_get_vocab(model) else { return [] }
        let utf8 = Array(text.utf8)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 16)
        let count = utf8.withUnsafeBufferPointer { bytes in
            llama_tokenize(vocab, bytes.baseAddress, Int32(bytes.count), &tokens, Int32(tokens.count), false, true)
        }
        return count >= 0 ? Array(tokens.prefix(Int(count))) : []
    }

    // MARK: CleanupLanguageModel

    public func warm(prefix: String) throws {
        _ = try restore(prefix)
    }

    public func complete(_ request: LLMRequest) throws -> LLMResult {
        guard let context, let model, let vocab = llama_model_get_vocab(model) else {
            throw SpeechError.engineUnavailable("The cleanup model isn't loaded.")
        }
        let started = Date()
        let prefixPrefill = try restore(request.prefix)
        let turn = tokenize(request.turn)
        heldPrefix = nil
        let room = Int(llama_n_ctx(context)) - prefixPrefill.total - turn.count - 1
        guard room > 0 else { throw SpeechError.failed("The text is too long for the model's context.") }
        try decode(turn)
        let prefilled = Date()

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        defer { llama_sampler_free(sampler) }
        var bytes: [UInt8] = []
        var generated = 0
        var timedOut = false
        while generated < min(request.maxTokens, room) {
            if Date() >= request.deadline { timedOut = true; break }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += piece(token, vocab: vocab)
            generated += 1
            if LlamaEngine.reachedStop(bytes) { break }
            let status = withUnsafeMutablePointer(to: &token) { llama_decode(context, llama_batch_get_one($0, 1)) }
            guard status == 0 else { throw SpeechError.failed("llama_decode failed (\(status))") }
        }
        let finished = Date()
        return LLMResult(text: String(decoding: bytes, as: UTF8.self), prefilledTokens: prefixPrefill.prefilled + turn.count,
                         generatedTokens: generated, prefillSeconds: prefilled.timeIntervalSince(started),
                         decodeSeconds: finished.timeIntervalSince(prefilled), timedOut: timedOut)
    }

    public func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        snapshots = []
        heldPrefix = nil
    }

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    // MARK: Internals

    /// Puts sequence 0 at the end of `prefix`: as is, from a snapshot, or by prefilling (then snapshotting) it.
    /// Returns the prefix length and how many tokens had to be prefilled.
    private func restore(_ prefix: String) throws -> (total: Int, prefilled: Int) {
        guard let context, let memory = llama_get_memory(context) else { throw SpeechError.engineUnavailable("The cleanup model isn't loaded.") }
        if let index = snapshots.firstIndex(where: { $0.prefix == prefix }) {
            let snapshot = snapshots.remove(at: index)
            snapshots.append(snapshot)
            if heldPrefix == prefix { return (snapshot.tokens, 0) }
            _ = llama_memory_seq_rm(memory, 0, -1, -1)
            let restored = snapshot.state.withUnsafeBufferPointer { llama_state_seq_set_data(context, $0.baseAddress, $0.count, 0) }
            if restored > 0 { heldPrefix = prefix; return (snapshot.tokens, 0) }
            snapshots.removeLast()
        }
        llama_memory_clear(memory, true)
        heldPrefix = nil
        var tokens = tokenize(prefix)
        if let model, let vocab = llama_model_get_vocab(model), llama_vocab_get_add_bos(vocab) { tokens.insert(llama_vocab_bos(vocab), at: 0) }
        try decode(tokens)
        let size = llama_state_seq_get_size(context, 0)
        var state = [UInt8](repeating: 0, count: size)
        let written = state.withUnsafeMutableBufferPointer { llama_state_seq_get_data(context, $0.baseAddress, size, 0) }
        if written > 0 {
            snapshots.append(Snapshot(prefix: prefix, tokens: tokens.count, state: Array(state.prefix(written))))
            if snapshots.count > LlamaEngine.maxSnapshots { snapshots.removeFirst() }
        }
        heldPrefix = prefix
        return (tokens.count, tokens.count)
    }

    /// Prefills tokens in batch-sized chunks; positions continue from the sequence's end.
    private func decode(_ tokens: [llama_token]) throws {
        guard let context else { return }
        let batch = Int(llama_n_batch(context))
        var start = 0
        while start < tokens.count {
            var chunk = Array(tokens[start..<min(start + batch, tokens.count)])
            let status = chunk.withUnsafeMutableBufferPointer { llama_decode(context, llama_batch_get_one($0.baseAddress, Int32($0.count))) }
            guard status == 0 else { throw SpeechError.failed("llama_decode failed (\(status))") }
            start += batch
        }
    }

    private func piece(_ token: llama_token, vocab: OpaquePointer) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(length, 0))).map { UInt8(bitPattern: $0) }
    }

    /// The model started another turn or echoed the prompt's tags: stop early (the guardrails reject the output).
    private static let stops = ["<|im_start|>", "<|im_end|>", "<|endoftext|>", "</transcript>", "<transcript>", "<dictionary>"]
    private static func reachedStop(_ bytes: [UInt8]) -> Bool {
        let tail = String(decoding: bytes.suffix(24), as: UTF8.self)
        return stops.contains { tail.contains($0) }
    }
}
