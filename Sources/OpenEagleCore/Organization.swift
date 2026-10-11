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

extension LibraryRepository {
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
