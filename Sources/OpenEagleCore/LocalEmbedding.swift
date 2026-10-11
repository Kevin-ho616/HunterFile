import Foundation
import CLiteRTLM

public enum EmbeddingInput: Sendable {
    case text(String), image(Data)
}

public actor LocalEmbedding {
    public static let dimension = 768
    public static let modelSHA256 = "92dcbea108899e5d6e30d919b0744f90d9967e80c67a4ab5503ac16d54f62eb0"
    public static let modelRevision = "e301f74d5551b0c2641bd5cb4652a76239d5c5f8"
    public static let modelURL = URL(string: "https://huggingface.co/litert-community/embeddinggemma-2-text-vision-440m-litert-lm/resolve/\(modelRevision)/embeddinggemma-2-text-vision-440m.litertlm")!
    public static let indexVersion = "eg2-440m-\(modelSHA256)-768-content-v1"
    private var handle: OpaquePointer?

    public init(modelURL: URL, useGPU: Bool = false) throws {
        try Task.checkCancellation()
        guard try LibraryRepository.sha256(modelURL) == Self.modelSHA256 else {
            throw LibraryError.message("模型校验失败，请选择官方 EmbeddingGemma 2 文字与视觉 440M 的 .litertlm 文件。")
        }
        guard let settings = litert_lm_embedding_engine_settings_create(modelURL.path, useGPU ? "gpu" : "cpu", "cpu", nil) else { throw Self.runtimeError() }
        defer { litert_lm_embedding_engine_settings_delete(settings) }
        litert_lm_embedding_engine_settings_set_num_threads(settings, 4)
        litert_lm_embedding_engine_settings_set_max_input_length(settings, 2048)
        litert_lm_embedding_engine_settings_set_cache_dir(settings, NSTemporaryDirectory())
        guard let engine = litert_lm_embedding_engine_create(settings) else { throw Self.runtimeError() }
        handle = engine
    }
    deinit { if let handle { litert_lm_embedding_engine_delete(handle) } }

    public func embed(_ input: EmbeddingInput) throws -> [Float] {
        try Task.checkCancellation()
        guard let handle else { throw LibraryError.message("本地模型未加载。") }
        let pointer: OpaquePointer?
        switch input {
        case .text(let text):
            pointer = text.withCString { litert_lm_input_data_create(kLiteRtLmInputDataTypeText, $0, text.utf8.count) }
        case .image(let data):
            pointer = data.withUnsafeBytes { litert_lm_input_data_create(kLiteRtLmInputDataTypeImage, $0.baseAddress, data.count) }
        }
        guard let pointer else { throw Self.runtimeError() }
        defer { litert_lm_input_data_delete(pointer) }
        guard let options = litert_lm_embedding_options_create() else { throw Self.runtimeError() }
        defer { litert_lm_embedding_options_delete(options) }
        litert_lm_embedding_options_set_normalize(options, true)
        litert_lm_embedding_options_set_output_size(options, Int32(Self.dimension))
        var inputs: [OpaquePointer?] = [pointer]
        let response = inputs.withUnsafeMutableBufferPointer { litert_lm_embedding_engine_compute_embedding(handle, $0.baseAddress, $0.count, options) }
        guard let response else { throw Self.runtimeError() }
        defer { litert_lm_embedding_response_delete(response) }
        guard litert_lm_embedding_response_get_size(response) == Self.dimension,
              let values = litert_lm_embedding_response_get_values(response) else { throw LibraryError.message("模型返回了无效的向量维度。") }
        let vector = Array(UnsafeBufferPointer(start: values, count: Self.dimension))
        try Self.validate(vector)
        try Task.checkCancellation()
        return vector
    }
    public func query(_ text: String) throws -> [Float] { try embed(.text("task: search result | query: \(text)")) }
    public static func validate(_ vector: [Float]) throws {
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }
        guard vector.count == dimension, vector.allSatisfy(\.isFinite), abs(norm - 1) < 0.01 else {
            throw LibraryError.message("向量必须是 768 维、有限且归一化的数据。")
        }
    }
    private static func runtimeError() -> LibraryError {
        .message("本地模型：" + (litert_lm_get_last_error_message().map { String(cString: $0) } ?? "推理失败"))
    }
}
