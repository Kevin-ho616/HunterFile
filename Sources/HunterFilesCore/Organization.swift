import Foundation

public struct OrganizationCategory: Sendable {
    public var name: String
    public var description: String
    public var folderID: String?
    public var examples: [[Float]]
}

public struct OrganizationChange: Sendable {
    public var assetID: String
    public var tags: [String]
    public var folderIDs: [String]
    public init(assetID: String, tags: [String], folderIDs: [String]) { self.assetID = assetID; self.tags = tags; self.folderIDs = folderIDs }
}

public struct GeneratedMetadataChange: Sendable {
    public var assetID: String
    public var fingerprint: String
    public var name: String?
    public var summary: String
    public init(assetID: String, fingerprint: String, name: String? = nil, summary: String) { self.assetID = assetID; self.fingerprint = fingerprint; self.name = name; self.summary = summary }
}

extension LibraryRepository {
    public func applyGeneratedMetadata(_ changes: [GeneratedMetadataChange]) throws -> [Asset] {
        guard !changes.isEmpty, Set(changes.map(\.assetID)).count == changes.count else { throw LibraryError.message("请勾选需要应用的素材。") }
        for change in changes {
            guard let current = try asset(id: change.assetID), current.trashedAt == nil, current.generationFingerprint == change.fingerprint else { throw LibraryError.message("素材已改变、删除或锁定，请重新生成建议。") }
            guard !change.summary.trimmed.isEmpty, change.summary.count <= 3000, change.name.map({ !$0.trimmed.isEmpty && $0.count <= 180 }) != false else { throw LibraryError.message("名称或摘要无效，素材未修改。") }
        }
        let map = Dictionary(uniqueKeysWithValues: changes.map { ($0.assetID, $0) })
        return try modify(ids: changes.map(\.assetID)) { asset in
            guard let change = map[asset.id] else { return }
            if let name = change.name { asset.name = name.safeFilename }
            asset.aiSummary = change.summary.trimmed
        }
    }
    public func organizationCategories(excluding ids: Set<String>) throws -> [OrganizationCategory] {
        let folders = try allFolders(), hidden = inaccessibleIDs(in: try allFolders())
        var categories: [OrganizationCategory] = []
        func examples(_ scope: LibraryScope) throws -> [[Float]] {
            var result: [[Float]] = []
            for id in try matchingIDs(scope: scope, filter: .init()).filter({ !ids.contains($0) }).prefix(3) {
                let chunks = try semanticChunks(for: id)
                guard !chunks.isEmpty else { continue }
                var mean = [Float](repeating: 0, count: LocalEmbedding.dimension)
                for chunk in chunks { for index in mean.indices { mean[index] += chunk.vector[index] } }
                let norm = sqrt(mean.reduce(Float(0)) { $0 + $1 * $1 })
                if norm > 0 { result.append(mean.map { $0 / norm }) }
            }
            return result
        }
        for tag in try snapshot(limit: 1).tags.keys.sorted() {
            categories.append(OrganizationCategory(name: tag, description: tag, folderID: nil, examples: try examples(.tag(tag))))
        }
        for folder in folders where !hidden.contains(folder.id) {
            categories.append(OrganizationCategory(name: folder.name, description: ([folder.name, folder.note] + folder.autoTags).joined(separator: " "), folderID: folder.id, examples: try examples(.folder(folder.id))))
        }
        return categories
    }
    public func applyOrganization(_ changes: [OrganizationChange]) throws -> [Asset] {
        let targets = try assets(ids: changes.map(\.assetID))
        guard targets.count == changes.count, targets.allSatisfy({ $0.trashedAt == nil }) else { throw LibraryError.message("建议中的素材已删除或锁定，请重新生成。") }
        let folders = try allFolders(), hidden = inaccessibleIDs(in: folders)
        let valid = Set(folders.filter { !hidden.contains($0.id) }.map(\.id))
        guard changes.allSatisfy({ Set($0.folderIDs).isSubset(of: valid) }), Set(changes.map(\.assetID)).count == changes.count else { throw LibraryError.message("建议中的文件夹已不存在或被锁定，请重新生成。") }
        let map = Dictionary(uniqueKeysWithValues: changes.map { ($0.assetID, $0) })
        let autoTags = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.autoTags) })
        return try modify(ids: changes.map(\.assetID)) { asset in
            guard let change = map[asset.id] else { return }
            asset.tags = Array(Set(asset.tags + change.tags.map(\.trimmed).filter { !$0.isEmpty } + change.folderIDs.flatMap { autoTags[$0] ?? [] })).sorted()
            asset.folderIDs = Array(Set(asset.folderIDs + change.folderIDs)).sorted()
        }
    }
}
