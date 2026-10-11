import AppKit
import UniformTypeIdentifiers
import OpenEagleCore

extension AppStore {
    func captureScreenshot() {
        guard let repository else { return }
        let folders = destinationFolderIDs
        runJob("选择要截图的区域…") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("截图-\(UUID().uuidString.prefix(8)).png")
            defer { try? FileManager.default.removeItem(at: url); NSApp.activate(ignoringOtherApps: true) }
            NSApp.hide(nil)
            let status = try await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-x", url.path]
                try process.run(); process.waitUntilExit(); return process.terminationStatus
            }.value
            guard status == 0, FileManager.default.fileExists(atPath: url.path) else { self.notice = "截图已取消。"; return }
            let asset = try await repository.importFile(url, folderIDs: folders).asset
            await self.analyze(asset, in: repository); self.notice = "截图已保存到资源库。"
        }
    }
    func chooseImport() {
        let panel = NSOpenPanel()
        panel.title = "导入素材"; panel.message = "原文件会被复制到资源库，支持多个文件和文件夹。"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func chooseLibrary(create: Bool) {
        if create {
            let panel = NSSavePanel(); panel.title = "新建资源库"; panel.nameFieldStringValue = "新的资源库.openeagle"
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                let target = url.pathExtension.lowercased() == "openeagle" ? url : url.appendingPathExtension("openeagle")
                Task { await openLibrary(target, create: true) }
            }
        } else {
            let panel = NSOpenPanel(); panel.title = "打开 OpenEagle 资源库"; panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.treatsFilePackagesAsDirectories = true
            if panel.runModal() == .OK, let url = panel.url { Task { await openLibrary(url, create: false) } }
        }
    }
    func importURLs(_ urls: [URL], into explicitFolders: [String]? = nil, tags: [String] = []) {
        guard let repository else { return }
        if !urls.isEmpty && urls.allSatisfy({ !$0.isFileURL }) {
            let folders = explicitFolders ?? destinationFolderIDs
            runJob("收集网页素材…") {
                var imported = 0
                for (index, url) in urls.enumerated() {
                    try Task.checkCancellation()
                    self.progress = Double(index) / Double(urls.count)
                    do { let asset = try await WebCollector.collect(url.absoluteString, name: "", download: true, into: repository, folders: folders, tags: tags); await self.analyze(asset, in: repository); imported += 1 }
                    catch { self.activityErrors.append(error.localizedDescription) }
                }
                self.notice = "已收集 \(imported) 项网页素材。"
                if !self.activityErrors.isEmpty { self.sheet = .activity }
            }
            return
        }
        if urls.count == 1, let source = urls.first, source.pathExtension.lowercased() == "openeaglepack" {
            runJob("导入素材包…") {
                let results = try await repository.importPack(source)
                for (index, result) in results.enumerated() where !result.duplicate { self.progress = Double(index) / Double(max(1, results.count)); await self.analyze(result.asset, in: repository) }
                self.notice = "素材包已导入：\(results.filter { !$0.duplicate }.count) 项，分类与元数据已恢复。"
            }
            return
        }
        let destination = explicitFolders ?? destinationFolderIDs
        runJob("准备导入…") {
            let plan = try await Task.detached { try FileImportPlan.scan(urls, excluding: repository.root) }.value
            self.activityErrors = plan.warnings
            var folderMap: [String: String] = [:]
            for path in plan.folders.sorted(by: { $0.count < $1.count }) {
                let key = path.joined(separator: "/")
                let parent = path.count == 1 ? destination.first : folderMap[path.dropLast().joined(separator: "/")]
                let existing = (try await repository.allFolders()).first { $0.name == path.last && $0.parentID == parent }
                let folder = existing ?? LibraryFolder(name: path.last ?? "导入", parentID: parent)
                if existing == nil { try await repository.saveFolder(folder) }
                folderMap[key] = folder.id
            }
            var imported = 0, duplicates = 0
            for (index, entry) in plan.files.enumerated() {
                try Task.checkCancellation()
                self.progressTitle = "导入 \(index + 1)/\(plan.files.count) · \(entry.url.lastPathComponent)"
                self.progress = Double(index) / Double(max(1, plan.files.count))
                do {
                    let folders = entry.folder.isEmpty ? destination : folderMap[entry.folder.joined(separator: "/")].map { [$0] } ?? destination
                    let result = try await repository.importFile(entry.url, folderIDs: folders, tags: tags, allowDuplicate: UserDefaults.standard.bool(forKey: "allowDuplicates"))
                    if result.duplicate { duplicates += 1 } else {
                        imported += 1
                        await self.analyze(result.asset, in: repository)
                    }
                } catch { self.activityErrors.append("\(entry.url.lastPathComponent)：\(error.localizedDescription)") }
                if index % 20 == 0 { await self.refresh() }
            }
            self.progress = 1
            self.notice = "已导入 \(imported) 项，跳过 \(duplicates) 个重复项" + (self.activityErrors.isEmpty ? "" : "，\(self.activityErrors.count) 项需要查看")
            if !self.activityErrors.isEmpty { self.sheet = .activity }
        }
    }
    func analyze(_ asset: Asset, in repository: LibraryRepository) async {
        let analysis = await MediaService.shared.analyze(repository.fileURL(for: asset), kind: asset.kind, thumbnail: repository.thumbnailURL(for: asset))
        do { try await repository.updateAnalysis(id: asset.id, width: analysis.width, height: analysis.height, duration: analysis.duration, colors: analysis.colors) }
        catch { activityErrors.append("\(asset.name) 的预览信息：\(error.localizedDescription)") }
        if self.repository === repository, semanticEnabled { startSemanticIndex() }
    }
    func pasteFromClipboard() {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { importURLs(urls); return }
        if let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("剪贴板-\(UUID().uuidString.prefix(8)).png")
            do { try data.write(to: url); importTemporaryFile(url) } catch { self.error = error.localizedDescription }
            return
        }
        if let text = board.string(forType: .string), let url = URL(string: text.trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { sheet = .bookmark; return }
        notice = "剪贴板中没有可导入的文件或图片。"
    }
    func importTemporaryFile(_ url: URL) {
        guard let repository else { return }
        let folders = destinationFolderIDs
        runJob("保存素材…") {
            defer { try? FileManager.default.removeItem(at: url) }
            let result = try await repository.importFile(url, folderIDs: folders)
            await self.analyze(result.asset, in: repository)
            self.notice = "已保存到资源库"
        }
    }
    func saveWeb(_ text: String, name: String, download: Bool, tags: [String] = []) {
        guard let repository else { return }
        let folders = destinationFolderIDs
        runJob(download ? "下载素材…" : "保存书签…") {
            let asset = try await WebCollector.collect(text, name: name, download: download, into: repository, folders: folders, tags: tags)
            await self.analyze(asset, in: repository)
            self.notice = download ? "网页素材已导入" : "书签已保存"
        }
    }
    func chooseEagleLibrary() {
        let panel = NSOpenPanel(); panel.title = "导入 Eagle 资源库"; panel.message = "读取 .library 中的素材与分类并复制到 OpenEagle，原资源库保持完整。"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url, let repository else { return }
        runJob("读取 Eagle 资源库…") {
            let plan = try await Task.detached { try EagleMigrationPlan.read(url) }.value
            self.activityErrors = plan.warnings
            for folder in plan.folders { try Task.checkCancellation(); try await repository.saveFolder(folder) }
            var imported = 0, duplicates = 0
            for (index, entry) in plan.entries.enumerated() {
                try Task.checkCancellation()
                self.progress = Double(index) / Double(max(1, plan.entries.count))
                self.progressTitle = "迁移 \(index + 1)/\(plan.entries.count) · \(entry.name)"
                do {
                    let result = try await repository.importFile(entry.url, folderIDs: entry.folders, tags: entry.tags, sourceURL: entry.sourceURL)
                    if result.duplicate { duplicates += 1 } else { imported += 1 }
                    _ = try await repository.modify(ids: [result.asset.id]) { asset in
                        if !result.duplicate { asset.name = entry.name; if let date = entry.added { asset.importedAt = date } }
                        asset.rating = max(asset.rating, entry.rating)
                        if !entry.note.isEmpty && !asset.note.contains(entry.note) { asset.note = [asset.note, entry.note].filter { !$0.isEmpty }.joined(separator: "\n\n") }
                    }
                    if !result.duplicate { await self.analyze(result.asset, in: repository) }
                } catch { self.activityErrors.append("\(entry.name)：\(error.localizedDescription)") }
                if index % 25 == 0 { await self.refresh() }
            }
            self.notice = "迁移完成：\(imported) 个新素材，\(duplicates) 个重复项，\(self.activityErrors.count) 条提示。"
            self.sheet = .activity
        }
    }
    func chooseBackup() {
        guard let repository else { return }
        let panel = NSSavePanel(); panel.title = "备份完整资源库"; panel.nameFieldStringValue = "\(libraryName)-备份.openeagle"
        if panel.runModal() == .OK, let url = panel.url {
            let target = url.pathExtension.lowercased() == "openeagle" ? url : url.appendingPathExtension("openeagle")
            runJob("备份原件与数据库…") { try await repository.backup(to: target); self.notice = "备份已保存：\(target.lastPathComponent)" }
        }
    }
    func exportFolder(_ folder: LibraryFolder) {
        guard let repository else { return }
        let panel = NSOpenPanel(); panel.title = "导出文件夹：\(folder.name)"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        runJob("导出文件夹及子文件夹中的素材…") {
            let ids = try await repository.matchingIDs(scope: .folder(folder.id), filter: .init(), includeSubfolders: true)
            _ = try await repository.export(ids: ids, to: destination, includeMetadata: true)
            self.notice = "文件夹已导出：\(ids.count) 个素材及元数据。"
        }
    }
    func exportSelection(metadata: Bool, format: String = "original", maxPixels: Int = 0, rotate: Bool = false) {
        guard let repository else { return }
        if format == "pack" {
            let panel = NSSavePanel(); panel.title = "导出可迁移素材包"; panel.nameFieldStringValue = "素材包.openeaglepack"
            if panel.runModal() == .OK, let url = panel.url {
                let ids = Array(selection)
                let target = url.pathExtension.lowercased() == "openeaglepack" ? url : url.appendingPathExtension("openeaglepack")
                runJob("导出素材包…") { try await repository.exportPack(ids: ids, to: target); self.notice = "素材包已导出，包含原件、分类与元数据。" }
            }
            return
        }
        let panel = NSOpenPanel(); panel.title = "导出到文件夹"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let ids = selection
        runJob("导出素材…") {
            let items = try await repository.assets(ids: Array(ids))
            if format == "original" {
                _ = try await repository.export(ids: Array(ids), to: destination, includeMetadata: metadata)
            } else {
                for (index, item) in items.enumerated() {
                    try Task.checkCancellation()
                    self.progress = Double(index) / Double(max(1, items.count))
                    let target = LibraryRepository.uniqueURL(in: destination, filename: item.name + "." + format)
                    do { try await MediaService.shared.exportImage(repository.fileURL(for: item), to: target, format: format, maxPixels: maxPixels, rotate: rotate) }
                    catch { self.activityErrors.append("\(item.name)：\(error.localizedDescription)") }
                }
            }
            self.notice = "导出完成：\(items.count - self.activityErrors.count) 项"
            if !self.activityErrors.isEmpty { self.sheet = .activity }
        }
    }
    func recognizeSelection(classify: Bool = false) {
        guard let repository else { return }
        let ids = Array(selection)
        runJob(classify ? "本地图像分类…" : "识别图片文字…") {
            let items = try await repository.assets(ids: ids)
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                self.progress = Double(index) / Double(max(1, items.count))
                do {
                    if classify {
                        let labels = try await MediaService.shared.classification(at: repository.fileURL(for: item))
                        _ = try await repository.modify(ids: [item.id]) { $0.tags = Array(Set($0.tags + labels)).sorted() }
                    } else {
                        let text = try await MediaService.shared.recognizeText(at: repository.fileURL(for: item))
                        _ = try await repository.modify(ids: [item.id]) { $0.extractedText = text }
                    }
                } catch { self.activityErrors.append("\(item.name)：\(error.localizedDescription)") }
            }
            self.notice = classify ? "本地分类完成，标签可手动调整。" : "文字识别完成，结果可搜索与复制。"
            if !self.activityErrors.isEmpty { self.sheet = .activity }
        }
    }
    func findSimilar() {
        if semanticEnabled, let asset = selectedAsset, asset.kind == .image, let repository {
            searchSemanticImage(repository.thumbnailURL(for: asset), name: asset.name); return
        }
        guard let asset = selectedAsset, let repository else { return }
        runJob("分析相似素材…") {
            let ids = try await repository.matchingIDs(scope: .kind(.image), filter: .init())
            let items = try await repository.assets(ids: ids)
            let reference = repository.fileURL(for: asset)
            let matches = try await MediaService.shared.similar(to: reference, candidates: items.map { ($0.id, repository.thumbnailURL(for: $0)) }) { index in
                await MainActor.run { self.progress = Double(index) / Double(max(1, items.count)); self.progressTitle = "比较图像特征 \(index)/\(items.count)" }
            }
            self.similarityIDs = matches; self.notice = "按本地图像相似度排序，共 \(matches.count) 项。"; await self.refresh()
        }
    }
    func revealSelection() {
        guard let repository else { return }
        NSWorkspace.shared.activateFileViewerSelecting(selectedAssets.map { repository.fileURL(for: $0) })
    }
    func openExternally() {
        guard let asset = selectedAsset, let repository else { return }
        if asset.kind == .bookmark, let url = URL(string: asset.sourceURL), ["http", "https"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        else { NSWorkspace.shared.open(repository.fileURL(for: asset)) }
    }
    func copyFiles() {
        guard let repository else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(selectedAssets.map { repository.fileURL(for: $0) as NSURL })
    }
}

