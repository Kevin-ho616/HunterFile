import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

public struct SemanticChunk: Codable, Sendable {
    public var vector: [Float]
    public var text: String
    public var page: Int?
    public var seconds: Double?
    public init(vector: [Float], text: String = "", page: Int? = nil, seconds: Double? = nil) {
        self.vector = vector; self.text = text; self.page = page; self.seconds = seconds
    }
}

extension LocalEmbedding {
    public func chunks(at url: URL, kind: AssetKind, title: String, metadata: String = "", thumbnail: URL? = nil) async throws -> [SemanticChunk] {
        var result: [SemanticChunk] = []
        func addText(_ text: String, page: Int? = nil) async throws {
            for segment in Self.textSegments(text) {
                result.append(SemanticChunk(vector: try embed(.text("title: \(title) | text: \(segment)")), text: String(segment.prefix(300)), page: page))
                await Task.yield()
            }
        }
        try await addText(metadata)
        if kind == .image {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) ?? thumbnail.flatMap({ CGImageSourceCreateWithURL($0 as CFURL, nil) }),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw LibraryError.message("无法解码图片。") }
            result.append(SemanticChunk(vector: try embed(.image(Self.png(image)))))
            try await addText(Self.ocr(image))
        } else if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), !document.isLocked else { throw LibraryError.message("无法读取 PDF 或文档已加密。") }
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { throw LibraryError.message("无法读取 PDF 第 \(index + 1) 页。") }
                let image = page.thumbnail(of: CGSize(width: 768, height: 768), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
                let text = (page.string ?? "").precomposedStringWithCompatibilityMapping.trimmed
                try await addText(text.isEmpty ? image.map(Self.ocr) ?? "" : text, page: index + 1)
                if let image { result.append(SemanticChunk(vector: try embed(.image(Self.png(image))), page: index + 1)) }
                await Task.yield()
            }
        } else if kind == .video {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw LibraryError.message("无法读取视频时长。") }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            // shortcut: a frame every five seconds can miss brief cuts; add scene detection after real-library evaluation.
            for seconds in stride(from: 0.0, to: duration, by: 5) {
                try Task.checkCancellation()
                let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
                result.append(SemanticChunk(vector: try embed(.image(Self.png(frame.image))), seconds: frame.actualTime.seconds))
            }
        } else if kind == .document {
            let text: String
            if ["rtf", "doc", "docx"].contains(url.pathExtension.lowercased()) {
                text = try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
            } else { text = try String(contentsOf: url, encoding: .utf8) }
            try await addText(text.precomposedStringWithCompatibilityMapping)
        }
        guard !result.isEmpty else { throw LibraryError.message("此素材没有可索引的内容。") }
        return result
    }
    public nonisolated static func textSegments(_ text: String) -> [String] {
        let characters = Array(text.trimmed)
        return stride(from: 0, to: characters.count, by: 900).map { String(characters[$0..<min($0 + 1000, characters.count)]) }
    }
    public nonisolated static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw LibraryError.message("无法编码索引图像。") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw LibraryError.message("索引图像编码失败。") }
        return data as Data
    }
    private nonisolated static func ocr(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.recognitionLanguages = ["zh-Hans", "en-US"]; request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
            return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
        } catch { return "" }
    }
}
