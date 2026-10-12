import Foundation
import CryptoKit
import Darwin

public actor LibraryRepository {
    public nonisolated let root: URL
    let db: SQLite
    private let lockFD: Int32
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    var unlockedFolders: Set<String> = []

    public init(url: URL, create: Bool = false) throws {
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        let manifest = root.appendingPathComponent("library.json")
        if create {
            if fm.fileExists(atPath: root.path), !(try fm.contentsOfDirectory(atPath: root.path)).isEmpty {
                throw LibraryError.message("请选择一个空文件夹，新资源库不会覆盖已有文件。")
            }
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["format": "HunterFile", "version": 1], options: [.prettyPrinted]).write(to: manifest, options: .atomic)
        }
        guard let data = try? Data(contentsOf: manifest),
              let info = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              info["format"] as? String == "HunterFile", info["version"] as? Int == 1 else {
            throw LibraryError.message("这不是受支持的 HunterFile 资源库。迁移 Eagle 请使用“导入 Eagle 资源库”。")
        }
        if !create && !fm.fileExists(atPath: root.appendingPathComponent("library.sqlite").path) {
            throw LibraryError.message("资源库数据库缺失。请恢复完整备份，不会创建空库覆盖现有素材。")
        }
        for name in ["library.sqlite", "assets", ".lock"] {
            let path = root.appendingPathComponent(name)
            guard path.resolvingSymlinksInPath().path == path.path else { throw LibraryError.message("资源库的数据库和素材目录不能是符号链接。") }
        }
        let fd = Darwin.open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LibraryError.message("无法写入资源库，请检查磁盘和访问权限。") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); throw LibraryError.message("此资源库已被另一个 HunterFile 实例打开。") }
        do {
            let database = try SQLite(url: root.appendingPathComponent("library.sqlite"))
            try database.execute("""
                CREATE TABLE IF NOT EXISTS assets (
                  id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, ext TEXT NOT NULL,
                  bytes INTEGER NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL,
                  imported REAL NOT NULL, modified REAL NOT NULL, rating INTEGER NOT NULL,
                  favorite INTEGER NOT NULL, trash REAL, hash TEXT NOT NULL, search TEXT NOT NULL, data TEXT NOT NULL
                )
                """)
            for sql in [
                "CREATE INDEX IF NOT EXISTS assets_hash ON assets(hash)",
                "CREATE INDEX IF NOT EXISTS assets_imported ON assets(trash, imported DESC)",
                "CREATE INDEX IF NOT EXISTS assets_kind ON assets(kind)",
                "CREATE TABLE IF NOT EXISTS folders (id TEXT PRIMARY KEY, parent TEXT, name TEXT NOT NULL, data TEXT NOT NULL)",
                "CREATE TABLE IF NOT EXISTS smart_folders (id TEXT PRIMARY KEY, data TEXT NOT NULL)",
                "CREATE TABLE IF NOT EXISTS preferences (key TEXT PRIMARY KEY, data TEXT NOT NULL)",
                "CREATE TABLE IF NOT EXISTS semantic_assets (asset TEXT PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE, fingerprint TEXT NOT NULL, version TEXT NOT NULL)",
                "CREATE TABLE IF NOT EXISTS semantic_chunks (asset TEXT NOT NULL REFERENCES semantic_assets(asset) ON DELETE CASCADE, ordinal INTEGER NOT NULL, data TEXT NOT NULL, vector BLOB NOT NULL, PRIMARY KEY(asset, ordinal))"
            ] { try database.execute(sql) }
            guard try database.rows("PRAGMA quick_check").first?.values.first == "ok" else { throw LibraryError.message("资源库完整性检查失败，请使用备份。") }
            try fm.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
            self.root = root; self.db = database; self.lockFD = fd
        } catch { flock(fd, LOCK_UN); Darwin.close(fd); throw error }
    }

    deinit { flock(lockFD, LOCK_UN); Darwin.close(lockFD) }

    public nonisolated func fileURL(for asset: Asset) -> URL {
        root.appendingPathComponent(asset.relativePath)
    }
    public nonisolated func thumbnailURL(for asset: Asset) -> URL {
        root.appendingPathComponent("assets/\(asset.id)/thumbnail.png")
    }
    public nonisolated func checkedURL(_ relative: String) throws -> URL {
        let requested = root.appendingPathComponent(relative).standardizedFileURL
        let url = requested.resolvingSymlinksInPath()
        guard !relative.hasPrefix("/"), url.path == requested.path, url.path.hasPrefix(root.path + "/assets/") else {
            throw LibraryError.message("素材路径无效，拒绝访问资源库以外的文件。")
        }
        return url
    }
    public func asset(id: String) throws -> Asset? {
        let visible = visibility(in: try allFolders())
        return try db.rows("SELECT data FROM assets WHERE id = ? AND \(visible.0)", [id] + visible.1).first.map { try decodeAsset($0) }
    }
    public func assets(ids: [String]) throws -> [Asset] {
        let visible = visibility(in: try allFolders())
        var found: [String: Asset] = [:], seen: Set<String> = []
        let uniqueIDs = ids.filter { seen.insert($0).inserted }
        for offset in stride(from: 0, to: uniqueIDs.count, by: 500) {
            let batch = Array(uniqueIDs[offset..<min(offset + 500, uniqueIDs.count)])
            let sql = "SELECT data FROM assets WHERE id IN (\(batch.map { _ in "?" }.joined(separator: ","))) AND \(visible.0)"
            for row in try db.rows(sql, batch + visible.1) { let asset = try decodeAsset(row); found[asset.id] = asset }
        }
        return uniqueIDs.compactMap { found[$0] }
    }
    func decodeAsset(_ row: [String: String]) throws -> Asset {
        let asset = try decoder.decode(Asset.self, from: Data((row["data"] ?? "").utf8))
        try validateAssetPath(asset)
        return asset
    }
    func validateAssetPath(_ asset: Asset) throws {
        _ = try checkedURL(asset.relativePath)
        let filename = asset.ext.isEmpty ? "original" : "original.\(asset.ext.safeFilename)"
        guard UUID(uuidString: asset.id) != nil, asset.relativePath == "assets/\(asset.id)/\(filename)" else { throw LibraryError.message("资源库包含无效素材路径或标识。") }
    }
    public func save(_ assets: [Asset]) throws {
        try db.transaction { for var asset in assets {
            guard try self.asset(id: asset.id) != nil else { throw LibraryError.message("素材已不存在，请刷新资源库。") }
            asset.modifiedAt = Date()
            try upsert(asset)
        } }
    }
    public func modify(ids: [String], _ mutation: @Sendable (inout Asset) -> Void) throws -> [Asset] {
        try db.transaction {
            let previous = try assets(ids: ids)
            for var asset in previous { mutation(&asset); asset.modifiedAt = Date(); try upsert(asset) }
            return previous
        }
    }
    public func moveAssets(ids: [String], fromFolder sourceID: String, toFolder targetID: String, includeSubfolders: Bool = false) throws -> [Asset] {
        guard sourceID != targetID else { return [] }
        let folders = try allFolders()
        guard folders.contains(where: { $0.id == sourceID }), let target = folders.first(where: { $0.id == targetID }) else {
            throw LibraryError.message("移动的来源或目标文件夹已不存在。")
        }
        guard Set([sourceID, targetID]).isDisjoint(with: inaccessibleIDs(in: folders)) else { throw LibraryError.message("请先解锁文件夹。") }
        let sourceIDs = includeSubfolders ? descendants(sourceID, in: folders) : [sourceID]
        let movingIDs = try assets(ids: ids).filter { !Set($0.folderIDs).isDisjoint(with: sourceIDs) }.map(\.id)
        return try modify(ids: movingIDs) { asset in
            asset.folderIDs.removeAll { sourceIDs.contains($0) }
            if !asset.folderIDs.contains(targetID) { asset.folderIDs.append(targetID) }
            asset.tags = Array(Set(asset.tags + target.autoTags)).sorted()
        }
    }
    func upsert(_ asset: Asset) throws {
        try validateAssetPath(asset)
        guard UUID(uuidString: asset.id) != nil, (0...5).contains(asset.rating), !asset.name.trimmed.isEmpty else { throw LibraryError.message("素材名称、标识或评分无效。") }
        let json = String(decoding: try encoder.encode(asset), as: UTF8.self)
        try db.execute("""
            INSERT INTO assets (id,name,kind,ext,bytes,width,height,imported,modified,rating,favorite,trash,hash,search,data)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
            name=excluded.name,kind=excluded.kind,ext=excluded.ext,bytes=excluded.bytes,width=excluded.width,height=excluded.height,
            imported=excluded.imported,modified=excluded.modified,rating=excluded.rating,favorite=excluded.favorite,
            trash=excluded.trash,hash=excluded.hash,search=excluded.search,data=excluded.data
            """, [asset.id, asset.name, asset.kind.rawValue, asset.ext, String(asset.byteCount), String(asset.width), String(asset.height),
                    String(asset.importedAt.timeIntervalSince1970), String(asset.modifiedAt.timeIntervalSince1970), String(asset.rating),
                    asset.favorite ? "1" : "0", asset.trashedAt.map { String($0.timeIntervalSince1970) }, asset.hash, asset.searchable, json])
        try db.execute("DELETE FROM semantic_assets WHERE asset = ? AND fingerprint != ?", [asset.id, asset.semanticFingerprint])
    }

    public func importFile(_ source: URL, folderIDs: [String] = [], tags: [String] = [], sourceURL: String = "", allowDuplicate: Bool = false) throws -> ImportResult {
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        guard source.isFileURL, !source.path.hasPrefix(root.path + "/") else { throw LibraryError.message("不能将资源库自身再次导入。") }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw LibraryError.message("只支持导入普通文件：\(source.lastPathComponent)") }
        var asset = Asset(name: source.deletingPathExtension().lastPathComponent, ext: source.pathExtension)
        asset.folderIDs = Array(Set(folderIDs))
        let folders = try allFolders()
        guard Set(folderIDs).isSubset(of: Set(folders.map(\.id))) else { throw LibraryError.message("导入目标文件夹已不存在。") }
        guard Set(folderIDs).isDisjoint(with: inaccessibleIDs(in: folders)) else { throw LibraryError.message("请先解锁导入目标文件夹。") }
        asset.tags = Array(Set(tags + folders.filter { folderIDs.contains($0.id) }.flatMap(\.autoTags))).sorted()
        asset.sourceURL = sourceURL
        asset.fileDate = values.creationDate ?? values.contentModificationDate ?? Date()
        let fm = FileManager.default
        let staging = root.appendingPathComponent(".import-\(asset.id)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let filename = asset.ext.isEmpty ? "original" : "original.\(asset.ext.safeFilename)"
        let copied = staging.appendingPathComponent(filename)
        try fm.copyItem(at: source, to: copied)
        let after = try URL(fileURLWithPath: source.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard values.fileSize == after.fileSize, values.contentModificationDate == after.contentModificationDate else { throw LibraryError.message("文件正在修改，请等待写入完成后重试。") }
        asset.hash = try Self.sha256(copied)
        let visible = visibility(in: folders)
        if !allowDuplicate, let existing = try db.rows("SELECT data FROM assets WHERE hash = ? AND trash IS NULL AND \(visible.0) LIMIT 1", [asset.hash] + visible.1).first {
            var duplicate = try decodeAsset(existing)
            duplicate.tags = Array(Set(duplicate.tags + asset.tags)).sorted()
            duplicate.folderIDs = Array(Set(duplicate.folderIDs + asset.folderIDs))
            try upsert(duplicate)
            return ImportResult(asset: duplicate, duplicate: true)
        }
        asset.byteCount = Int64(try copied.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        asset.relativePath = "assets/\(asset.id)/\(filename)"
        try encoder.encode(asset).write(to: staging.appendingPathComponent(".pending-import.json"), options: .atomic)
        let destination = root.appendingPathComponent("assets/\(asset.id)")
        try fm.moveItem(at: staging, to: destination)
        do { try upsert(asset) }
        catch { try? fm.removeItem(at: destination); throw error }
        try? fm.removeItem(at: destination.appendingPathComponent(".pending-import.json"))
        return ImportResult(asset: asset, duplicate: false)
    }

    public func recoverInterruptedImports() throws -> Int {
        var recovered = 0
        let fm = FileManager.default
        for directory in try fm.contentsOfDirectory(at: root.appendingPathComponent("assets"), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let pending = directory.appendingPathComponent(".pending-import.json")
            guard fm.fileExists(atPath: pending.path) else { continue }
            let asset = try decoder.decode(Asset.self, from: Data(contentsOf: pending))
            try validateAssetPath(asset)
            guard directory.lastPathComponent == asset.id, fm.fileExists(atPath: fileURL(for: asset).path) else { throw LibraryError.message("发现不完整的导入恢复记录：\(directory.lastPathComponent)") }
            if try db.scalar("SELECT COUNT(*) FROM assets WHERE id = ?", [asset.id]) == 0 { try upsert(asset); recovered += 1 }
            try fm.removeItem(at: pending)
        }
        return recovered
    }

    public func updateAnalysis(id: String, width: Int, height: Int, duration: Double, colors: [String], text: String? = nil) throws {
        guard var asset = try asset(id: id) else { return }
        asset.width = max(0, width); asset.height = max(0, height)
        asset.duration = duration.isFinite ? max(0, duration) : 0
        asset.colors = colors
        if let text { asset.extractedText = text }
        try upsert(asset)
    }

    public func allFolders() throws -> [LibraryFolder] {
        try db.rows("SELECT data FROM folders ORDER BY json_extract(data,'$.sortOrder') IS NULL, json_extract(data,'$.sortOrder'), name COLLATE NOCASE, id").map { try decoder.decode(LibraryFolder.self, from: Data(($0["data"] ?? "").utf8)) }
    }
    public func saveFolder(_ folder: LibraryFolder) throws {
        guard !folder.name.trimmed.isEmpty else { throw LibraryError.message("请输入文件夹名称。") }
        let existing = try allFolders()
        let inaccessible = inaccessibleIDs(in: existing)
        guard !inaccessible.contains(folder.id), folder.parentID.map({ !inaccessible.contains($0) }) ?? true else { throw LibraryError.message("请先解锁文件夹。") }
        if let parent = folder.parentID {
            let folders = try allFolders()
            guard folders.contains(where: { $0.id == parent }), !descendants(folder.id, in: folders).contains(parent) else {
                throw LibraryError.message("文件夹不能移动到自身或其子文件夹。")
            }
        }
        var folder = folder
        if let previous = existing.first(where: { $0.id == folder.id }), previous.parentID != folder.parentID { folder.sortOrder = nil }
        try writeFolder(folder)
        if folder.password != nil { unlockedFolders.insert(folder.id) }
    }
    public func moveFolder(id: String, toParent parentID: String?, before siblingID: String? = nil) throws {
        let folders = try allFolders()
        guard var folder = folders.first(where: { $0.id == id }) else { throw LibraryError.message("要移动的文件夹已不存在。") }
        let inaccessible = inaccessibleIDs(in: folders)
        guard !inaccessible.contains(id), parentID.map({ !inaccessible.contains($0) }) ?? true else { throw LibraryError.message("请先解锁文件夹。") }
        if let parentID {
            guard folders.contains(where: { $0.id == parentID }), !descendants(id, in: folders).contains(parentID) else {
                throw LibraryError.message("文件夹不能移动到自身或其子文件夹。")
            }
        }
        var siblings = folders.filter { $0.parentID == parentID && $0.id != id }
        let index: Int
        if let siblingID {
            guard let position = siblings.firstIndex(where: { $0.id == siblingID }) else { throw LibraryError.message("目标位置已变化，请重新拖动。") }
            index = position
        } else { index = siblings.count }
        folder.parentID = parentID
        siblings.insert(folder, at: index)
        try db.transaction {
            for (index, var sibling) in siblings.enumerated() {
                sibling.sortOrder = index
                try writeFolder(sibling)
            }
        }
    }
    private func writeFolder(_ folder: LibraryFolder) throws {
        try db.execute("INSERT INTO folders (id,parent,name,data) VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET parent=excluded.parent,name=excluded.name,data=excluded.data",
                       [folder.id, folder.parentID, folder.name, String(decoding: try encoder.encode(folder), as: UTF8.self)])
    }
    public func deleteFolder(id: String) throws {
        guard try lockedAncestor(of: id) == nil else { throw LibraryError.message("请先解锁文件夹后再删除分类。") }
        let folders = try allFolders()
        let ids = descendants(id, in: folders)
        guard ids.isDisjoint(with: inaccessibleIDs(in: folders)) else { throw LibraryError.message("此分类包含锁定的子文件夹，请先解锁后再删除。") }
        try db.transaction {
            for row in try db.rows("SELECT data FROM assets") {
                var asset = try decodeAsset(row)
                if !Set(asset.folderIDs).isDisjoint(with: ids) { asset.folderIDs.removeAll { ids.contains($0) }; try upsert(asset) }
            }
            for id in ids { try db.execute("DELETE FROM folders WHERE id = ?", [id]) }
        }
    }
    func descendants(_ id: String, in folders: [LibraryFolder]) -> Set<String> {
        var result: Set<String> = [id], queue = [id]
        while let next = queue.popLast() {
            for child in folders where child.parentID == next {
                if result.insert(child.id).inserted { queue.append(child.id) }
            }
        }
        return result
    }
    public func saveSmartFolder(_ folder: SmartFolder) throws {
        guard !folder.name.trimmed.isEmpty, !folder.filters.isEmpty else { throw LibraryError.message("智能文件夹需要名称和筛选条件。") }
        guard folder.semanticQuery.map({ !$0.trimmed.isEmpty && $0.count <= 1000 }) != false,
              folder.minimumSimilarity.map({ $0.isFinite && (0...1).contains($0) }) != false else { throw LibraryError.message("语义描述不能为空，相关度门槛必须在 0 到 1 之间。") }
        try db.execute("INSERT INTO smart_folders (id,data) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data", [folder.id, String(decoding: try encoder.encode(folder), as: UTF8.self)])
    }
    public func deleteSmartFolder(id: String) throws { try db.execute("DELETE FROM smart_folders WHERE id = ?", [id]) }
    public func renameTag(_ old: String, to new: String) throws {
        let folders = try allFolders(), visible = visibility(in: try allFolders())
        try db.transaction {
            for row in try db.rows("SELECT data FROM assets WHERE \(visible.0) AND EXISTS (SELECT 1 FROM json_each(assets.data, '$.tags') WHERE value = ?)", visible.1 + [old]) {
                var asset = try decodeAsset(row)
                asset.tags = Array(Set(asset.tags.filter { $0 != old } + (new.trimmed.isEmpty ? [] : [new.trimmed]))).sorted()
                try upsert(asset)
            }
            for var folder in folders where folder.autoTags.contains(old) && !inaccessibleIDs(in: folders).contains(folder.id) {
                folder.autoTags = Array(Set(folder.autoTags.filter { $0 != old } + (new.trimmed.isEmpty ? [] : [new.trimmed]))).sorted()
                try saveFolder(folder)
            }
        }
    }
    public func setTrashed(ids: [String], trashed: Bool) throws {
        try db.transaction { for var asset in try assets(ids: ids) { asset.trashedAt = trashed ? Date() : nil; try upsert(asset) } }
    }
    public func removeToSystemTrash(ids: [String]) throws {
        for asset in try assets(ids: ids) where asset.trashedAt != nil {
            try Task.checkCancellation()
            let directory = try checkedURL(asset.relativePath).deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try db.execute("DELETE FROM assets WHERE id = ?", [asset.id])
                continue
            }
            try encoder.encode(asset).write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: directory, resultingItemURL: &trashedURL)
            do { try db.execute("DELETE FROM assets WHERE id = ?", [asset.id]) }
            catch {
                if let trashedURL { try? FileManager.default.moveItem(at: trashedURL as URL, to: directory) }
                throw error
            }
        }
    }
    public func mergeDuplicates() throws -> Int {
        var count = 0
        let visible = visibility(in: try allFolders())
        try db.transaction {
            for group in try db.rows("SELECT hash FROM assets WHERE trash IS NULL AND \(visible.0) GROUP BY hash HAVING COUNT(*) > 1", visible.1) {
                try Task.checkCancellation()
                var assets = try db.rows("SELECT data FROM assets WHERE hash = ? AND trash IS NULL AND \(visible.0) ORDER BY imported", [group["hash"]] + visible.1).map(decodeAsset)
                guard let keeperIndex = assets.firstIndex(where: { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }) else { continue }
                var first = assets.remove(at: keeperIndex)
                first.tags = Array(Set(([first] + assets).flatMap(\.tags))).sorted()
                first.folderIDs = Array(Set(([first] + assets).flatMap(\.folderIDs)))
                first.rating = ([first] + assets).map(\.rating).max() ?? 0
                first.favorite = ([first] + assets).contains { $0.favorite }
                first.note = Array(Set(([first] + assets).map(\.note).filter { !$0.isEmpty })).sorted().joined(separator: "\n\n")
                first.annotations = ([first] + assets).flatMap(\.annotations)
                if first.sourceURL.isEmpty { first.sourceURL = assets.first(where: { !$0.sourceURL.isEmpty })?.sourceURL ?? "" }
                try upsert(first)
                for var extra in assets { extra.trashedAt = Date(); try upsert(extra); count += 1 }
            }
        }
        return count
    }
    public func preference<T: Decodable>(_ key: String, as: T.Type) throws -> T? {
        guard let value = try db.rows("SELECT data FROM preferences WHERE key = ?", [key]).first?["data"] else { return nil }
        return try decoder.decode(T.self, from: Data(value.utf8))
    }
    public func setPreference<T: Encodable>(_ key: String, value: T) throws {
        try db.execute("INSERT INTO preferences (key,data) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET data=excluded.data", [key, String(decoding: try encoder.encode(value), as: UTF8.self)])
    }
    public func backup(to destination: URL) throws {
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !destination.path.hasPrefix(root.path + "/"), !FileManager.default.fileExists(atPath: destination.path) else { throw LibraryError.message("备份必须保存到资源库以外的新文件夹。") }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Task.checkCancellation()
        try db.backup(to: staging.appendingPathComponent("library.sqlite"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("library.json"), to: staging.appendingPathComponent("library.json"))
        let sourceAssets = root.appendingPathComponent("assets"), targetAssets = staging.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: targetAssets, withIntermediateDirectories: true)
        for item in try FileManager.default.contentsOfDirectory(at: sourceAssets, includingPropertiesForKeys: nil) {
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: item, to: targetAssets.appendingPathComponent(item.lastPathComponent))
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: destination)
    }
    public func export(ids: [String], to destination: URL, includeMetadata: Bool) throws -> [URL] {
        let assets = try assets(ids: ids)
        var urls: [URL] = []
        for asset in assets {
            try Task.checkCancellation()
            let source = try checkedURL(asset.relativePath)
            let url = Self.uniqueURL(in: destination, filename: asset.filename.safeFilename)
            try FileManager.default.copyItem(at: source, to: url)
            urls.append(url)
            if includeMetadata {
                let metadata = Self.uniqueURL(in: destination, filename: url.lastPathComponent + ".json")
                try encoder.encode(asset).write(to: metadata, options: .withoutOverwriting)
            }
        }
        return urls
    }
    public nonisolated static func uniqueURL(in folder: URL, filename: String) -> URL {
        var candidate = folder.appendingPathComponent(filename.safeFilename), index = 2
        let ext = candidate.pathExtension, stem = candidate.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) (\(index))" + (ext.isEmpty ? "" : ".\(ext)")); index += 1
        }
        return candidate
    }
    public nonisolated static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
