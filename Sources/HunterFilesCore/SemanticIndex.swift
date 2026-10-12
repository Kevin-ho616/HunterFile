import Foundation
import CryptoKit
import Accelerate

extension Asset {
    public var semanticFingerprint: String { SHA256.hash(data: Data((hash + "\n" + kind.rawValue + "\n" + searchable).utf8)).map { String(format: "%02x", $0) }.joined() }
    public var generationFingerprint: String { semanticFingerprint + "\n" + (aiSummary ?? "") }
}

public struct SemanticHit: Codable, Sendable {
    public var assetID: String
    public var score: Float
    public var text: String
    public var page: Int?
    public var seconds: Double?
    public var literal: Bool
    public var indexed = true
    public var location: String {
        if let page { return "第 \(page) 页" }
        if let seconds { return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
        return ""
    }
}

extension LibraryRepository {
    public func semanticResults(vector: [Float], scope: LibraryScope = .all, filter: AssetFilter = .init(), includeSubfolders: Bool = false, limit: Int = 500, folderVector: [Float]? = nil) throws -> (assets: [Asset], hits: [SemanticHit], total: Int) {
        let hits = try semanticSearch(vector: vector, scope: scope, filter: filter, includeSubfolders: includeSubfolders, limit: 100_000, folderVector: folderVector)
        let page = Array(hits.prefix(max(1, min(limit, 100_000))))
        return (try assets(ids: page.map(\.assetID)), page, hits.count)
    }
    public func pendingSemanticAssets(version: String = LocalEmbedding.indexVersion) throws -> [Asset] {
        let visible = visibility(in: try allFolders())
        return try db.rows("SELECT data FROM assets WHERE trash IS NULL AND \(visible.0) AND NOT EXISTS (SELECT 1 FROM semantic_assets WHERE asset = assets.id AND version = ?) ORDER BY imported", visible.1 + [version]).map(decodeAsset)
    }
    public func semanticIndexedCount(version: String = LocalEmbedding.indexVersion) throws -> Int {
        let visible = visibility(in: try allFolders())
        return try db.scalar("SELECT COUNT(*) FROM assets WHERE trash IS NULL AND \(visible.0) AND id IN (SELECT asset FROM semantic_assets WHERE version = ?)", visible.1 + [version])
    }
    public func saveSemanticChunks(_ chunks: [SemanticChunk], for asset: Asset, version: String = LocalEmbedding.indexVersion) throws {
        try Task.checkCancellation()
        guard let current = try self.asset(id: asset.id), current.trashedAt == nil, current.semanticFingerprint == asset.semanticFingerprint else { return }
        guard !chunks.isEmpty else { throw LibraryError.message("索引内容不能为空。") }
        for chunk in chunks {
            try LocalEmbedding.validate(chunk.vector)
            guard chunk.page.map({ $0 > 0 }) != false, chunk.seconds.map({ $0.isFinite && $0 >= 0 && $0 < Double(Int.max) }) != false else { throw LibraryError.message("索引定位无效。") }
        }
        try db.transaction {
            try db.execute("DELETE FROM semantic_assets WHERE asset = ?", [asset.id])
            try db.execute("INSERT INTO semantic_assets(asset, fingerprint, version) VALUES (?,?,?)", [asset.id, asset.semanticFingerprint, version])
            for (ordinal, var chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                let vector = chunk.vector.withUnsafeBytes { Data($0) }; chunk.vector = []
                try db.execute("INSERT INTO semantic_chunks(asset, ordinal, data, vector) VALUES (?,?,?,?)", [asset.id, String(ordinal), String(decoding: try encoder.encode(chunk), as: UTF8.self)], blob: vector)
            }
        }
    }
    public func clearSemanticIndex() throws { try db.execute("DELETE FROM semantic_assets") }
    public func semanticChunks(for assetID: String) throws -> [SemanticChunk] {
        guard try asset(id: assetID) != nil else { return [] }
        var result: [SemanticChunk] = []
        try db.forEachBlob("SELECT semantic_chunks.data, vector FROM semantic_chunks JOIN semantic_assets ON semantic_assets.asset = semantic_chunks.asset WHERE semantic_chunks.asset = ? AND version = ? ORDER BY ordinal", [assetID, LocalEmbedding.indexVersion]) { row, data in
            var chunk = try decoder.decode(SemanticChunk.self, from: Data((row["data"] ?? "").utf8))
            guard data.count == LocalEmbedding.dimension * MemoryLayout<Float>.size else { throw LibraryError.message("索引维度损坏。") }
            chunk.vector = [Float](repeating: 0, count: LocalEmbedding.dimension)
            _ = chunk.vector.withUnsafeMutableBytes { data.copyBytes(to: $0) }
            try LocalEmbedding.validate(chunk.vector); result.append(chunk)
        }
        return result
    }
    public func semanticSearch(vector: [Float], scope: LibraryScope = .all, filter: AssetFilter = .init(), includeSubfolders: Bool = false, limit: Int = 500, version: String = LocalEmbedding.indexVersion, folderVector: [Float]? = nil) throws -> [SemanticHit] {
        try LocalEmbedding.validate(vector)
        var eligible = filter; eligible.query = ""
        let smart = try db.rows("SELECT data FROM smart_folders").map { try decoder.decode(SmartFolder.self, from: Data(($0["data"] ?? "").utf8)) }
        let semanticFolder: SmartFolder?
        if case .smart(let id) = scope { semanticFolder = smart.first { $0.id == id && $0.isSemantic } } else { semanticFolder = nil }
        if semanticFolder != nil {
            guard let folderVector else { throw LibraryError.message("语义智能文件夹需要已启用的本地 AI 模型。") }
            try LocalEmbedding.validate(folderVector)
        }
        let folders = try allFolders()
        let (clause, values) = whereClause(scope: scope, filter: eligible, folders: folders, smart: smart, includeSubfolders: includeSubfolders, semanticContext: true)
        let literalClause = whereClause(scope: scope, filter: filter, folders: folders, smart: smart, includeSubfolders: includeSubfolders, semanticContext: true)
        let literalIDs = filter.query.trimmed.isEmpty ? Set<String>() : Set(try db.rows("SELECT id FROM assets WHERE \(literalClause.0)", literalClause.1).compactMap { $0["id"] })
        var hits: [String: SemanticHit] = [:]
        var membership: [String: Float] = [:]
        // shortcut: exact vector scanning is linear; add an approximate index when measured library sizes need it.
        try db.forEachBlob("SELECT semantic_chunks.asset AS asset, semantic_chunks.data, vector FROM semantic_chunks JOIN semantic_assets ON semantic_assets.asset = semantic_chunks.asset WHERE version = ? AND semantic_chunks.asset IN (SELECT id FROM assets WHERE \(clause)) ORDER BY semantic_chunks.asset, ordinal", [version] + values) { row, data in
            try Task.checkCancellation()
            guard data.count == LocalEmbedding.dimension * MemoryLayout<Float>.size, let id = row["asset"] else { throw LibraryError.message("索引损坏，请重新建立本地 AI 索引。") }
            var candidate = [Float](repeating: 0, count: LocalEmbedding.dimension)
            _ = candidate.withUnsafeMutableBytes { data.copyBytes(to: $0) }
            try LocalEmbedding.validate(candidate)
            var score: Float = 0
            vDSP_dotpr(vector, 1, candidate, 1, &score, vDSP_Length(vector.count))
            if semanticFolder != nil, let folderVector {
                var similarity: Float = 0
                vDSP_dotpr(folderVector, 1, candidate, 1, &similarity, vDSP_Length(folderVector.count))
                membership[id] = max(membership[id] ?? -1, similarity)
            }
            if hits[id].map({ $0.score >= score }) == true { return }
            let chunk = try decoder.decode(SemanticChunk.self, from: Data((row["data"] ?? "").utf8))
            guard chunk.page.map({ $0 > 0 }) != false, chunk.seconds.map({ $0.isFinite && $0 >= 0 && $0 < Double(Int.max) }) != false else { throw LibraryError.message("索引定位损坏，请重新建立索引。") }
            hits[id] = SemanticHit(assetID: id, score: score, text: chunk.text, page: chunk.page, seconds: chunk.seconds, literal: literalIDs.contains(id))
        }
        if let semanticFolder { hits = hits.filter { (membership[$0.key] ?? -1) >= Float(semanticFolder.minimumSimilarity ?? 0.6) } }
        else { for id in literalIDs where hits[id] == nil { hits[id] = SemanticHit(assetID: id, score: 0, text: "", page: nil, seconds: nil, literal: true, indexed: false) } }
        return Array(hits.values.sorted {
            if $0.literal != $1.literal { return $0.literal }
            return $0.score == $1.score ? $0.assetID < $1.assetID : $0.score > $1.score
        }.prefix(max(1, min(limit, 100_000))))
    }
}
