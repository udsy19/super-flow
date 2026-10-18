import Foundation
import llama
import SuperFlowCore

/// A llama.cpp model + context (local-models.md §3). Owns the C handles; all calls run on the actor. The full
/// cleanup prompt, prefix caching and guardrails are CleanupKit's work on top of this.
public actor LlamaEngine {
    public let modelURL: URL
    private var model: OpaquePointer?
    private var context: OpaquePointer?

    public static let backendReady: Void = { llama_backend_init() }()

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

    /// Tokenises `text` with the model's vocabulary (no special tokens).
    public func tokenize(_ text: String) -> [Int32] {
        guard let model, let vocab = llama_model_get_vocab(model) else { return [] }
        let utf8 = Array(text.utf8)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 16)
        let count = utf8.withUnsafeBufferPointer { bytes in
            llama_tokenize(vocab, bytes.baseAddress, Int32(bytes.count), &tokens, Int32(tokens.count), false, true)
        }
        return count >= 0 ? Array(tokens.prefix(Int(count))) : []
    }

    public func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
    }

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }
}
