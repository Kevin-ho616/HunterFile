import AppKit
import CoreText
import OpenEagleCore

extension AppStore {
    func loadDemoLibrary() {
        guard !isBusy else { return }
        Task {
            let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!.appendingPathComponent("OpenEagle/示例素材库.openeagle")
            let exists = FileManager.default.fileExists(atPath: base.path)
            await openLibrary(base, create: !exists)
            guard let repository, repository.root == base.standardizedFileURL.resolvingSymlinksInPath(), !exists else { return }
            runJob("创建示例素材…") {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("openeagle-demo-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: temp) }
                let design = LibraryFolder(name: "设计灵感")
                var brand = LibraryFolder(name: "品牌与排版", parentID: design.id); brand.autoTags = ["排版"]
                var art = LibraryFolder(name: "形态与色彩", parentID: design.id); art.color = "#D687B1"
                let files = LibraryFolder(name: "文档与字体")
                for folder in [design, brand, art, files] { try await repository.saveFolder(folder) }
                let titles = ["Form & Feeling", "缓慢生长", "TYPE\nMATTERS", "Between\nthe lines", "色彩研究 01", "Objects of\nTomorrow", "GOOD\nIDEAS", "浮光 · Fluid", "Composition", "Quiet Space", "设计的秩序", "Play / Pause"]
                for index in titles.indices {
                    try Task.checkCancellation()
                    let url = temp.appendingPathComponent(titles[index].replacingOccurrences(of: "\n", with: " ").safeFilename + ".png")
                    try DemoArtwork.write(index: index, title: titles[index], to: url)
                    var asset = try await repository.importFile(url, folderIDs: [index % 3 == 1 ? brand.id : art.id], tags: index % 3 == 1 ? ["海报", "排版"] : ["灵感", "抽象"]).asset
                    asset.favorite = [0, 3, 7].contains(index); asset.rating = [0, 2, 4, 8].contains(index) ? 5 : (index % 3 == 0 ? 4 : 0)
                    asset.note = "OpenEagle 内置示例 · 可自由编辑、导出和删除。试试颜色筛选、标签和空格预览。"
                    asset.importedAt = Date().addingTimeInterval(-Double(index) * 3600)
                    try await repository.save([asset]); await self.analyze(asset, in: repository)
                    self.progress = Double(index + 1) / Double(titles.count)
                }
                let guide = temp.appendingPathComponent("欢迎使用 OpenEagle.md")
                try Data("# 欢迎使用 OpenEagle\n\n⌘I 导入文件，空格预览。拖动素材到侧栏文件夹进行归类。\n\n标签、备注、评分、图片标注都可搜索。原件复制到本地资源库，导出时自动避开同名文件。\n".utf8).write(to: guide)
                let doc = try await repository.importFile(guide, folderIDs: [files.id], tags: ["使用指南"]).asset
                await self.analyze(doc, in: repository)
                let font = NSFont.systemFont(ofSize: 16) as CTFont
                if let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL, FileManager.default.fileExists(atPath: url.path) {
                    let result = try await repository.importFile(url, folderIDs: [files.id], tags: ["字体"])
                    await self.analyze(result.asset, in: repository)
                }
                let bookmark = try await WebCollector.collect("https://en.eagle.cool/", name: "Eagle · 创作灵感", download: false, into: repository, folders: [], tags: ["工具"])
                await self.analyze(bookmark, in: repository)
                var filter = AssetFilter(); filter.minRating = 4
                try await repository.saveSmartFolder(SmartFolder(name: "精选素材 · 4 星以上", filters: [filter]))
                self.notice = "欢迎体验！这是独立示例库，你的其他资源库保持完整。"
            }
        }
    }
}

private enum DemoArtwork {
    @MainActor static func write(index: Int, title: String, to url: URL) throws {
        let width = 800, height = [1000, 1080, 820, 600][index % 4]
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw LibraryError.message("无法创建示例图像") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let palettes: [(NSColor, NSColor, NSColor)] = [
            (.init(red: 0.88, green: 0.90, blue: 0.79, alpha: 1), .init(red: 0.26, green: 0.39, blue: 0.23, alpha: 1), .init(white: 0.12, alpha: 1)),
            (.init(red: 0.94, green: 0.89, blue: 0.80, alpha: 1), .init(red: 0.87, green: 0.40, blue: 0.24, alpha: 1), .init(white: 0.18, alpha: 1)),
            (.init(red: 0.70, green: 0.66, blue: 0.90, alpha: 1), .init(red: 0.32, green: 0.24, blue: 0.68, alpha: 1), .white),
            (.init(red: 0.18, green: 0.25, blue: 0.37, alpha: 1), .init(red: 0.74, green: 0.82, blue: 0.92, alpha: 1), .white),
            (.init(red: 0.95, green: 0.67, blue: 0.70, alpha: 1), .init(red: 0.75, green: 0.19, blue: 0.24, alpha: 1), .init(white: 0.12, alpha: 1)),
            (.init(red: 0.91, green: 0.91, blue: 0.88, alpha: 1), .init(red: 0.33, green: 0.54, blue: 0.81, alpha: 1), .init(white: 0.12, alpha: 1))
        ]
        let colors = palettes[index % palettes.count]
        colors.0.setFill(); rect.fill()
        let cg = context.cgContext
        cg.saveGState()
        if index % 3 == 0 {
            for circle in stride(from: 9, through: 0, by: -1) {
                let diameter = CGFloat(55 + circle * 47)
                colors.1.withAlphaComponent(0.12 + Double(9 - circle) * 0.075).setFill()
                NSBezierPath(ovalIn: NSRect(x: 390 - diameter / 2, y: CGFloat(height) * 0.44 - diameter / 2, width: diameter, height: diameter)).fill()
            }
        } else if index % 3 == 1 {
            cg.translateBy(x: 420, y: CGFloat(height) * 0.41)
            for petal in 0..<12 {
                cg.saveGState(); cg.rotate(by: CGFloat(petal) * .pi / 6)
                colors.1.withAlphaComponent(0.70).setFill()
                NSBezierPath(roundedRect: NSRect(x: -36, y: 15, width: 72, height: 270), xRadius: 36, yRadius: 36).fill()
                cg.restoreGState()
            }
        } else {
            for line in 0..<8 {
                colors.1.withAlphaComponent(0.9 - Double(line) * 0.07).setFill()
                NSBezierPath(roundedRect: NSRect(x: 70 + line * 19, y: 90 + line * 35, width: 630 - line * 38, height: 220), xRadius: 110, yRadius: 110).fill()
            }
        }
        cg.restoreGState()
        let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: index % 3 == 2 ? 95 : 65, weight: .semibold), .foregroundColor: colors.2, .kern: -2]
        (title as NSString).draw(in: NSRect(x: 55, y: height - 260, width: 690, height: 205), withAttributes: heading)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium), .foregroundColor: colors.2.withAlphaComponent(0.7), .kern: 2]
        ("OPENEAGLE     /     CREATIVE STUDIES" as NSString).draw(at: NSPoint(x: 55, y: height - 50), withAttributes: small)
        ("COLLECTION 01                                      \(String(format: "%02d", index + 1))" as NSString).draw(at: NSPoint(x: 55, y: 35), withAttributes: small)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw LibraryError.message("示例图片编码失败") }
        try png.write(to: url)
    }
}
