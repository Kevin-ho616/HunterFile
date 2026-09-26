import AppKit
import AVFoundation
import ImageIO
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import Vision
import CoreText
import OpenEagleCore

struct MediaAnalysis: Sendable {
    var width = 0
    var height = 0
    var duration: Double = 0
    var colors: [String] = []
}

actor MediaService {
    static let shared = MediaService()
    static let palette = ["#E65B57", "#EFA348", "#E7CE5E", "#74A777", "#63B9BD", "#6E83E8", "#A485CC", "#D687B1", "#987B67", "#E7E5DF", "#85898E", "#30333A"]

    func analyze(_ url: URL, kind: AssetKind, thumbnail: URL) async -> MediaAnalysis {
        var result = MediaAnalysis()
        var preview: CGImage?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            result.width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            result.height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
            let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1
            if (5...8).contains(orientation) { swap(&result.width, &result.height) }
            preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        }
        if kind == .video || kind == .audio {
            let asset = AVURLAsset(url: url)
            if let duration = try? await asset.load(.duration) { result.duration = duration.seconds.isFinite ? duration.seconds : 0 }
            if kind == .video {
                if let track = try? await asset.loadTracks(withMediaType: .video).first,
                   let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) {
                    let rect = CGRect(origin: .zero, size: size).applying(transform)
                    result.width = Int(abs(rect.width)); result.height = Int(abs(rect.height))
                }
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 640, height: 640)
                preview = try? await generator.image(at: CMTime(seconds: min(1, result.duration / 2), preferredTimescale: 600)).image
            }
        }
        if url.pathExtension.lowercased() == "pdf", let page = PDFDocument(url: url)?.page(at: 0) {
            let size = page.bounds(for: .mediaBox).size
            result.width = Int(size.width); result.height = Int(size.height)
            preview = page.thumbnail(of: CGSize(width: 640, height: 640), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        if preview == nil {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 640, height: 640), scale: 1, representationTypes: .thumbnail)
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { preview = representation.cgImage }
        }
        if let preview {
            result.colors = Self.colors(in: preview)
            if let target = CGImageDestinationCreateWithURL(thumbnail as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(target, preview, nil)
                _ = CGImageDestinationFinalize(target)
            }
        }
        return result
    }

    func recognizeText(at url: URL) throws -> String {
        if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) { return document.string ?? "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(url: url).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
    }

    func classification(at url: URL) throws -> [String] {
        let request = VNClassifyImageRequest()
        try VNImageRequestHandler(url: url).perform([request])
        return Array((request.results ?? []).filter { $0.confidence >= 0.25 }.prefix(8).map(\.identifier))
    }

    func feature(at url: URL) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        try VNImageRequestHandler(url: url).perform([request])
        guard let observation = request.results?.first else { throw LibraryError.message("无法提取此文件的图像特征。") }
        return observation
    }

    func similar(to reference: URL, candidates: [(String, URL)], progress: @Sendable (Int) async -> Void) async throws -> [String] {
        // ponytail: one thumbnail scan per request; persist versioned feature prints if large libraries make this slow.
        let base = try feature(at: reference)
        var matches: [(String, Float)] = []
        for (index, pair) in candidates.enumerated() {
            try Task.checkCancellation()
            if let observation = try? feature(at: pair.1) {
                var distance: Float = 0
                if (try? base.computeDistance(&distance, to: observation)) != nil { matches.append((pair.0, distance)) }
            }
            if index % 20 == 0 { await progress(index) }
        }
        return matches.sorted { $0.1 < $1.1 }.prefix(100).map(\.0)
    }

    func exportImage(_ source: URL, to target: URL, format: String, maxPixels: Int, rotate: Bool = false) throws {
        guard let data = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw LibraryError.message("此文件无法转换成位图。") }
        let properties = CGImageSourceCopyPropertiesAtIndex(data, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let maximum = maxPixels > 0 ? maxPixels : max(width, height)
        let scale = min(1, Double(maximum) / Double(max(1, max(width, height))))
        guard Double(width) * Double(height) * scale * scale <= 160_000_000 else { throw LibraryError.message("转换结果超过 1.6 亿像素，请填写较小的最长边，或导出原始文件。") }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(data, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximum] as CFDictionary) else { throw LibraryError.message("此文件无法转换成位图。") }
        var image = cg
        if rotate {
            guard let context = CGContext(data: nil, width: cg.height, height: cg.width, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw LibraryError.message("无法分配图片处理内存。") }
            context.translateBy(x: 0, y: CGFloat(cg.width)); context.rotate(by: -.pi / 2)
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            if let rotated = context.makeImage() { image = rotated }
        }
        let type = format == "jpg" ? UTType.jpeg : (format == "tiff" ? .tiff : .png)
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, type.identifier as CFString, 1, nil) else { throw LibraryError.message("无法创建图片导出文件。") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LibraryError.message("图片导出失败。") }
    }

    private static func colors(in image: CGImage) -> [String] {
        let dimension = 40
        var pixels = [UInt8](repeating: 0, count: dimension * dimension * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: dimension, height: dimension, bitsPerComponent: 8, bytesPerRow: dimension * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: dimension, height: dimension)); return true
        }
        guard drawn else { return [] }
        let rgb = palette.map { hex -> (Double, Double, Double) in
            let number = Int(hex.dropFirst(), radix: 16) ?? 0
            return (Double((number >> 16) & 255), Double((number >> 8) & 255), Double(number & 255))
        }
        var counts = [Int](repeating: 0, count: palette.count)
        for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] > 128 {
            let alpha = Double(pixels[offset + 3]) / 255
            let r = Double(pixels[offset]) / alpha, g = Double(pixels[offset + 1]) / alpha, b = Double(pixels[offset + 2]) / alpha
            let index = rgb.indices.min { a, c in
                func distance(_ i: Int) -> Double { pow(r - rgb[i].0, 2) + pow(g - rgb[i].1, 2) + pow(b - rgb[i].2, 2) }
                return distance(a) < distance(c)
            } ?? 0
            counts[index] += 1
        }
        return counts.indices.sorted { counts[$0] > counts[$1] }.filter { counts[$0] > 40 }.prefix(5).map { palette[$0] }
    }
}

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.totalCostLimit = 100 * 1024 * 1024; cache.countLimit = 350 }
    func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let image = cache.object(forKey: key) { return image }
        let image: NSImage
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: url.lastPathComponent == "thumbnail.png" ? 640 : 4096] as CFDictionary) {
            image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } else { guard let fallback = NSImage(contentsOf: url) else { return nil }; image = fallback }
        cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
    func clear() { cache.removeAllObjects() }
}
