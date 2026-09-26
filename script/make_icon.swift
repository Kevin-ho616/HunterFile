import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let artwork = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/branding/openeagle-app-icon-minimal.svg")
guard let icon = NSImage(contentsOf: artwork) else { fatalError("Cannot load icon artwork: \(artwork.path)") }
let iconset = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSGraphicsContext.current!.cgContext.clear(rect)
        NSGraphicsContext.current!.imageInterpolation = .high
        icon.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(1) }
