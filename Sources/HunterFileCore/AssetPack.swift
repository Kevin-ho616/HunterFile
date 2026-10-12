import Foundation

public struct AssetPack: Codable, Sendable {
    public var format = "OpenEaglePack"
    public var version = 1
    public var assets: [Asset]
    public var folders: [LibraryFolder]
    public static func read(_ root: URL) throws -> Self {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let manifest = root.appendingPathComponent("pack.json")
        guard (try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 128 * 1024 * 1024 else { throw LibraryError.message("素材包元数据超过 128 MB。") }
        let pack = try JSONDecoder().decode(Self.self, from: Data(contentsOf: manifest))
        guard pack.format == "OpenEaglePack", pack.version == 1, Set(pack.assets.map(\.id)).count == pack.assets.count else { throw LibraryError.message("无法读取此版本的素材包。") }
        for asset in pack.assets {
            let filename = asset.ext.isEmpty ? "original" : "original.\(asset.ext.safeFilename)"
            let expected = "assets/\(asset.id)/\(filename)"
            let url = root.appendingPathComponent(asset.relativePath).standardizedFileURL.resolvingSymlinksInPath()
            guard UUID(uuidString: asset.id) != nil, asset.relativePath == expected, url.path == root.appendingPathComponent(expected).path, FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.message("素材包包含无效路径或缺失文件：\(asset.name)") }
        }
        return pack
    }
}

extension LibraryRepository {
    public func exportPack(ids: [String], to destination: URL) throws {
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !destination.path.hasPrefix(root.path + "/"), !FileManager.default.fileExists(atPath: destination.path) else { throw LibraryError.message("请选择资源库以外的新素材包名称。") }
        let items = try assets(ids: ids)
        guard !items.isEmpty else { throw LibraryError.message("没有可导出的素材。") }
        let folders = try allFolders()
        var included = Set(items.flatMap(\.folderIDs)), queue = Array(included)
        while let id = queue.popLast() {
            if let parent = folders.first(where: { $0.id == id })?.parentID, included.insert(parent).inserted { queue.append(parent) }
        }
        let exportedFolders = folders.filter { included.contains($0.id) }.map { folder in var copy = folder; copy.password = nil; return copy }
        let pack = AssetPack(assets: items, folders: exportedFolders)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".pack-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for asset in items {
            try Task.checkCancellation()
            let file = staging.appendingPathComponent(asset.relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: checkedURL(asset.relativePath), to: file)
        }
        try encoder.encode(pack).write(to: staging.appendingPathComponent("pack.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    public func importPack(_ source: URL) throws -> [ImportResult] {
        let pack = try AssetPack.read(source)
        var mapping: [String: String] = [:], visiting: Set<String> = []
        func createFolder(_ old: LibraryFolder) throws -> String {
            if let id = mapping[old.id] { return id }
            guard visiting.count < 100, visiting.insert(old.id).inserted else { throw LibraryError.message("素材包的文件夹层级无效。") }
            defer { visiting.remove(old.id) }
            var parent: String?
            if let parentID = old.parentID {
                guard let folder = pack.folders.first(where: { $0.id == parentID }) else { throw LibraryError.message("素材包缺少上级文件夹。") }
                parent = try createFolder(folder)
            }
            var folder = LibraryFolder(name: old.name, parentID: parent)
            folder.autoTags = old.autoTags; folder.note = old.note; folder.color = old.color; folder.icon = old.icon
            folder.sortOrder = old.sortOrder
            try saveFolder(folder); mapping[old.id] = folder.id; return folder.id
        }
        for folder in pack.folders { _ = try createFolder(folder) }
        var results: [ImportResult] = []
        for old in pack.assets {
            try Task.checkCancellation()
            var result = try importFile(source.appendingPathComponent(old.relativePath), folderIDs: old.folderIDs.compactMap { mapping[$0] }, tags: old.tags, sourceURL: old.sourceURL)
            var current = result.asset
            if !result.duplicate {
                current.name = old.name; current.note = old.note; current.rating = old.rating; current.favorite = old.favorite
                current.importedAt = old.importedAt; current.extractedText = old.extractedText; current.annotations = old.annotations
                current.width = old.width; current.height = old.height; current.duration = old.duration; current.colors = old.colors
            }
            try upsert(current); result.asset = current; results.append(result)
        }
        return results
    }
}