private struct FileImportPlan: Sendable {
    struct Entry: Sendable { var url: URL; var folder: [String] }
    var files: [Entry] = []
    var folders: [[String]] = []
    var warnings: [String] = []
    static func scan(_ urls: [URL], excluding root: URL) throws -> Self {
        var result = Self()
        let fm = FileManager.default
        for url in urls {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
            if resolved == root.path || resolved.hasPrefix(root.path + "/") { result.warnings.append("跳过资源库自身：\(url.lastPathComponent)"); continue }
            let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if info.isSymbolicLink == true { continue }
            if info.isRegularFile == true { result.files.append(Entry(url: url, folder: [])); continue }
            guard info.isDirectory == true else { continue }
            if ["library", "openeagle"].contains(url.pathExtension) { result.warnings.append("\(url.lastPathComponent)：请使用资源库迁移或打开功能。"); continue }
            result.folders.append([url.lastPathComponent])
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { path, error in result.warnings.append("\(path.lastPathComponent)：\(error.localizedDescription)"); return true }) else { continue }
            for case let file as URL in enumerator {
                let props = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                if props.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                let relative = Array(file.pathComponents.dropFirst(url.pathComponents.count))
                if props.isDirectory == true {
                    if ["library", "openeagle"].contains(file.pathExtension) { enumerator.skipDescendants(); continue }
                    result.folders.append([url.lastPathComponent] + relative)
                } else if props.isRegularFile == true { result.files.append(Entry(url: file, folder: [url.lastPathComponent] + relative.dropLast())) }
            }
        }
        return result
    }
}
