import AppKit
import AVFoundation
import ImageIO
import PDFKit

public struct GeneratedMetadata: Codable, Sendable {
    public static let schema = #"{"type":"object","properties":{"name":{"type":"string"},"summary":{"type":"string"}},"required":["name","summary"],"additionalProperties":false}"#
    public var name: String
    public var summary: String
    public static func parse(_ text: String) throws -> Self {
        var result: Self = try GenerationContent.decode(text)
        guard !result.name.trimmed.isEmpty, result.name.count <= 180, !result.summary.trimmed.isEmpty, result.summary.count <= 3000 else { throw LibraryError.message("生成的名称或摘要无效，素材未修改。") }
        result.name = result.name.safeFilename; result.summary = result.summary.trimmed
        return result
    }
}

public struct GroundedAnswer: Codable, Sendable {
    public static let schema = #"{"type":"object","properties":{"answer":{"type":"string"},"sources":{"type":"array","items":{"type":"integer"}}},"required":["answer","sources"],"additionalProperties":false}"#
    public var answer: String
    public var sources: [Int]
    public static func parse(_ text: String, sourceCount: Int) throws -> Self {
        var result: Self = try GenerationContent.decode(text)
        guard !result.answer.trimmed.isEmpty, result.answer.count <= 6000,
              result.sources.allSatisfy({ (1...max(1, sourceCount)).contains($0) && sourceCount > 0 }) else { throw LibraryError.message("回答引用了无效来源，请重新提问。") }
        let expression = try NSRegularExpression(pattern: "\\[(?:S)?([0-9]+)\\]")
        let references = expression.matches(in: result.answer, range: NSRange(result.answer.startIndex..., in: result.answer))
        for reference in references {
            guard let range = Range(reference.range(at: 1), in: result.answer), let number = Int(result.answer[range]), result.sources.contains(number) else { throw LibraryError.message("回答中的来源编号无效，请重新提问。") }
        }
        result.sources = Array(Set(result.sources)).sorted()
        if result.sources.isEmpty { result.answer = "当前检索到的素材不足以回答这个问题。请缩小范围或补充相关素材。" }
        return result
    }
}

public enum GenerationContent {
    static func decode<T: Decodable>(_ text: String) throws -> T {
        var json = text.trimmed
        if json.hasPrefix("```"), json.hasSuffix("```") { json = json.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n") }
        guard json.utf8.count <= 64_000 else { throw LibraryError.message("生成结果过长，请重试。") }
        do { return try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
        catch { throw LibraryError.message("本地模型未返回有效 JSON，请重新生成。素材未修改。") }
    }
    public static func image(at url: URL, kind: AssetKind, page: Int? = nil, seconds: Double? = nil, thumbnail: URL? = nil) async throws -> Data? {
        try Task.checkCancellation()
        let image: CGImage?
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), !document.isLocked, let page = document.page(at: (page ?? 1) - 1) else { throw LibraryError.message("无法读取引用的 PDF 页面。") }
            image = page.thumbnail(of: CGSize(width: 640, height: 640), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else if kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 640, height: 640)
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            image = try await generator.image(at: CMTime(seconds: seconds ?? 0, preferredTimescale: 600)).image
        } else if kind == .image {
            let source = CGImageSourceCreateWithURL(url as CFURL, nil) ?? thumbnail.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            image = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) }
            guard image != nil else { throw LibraryError.message("无法解码用于生成的图片。") }
        } else { image = nil }
        try Task.checkCancellation()
        return try image.map(LocalEmbedding.png)
    }
}
