import Foundation

public struct EagleImportEntry: Sendable {
    public var url: URL
    public var name: String
    public var tags: [String]
    public var folders: [String]
    public var note: String
    public var sourceURL: String
    public var rating: Int
    public var added: Date?
}

public struct EagleMigrationPlan: Sendable {
    public var folders: [LibraryFolder]
    public var entries: [EagleImportEntry]
    public var warnings: [String]

    public static func read(_ root: URL) throws -> Self {
        let fm = FileManager.default
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let metadata = root.appendingPathComponent("metadata.json")
        let library = try JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any]
        guard let library, let rawFolders = library["folders"] as? [[String: Any]] else { throw LibraryError.message("Eagle 资源库的 metadata.json 中缺少文件夹数据。") }
        var folders: [LibraryFolder] = [], mapping: [String: String] = [:]
        func visit(_ items: [[String: Any]], parent: String?, depth: Int) throws {
            guard depth < 100 else { throw LibraryError.message("Eagle 文件夹层级超过安全读取范围。") }
            for item in items {
                guard let id = item["id"] as? String, let name = item["name"] as? String else { continue }
                var folder = LibraryFolder(name: name, parentID: parent)
                folder.autoTags = item["tags"] as? [String] ?? []
                folder.note = item["description"] as? String ?? ""
                mapping[id] = folder.id; folders.append(folder)
                try visit(item["children"] as? [[String: Any]] ?? [], parent: folder.id, depth: depth + 1)
            }
        }
        try visit(rawFolders, parent: nil, depth: 0)
        let images = root.appendingPathComponent("images").resolvingSymlinksInPath()
        guard images.path.hasPrefix(root.path + "/") else { throw LibraryError.message("Eagle images 目录不能指向资源库外部。") }
        var entries: [EagleImportEntry] = [], warnings: [String] = []
        for directory in try fm.contentsOfDirectory(at: images, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                guard directory.pathExtension == "info", directory.resolvingSymlinksInPath().path.hasPrefix(images.path + "/") else { continue }
                guard let info = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("metadata.json"))) as? [String: Any], let name = info["name"] as? String, let ext = info["ext"] as? String else { throw LibraryError.message("缺少文件名或格式") }
                if info["isDeleted"] as? Bool == true { continue }
                let original = directory.appendingPathComponent(name + (ext.isEmpty ? "" : "." + ext)).standardizedFileURL.resolvingSymlinksInPath()
                guard original.path.hasPrefix(directory.resolvingSymlinksInPath().path + "/"), fm.fileExists(atPath: original.path) else { throw LibraryError.message("原文件不存在或路径不安全") }
                let unknown = (info["folders"] as? [String] ?? []).filter { mapping[$0] == nil }
                if !unknown.isEmpty { warnings.append("\(name)：\(unknown.count) 个旧文件夹引用不存在") }
                entries.append(EagleImportEntry(url: original, name: name, tags: info["tags"] as? [String] ?? [], folders: (info["folders"] as? [String] ?? []).compactMap { mapping[$0] }, note: info["annotation"] as? String ?? "", sourceURL: info["url"] as? String ?? "", rating: min(5, max(0, info["star"] as? Int ?? 0)), added: (info["modificationTime"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }))
            } catch { warnings.append("\(directory.lastPathComponent)：\(error.localizedDescription)") }
        }
        return Self(folders: folders, entries: entries, warnings: warnings)
    }
}
