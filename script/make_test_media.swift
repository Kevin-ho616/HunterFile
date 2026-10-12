// Local, original test fixtures. Usage: swift script/make_test_media.swift /absolute/output/path
import AppKit
import AVFoundation
import CoreVideo
import PDFKit

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let pdfURL = root.appendingPathComponent("HunterFiles PDF.pdf")
var page = CGRect(x: 0, y: 0, width: 600, height: 420)
let pdf = CGContext(pdfURL as CFURL, mediaBox: &page, nil)!
pdf.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.6, alpha: 1).setFill()
NSBezierPath(rect: CGRect(x: 0, y: 0, width: 600, height: 420)).fill()
("HunterFiles PDF\nNative media verification" as NSString).draw(in: CGRect(x: 40, y: 170, width: 520, height: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 32, weight: .semibold), .foregroundColor: NSColor.white])
NSGraphicsContext.restoreGraphicsState()
pdf.endPDFPage(); pdf.closePDF()
assert(PDFDocument(url: pdfURL)?.string?.contains("HunterFiles PDF") == true)

let rate = 48_000.0
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let audioURL = root.appendingPathComponent("HunterFiles Audio.wav")
do {
    let audio = try AVAudioFile(forWriting: audioURL, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000)!
    buffer.frameLength = buffer.frameCapacity
    for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * 440 / rate) * 0.05) }
    try audio.write(from: buffer)
}
let audioDuration = try await AVURLAsset(url: audioURL).load(.duration).seconds
assert(audioDuration > 1.9)

let videoURL = root.appendingPathComponent("HunterFiles Video.mov")
if FileManager.default.fileExists(atPath: videoURL.path) { try FileManager.default.removeItem(at: videoURL) }
let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
writer.add(input)
assert(writer.startWriting()); writer.startSession(atSourceTime: .zero)
for frame in 0..<60 {
    while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
    var pixelBuffer: CVPixelBuffer?
    assert(CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &pixelBuffer) == kCVReturnSuccess)
    let buffer = pixelBuffer!
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
    context.setFillColor(CGColor(red: 1, green: 0.7, blue: 0.2, alpha: 1)); context.fill(CGRect(x: frame * 4, y: 65, width: 55, height: 55))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    assert(adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
}
input.markAsFinished(); await writer.finishWriting()
assert(writer.status == .completed)
let video = AVURLAsset(url: videoURL)
let duration = try await video.load(.duration).seconds
assert(duration > 1.9)
let font = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf")
let target = root.appendingPathComponent("Arial.ttf")
if FileManager.default.fileExists(atPath: font.path), !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: font, to: target) }
print("PDF, 2-second WAV, 2-second H.264 video, and font fixtures: \(root.path)")
