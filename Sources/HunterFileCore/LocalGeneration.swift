import Foundation
import CLiteRTLM

public actor LocalGeneration {
    public static let modelSHA256 = "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c"
    public static let modelRevision = "b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1"
    public static let modelURL = URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/\(modelRevision)/gemma-4-E2B-it.litertlm")!
    private let handle: OpaquePointer
    private var busy = false

    public init(modelURL: URL, useGPU: Bool = false) throws {
        try Task.checkCancellation()
        guard try LibraryRepository.sha256(modelURL) == Self.modelSHA256 else { throw LibraryError.message("请选择官方 Gemma 4 E2B 的 gemma-4-E2B-it.litertlm 文件，模型校验失败。") }
        guard let settings = litert_lm_engine_settings_create(modelURL.path, useGPU ? "gpu" : "cpu", "cpu", nil) else { throw Self.runtimeError() }
        defer { litert_lm_engine_settings_delete(settings) }
        litert_lm_engine_settings_set_num_threads(settings, 4)
        litert_lm_engine_settings_set_max_num_tokens(settings, 8192)
        litert_lm_engine_settings_set_max_vision_tokens_per_image(settings, 280)
        litert_lm_engine_settings_set_cache_dir(settings, NSTemporaryDirectory())
        guard let engine = litert_lm_engine_create(settings) else { throw Self.runtimeError() }
        handle = engine
    }
    deinit { litert_lm_engine_delete(handle) }

    public func generate(system: String, prompt: String, images: [Data] = [], maxOutputTokens: Int = 512, jsonSchema: String? = nil) async throws -> String {
        try Task.checkCancellation()
        guard !busy else { throw LibraryError.message("本地生成模型正在处理另一项任务，请稍后再试。") }
        guard prompt.count <= 12_000, images.count <= 3, images.allSatisfy({ !$0.isEmpty && $0.count < 8 * 1024 * 1024 }), (1...1024).contains(maxOutputTokens) else { throw LibraryError.message("生成内容超过单次处理范围。") }
        busy = true; defer { busy = false }
        guard let config = litert_lm_conversation_config_create(), let session = litert_lm_session_config_create(), let thinking = litert_lm_thinking_config_create() else { throw Self.runtimeError() }
        defer { litert_lm_conversation_config_delete(config); litert_lm_session_config_delete(session); litert_lm_thinking_config_delete(thinking) }
        litert_lm_session_config_set_max_output_tokens(session, Int32(maxOutputTokens))
        if let sampler = litert_lm_sampler_params_create(kLiteRtLmSamplerTypeTopP) {
            litert_lm_sampler_params_set_top_k(sampler, 1)
            litert_lm_sampler_params_set_top_p(sampler, 1)
            litert_lm_sampler_params_set_temperature(sampler, 1)
            litert_lm_session_config_set_sampler_params(session, sampler); litert_lm_sampler_params_delete(sampler)
        }
        litert_lm_conversation_config_set_session_config(config, session)
        litert_lm_thinking_config_set_enable_thinking(thinking, false)
        litert_lm_conversation_config_set_thinking_config(config, thinking)
        // The C API expects a content array here, unlike the user-message object.
        let systemJSON = String(decoding: try JSONSerialization.data(withJSONObject: [["type": "text", "text": system]]), as: UTF8.self)
        litert_lm_conversation_config_set_system_message(config, systemJSON)
        guard let options = litert_lm_conversation_optional_args_create() else { throw Self.runtimeError() }
        defer { litert_lm_conversation_optional_args_delete(options) }
        litert_lm_conversation_optional_args_set_max_output_tokens(options, Int32(maxOutputTokens))
        if let jsonSchema {
            var provider = kLiteRtLmConstraintProviderTypeLlGuidance
            litert_lm_conversation_config_set_constraint_provider(config, &provider)
            litert_lm_conversation_config_set_enable_constrained_decoding(config, true)
            litert_lm_conversation_optional_args_set_constraint(options, kLiteRtLmConstraintTypeJsonSchema, jsonSchema)
        }
        guard let conversation = litert_lm_conversation_create(handle, config) else { throw Self.runtimeError() }
        let stream = GenerationStream(conversation: conversation)
        defer { stream.close() }
        var content = [["type": "text", "text": prompt]]
        content += images.map { ["type": "image", "blob": $0.base64EncodedString()] }
        let message = String(decoding: try JSONSerialization.data(withJSONObject: ["role": "user", "content": content]), as: UTF8.self)
        let text = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { stream.start(message, options: options, continuation: $0) }
        } onCancel: { stream.cancel() }
        try Task.checkCancellation()
        guard !text.trimmed.isEmpty else { throw LibraryError.message("本地模型没有返回内容。") }
        return text.trimmed
    }
    private static func runtimeError() -> LibraryError { .message("本地生成模型：" + (litert_lm_get_last_error_message().map { String(cString: $0) } ?? "推理失败")) }
}

// Cancellation can arrive off the actor; the lock protects the native handle until decoding finishes.
private final class GenerationStream: @unchecked Sendable {
    private let lock = NSLock()
    private var conversation: OpaquePointer?
    private var cancelled = false
    private var continuation: CheckedContinuation<String, Error>?
    private var text = ""
    private var error: Error?
    init(conversation: OpaquePointer) { self.conversation = conversation }
    func start(_ message: String, options: OpaquePointer, continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        guard !cancelled, let conversation else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        lock.unlock()
        let context = Unmanaged.passRetained(self).toOpaque()
        let status = litert_lm_conversation_send_message_stream(conversation, message, nil, options, generationCallback, context)
        if status != 0 {
            Unmanaged<GenerationStream>.fromOpaque(context).release()
            continuation.resume(throwing: LibraryError.message("无法启动本地生成：" + (litert_lm_get_last_error_message().map { String(cString: $0) } ?? String(status))))
        } else {
            lock.lock(); if cancelled { litert_lm_conversation_cancel_process(conversation) }; lock.unlock()
        }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let conversation { litert_lm_conversation_cancel_process(conversation) }
    }
    func close() {
        lock.lock(); let value = conversation; conversation = nil; lock.unlock()
        if let value { litert_lm_conversation_delete(value) }
    }
    func receive(_ chunk: OpaquePointer?) -> Bool {
        if let value = litert_lm_stream_chunk_get_text(chunk) {
            do {
                guard let message = try JSONSerialization.jsonObject(with: Data(String(cString: value).utf8)) as? [String: Any] else { throw LibraryError.message("生成结果格式无效。") }
                for part in message["content"] as? [[String: Any]] ?? [] where part["type"] as? String == "text" { text += part["text"] as? String ?? "" }
            } catch { self.error = error }
        }
        let nativeError = litert_lm_stream_chunk_get_error(chunk)
        guard litert_lm_stream_chunk_is_final(chunk) || nativeError != nil else { return false }
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { continuation?.resume(throwing: CancellationError()) }
        else if let error { continuation?.resume(throwing: error) }
        else if let nativeError { continuation?.resume(throwing: LibraryError.message(String(cString: nativeError))) }
        else { continuation?.resume(returning: text) }
        continuation = nil
        return true
    }
}

private func generationCallback(_ context: UnsafeMutableRawPointer?, _ chunk: OpaquePointer?) {
    guard let context else { return }
    let stream = Unmanaged<GenerationStream>.fromOpaque(context)
    if stream.takeUnretainedValue().receive(chunk) { stream.release() }
}
