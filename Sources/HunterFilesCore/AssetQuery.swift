import Foundation

extension LibraryRepository {
    public func snapshot(scope: LibraryScope = .all, filter: AssetFilter = .init(), sort: AssetSortOrder = .newest, limit: Int = 500, includeSubfolders: Bool = false) throws -> LibrarySnapshot {
        let folders = try allFolders()
        let visible = visibility(in: folders)
        let smart = try db.rows("SELECT data FROM smart_folders").map { try decoder.decode(SmartFolder.self, from: Data(($0["data"] ?? "").utf8)) }
        let (clause, values) = whereClause(scope: scope, filter: filter, folders: folders, smart: smart, includeSubfolders: includeSubfolders)
        let order: String = scope == .random ? AssetSortOrder.random.sql : sort.sql
        let total = try db.scalar("SELECT COUNT(*) FROM assets WHERE \(clause)", values)
        let assets = try db.rows("SELECT data FROM assets WHERE \(clause) ORDER BY \(order) LIMIT ?", values + [String(max(1, min(limit, 100_000)))]).map(decodeAsset)
        let summary = try db.rows("""
            SELECT COUNT(*) AS allCount, COALESCE(SUM(bytes),0) AS bytes,
            SUM(CASE WHEN json_array_length(data,'$.folderIDs') = 0 THEN 1 ELSE 0 END) AS uncategorized,
            SUM(CASE WHEN json_array_length(data,'$.tags') = 0 THEN 1 ELSE 0 END) AS untagged,
            SUM(favorite) AS favorites FROM assets WHERE trash IS NULL AND \(visible.0)
            """, visible.1).first ?? [:]
        var counts = ["all": Int(summary["allCount"] ?? "0") ?? 0, "trash": try db.scalar("SELECT COUNT(*) FROM assets WHERE trash IS NOT NULL AND \(visible.0)", visible.1)]
        for key in ["uncategorized", "untagged", "favorites"] { counts[key] = Int(summary[key] ?? "0") ?? 0 }
        for row in try db.rows("SELECT kind,COUNT(*) AS count FROM assets WHERE trash IS NULL AND \(visible.0) GROUP BY kind", visible.1) { counts[row["kind"] ?? ""] = Int(row["count"] ?? "0") ?? 0 }
        var tags: [String: Int] = [:], folderCounts: [String: Int] = [:]
        for row in try db.rows("SELECT j.value AS tag,COUNT(*) AS count FROM assets, json_each(assets.data,'$.tags') j WHERE trash IS NULL AND \(visible.0) GROUP BY j.value", visible.1) { tags[row["tag"] ?? ""] = Int(row["count"] ?? "0") ?? 0 }
        let folderCountSQL = includeSubfolders ? """
            WITH RECURSIVE tree(folder, descendant) AS (
                SELECT id, id FROM folders
                UNION
                SELECT tree.folder, folders.id FROM tree JOIN folders ON folders.parent = tree.descendant
            )
            SELECT tree.folder, COUNT(DISTINCT assets.id) AS count
            FROM assets, json_each(assets.data,'$.folderIDs') j JOIN tree ON tree.descendant = j.value
            WHERE trash IS NULL AND \(visible.0) GROUP BY tree.folder
            """ : "SELECT j.value AS folder, COUNT(DISTINCT assets.id) AS count FROM assets, json_each(assets.data,'$.folderIDs') j WHERE trash IS NULL AND \(visible.0) GROUP BY j.value"
        for row in try db.rows(folderCountSQL, visible.1) { folderCounts[row["folder"] ?? ""] = Int(row["count"] ?? "0") ?? 0 }
        return LibrarySnapshot(assets: assets, total: total, folders: folders, smartFolders: smart, tags: tags, counts: counts, folderCounts: folderCounts, totalBytes: Int64(summary["bytes"] ?? "0") ?? 0)
    }
    public func matchingIDs(scope: LibraryScope, filter: AssetFilter, includeSubfolders: Bool = false) throws -> [String] {
        let smart = try db.rows("SELECT data FROM smart_folders").map { try decoder.decode(SmartFolder.self, from: Data(($0["data"] ?? "").utf8)) }
        let (clause, values) = whereClause(scope: scope, filter: filter, folders: try allFolders(), smart: smart, includeSubfolders: includeSubfolders)
        return try db.rows("SELECT id FROM assets WHERE \(clause)", values).compactMap { $0["id"] }
    }
    func whereClause(scope: LibraryScope, filter: AssetFilter, folders: [LibraryFolder], smart: [SmartFolder], includeSubfolders: Bool, semanticContext: Bool = false) -> (String, [String?]) {
        var clauses = [scope == .trash ? "trash IS NOT NULL" : "trash IS NULL"]
        var values: [String?] = []
        let visible = visibility(in: folders)
        clauses.append(visible.0); values += visible.1
        switch scope {
        case .uncategorized: clauses.append("json_array_length(data,'$.folderIDs') = 0")
        case .untagged: clauses.append("json_array_length(data,'$.tags') = 0")
        case .favorites: clauses.append("favorite = 1")
        case .recent: clauses.append("json_extract(data,'$.openedAt') IS NOT NULL")
        case .duplicates:
            clauses.append("hash IN (SELECT hash FROM assets WHERE trash IS NULL AND \(visible.0) GROUP BY hash HAVING COUNT(*) > 1)")
            values += visible.1
        case .folder(let id):
            let ids = includeSubfolders ? descendants(id, in: folders).sorted() : [id]
            clauses.append("EXISTS (SELECT 1 FROM json_each(assets.data,'$.folderIDs') WHERE value IN (\(ids.map { _ in "?" }.joined(separator: ","))))")
            values += ids
        case .tag(let tag): clauses.append("EXISTS (SELECT 1 FROM json_each(assets.data,'$.tags') WHERE value = ?)"); values.append(tag)
        case .kind(let kind): clauses.append("kind = ?"); values.append(kind.rawValue)
        case .smart(let id):
            if let folder = smart.first(where: { $0.id == id }) {
                // Unresolved semantic membership must never broaden to the whole library.
                if folder.isSemantic && !semanticContext { clauses.append("0") }
                let parts = folder.filters.map(filterClause)
                clauses.append("(" + parts.map { "(" + $0.0 + ")" }.joined(separator: folder.matchAll ? " AND " : " OR ") + ")")
                values += parts.flatMap(\.1)
            } else { clauses.append("0") }
        default: break
        }
        let part = filterClause(filter)
        clauses.append(part.0); values += part.1
        return (clauses.joined(separator: " AND "), values)
    }
    private func filterClause(_ filter: AssetFilter) -> (String, [String?]) {
        var clauses: [String] = [], values: [String?] = []
        func add(_ sql: String, _ value: String) { clauses.append(sql); values.append(value) }
        // Literal substring matching preserves Chinese text and treats %, _ and quotes as user text.
        for term in filter.query.searchFolded.split(whereSeparator: \.isWhitespace) { add("instr(search, ?) > 0", String(term)) }
        if let kind = filter.kind { add("kind = ?", kind.rawValue) }
        if !filter.ext.trimmed.isEmpty { add("ext = ?", filter.ext.trimmed.lowercased().replacingOccurrences(of: ".", with: "")) }
        if !filter.tag.trimmed.isEmpty { add("EXISTS (SELECT 1 FROM json_each(assets.data,'$.tags') WHERE value = ?)", filter.tag.trimmed) }
        if filter.minRating > 0 { add("rating >= ?", String(filter.minRating)) }
        if filter.minWidth > 0 { add("width >= ?", String(filter.minWidth)) }
        if filter.minHeight > 0 { add("height >= ?", String(filter.minHeight)) }
        if filter.minBytes > 0 { add("bytes >= ?", String(filter.minBytes)) }
        if filter.maxBytes > 0 { add("bytes <= ?", String(filter.maxBytes)) }
        if filter.days > 0 { add("imported >= ?", String(Date().addingTimeInterval(-Double(filter.days) * 86400).timeIntervalSince1970)) }
        switch filter.shape {
        case "landscape": clauses.append("width > height AND height > 0")
        case "portrait": clauses.append("height > width AND width > 0")
        case "square": clauses.append("width = height AND width > 0")
        case "wide": clauses.append("width >= height * 2 AND height > 0")
        default: break
        }
        if !filter.color.isEmpty { add("EXISTS (SELECT 1 FROM json_each(assets.data,'$.colors') WHERE value = ?)", filter.color) }
        return (clauses.isEmpty ? "1" : clauses.joined(separator: " AND "), values)
    }
}
