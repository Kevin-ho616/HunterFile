import Foundation
import Testing
@testable import HunterFileCore

struct SemanticTests {
    @Test func semanticSmartFoldersRespectMembershipFiltersAndCompatibility() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Smart.openeagle")
        var library: LibraryRepository? = try LibraryRepository(url: url, create: true)
        var a = try await add("query海洋", at: root, to: library!)
        var b = try await add("query太空", at: root, to: library!)
        let unindexed = try await add("query未索引", at: root, to: library!)
        a.tags = ["海洋"]; a.rating = 5; b.rating = 2
        try await library!.save([a, b])
        try await library!.saveSemanticChunks([SemanticChunk(vector: vector(), page: 1), SemanticChunk(vector: vector(1), page: 2)], for: a)
        try await library!.saveSemanticChunks([SemanticChunk(vector: vector(1))], for: b)
        var tag = AssetFilter(); tag.tag = "海洋"
        var rating = AssetFilter(); rating.minRating = 4
        var smart = SmartFolder(name: "海洋描述", filters: [tag, rating], matchAll: false)
        smart.semanticQuery = "海洋生态"; smart.minimumSimilarity = 0.8
        try await library!.saveSmartFolder(smart)
        #expect(try await library!.snapshot(scope: .smart(smart.id)).assets.isEmpty)
        #expect(try await library!.matchingIDs(scope: .smart(smart.id), filter: .init()).isEmpty)
        var query = AssetFilter(); query.query = "query"
        let firstPage = try await library!.semanticResults(vector: vector(1), filter: query, limit: 1)
        #expect(firstPage.assets.count == 1 && firstPage.hits.count == 1 && firstPage.total == 3)
        let hits = try await library!.semanticSearch(vector: vector(1), scope: .smart(smart.id), filter: query, folderVector: vector())
        #expect(hits.map(\.assetID) == [a.id] && hits.first?.page == 2)
        #expect(!hits.contains { $0.assetID == b.id || $0.assetID == unindexed.id })
        smart.filters = [tag, .init()]; smart.matchAll = true
        try await library!.saveSmartFolder(smart)
        #expect(try await library!.semanticSearch(vector: vector(), scope: .smart(smart.id), folderVector: vector()).map(\.assetID) == [a.id])
        do { _ = try await library!.semanticSearch(vector: vector(), scope: .smart(smart.id)); Issue.record("Unresolved membership must fail") } catch { }
        smart.minimumSimilarity = .nan
        do { try await library!.saveSmartFolder(smart); Issue.record("Invalid threshold must fail") } catch { }
        let legacy = SmartFolder(name: "旧规则", filters: [tag])
        let decoded = try JSONDecoder().decode(SmartFolder.self, from: JSONEncoder().encode(legacy))
        #expect(!decoded.isSemantic && decoded.minimumSimilarity == nil)
        library = nil; library = try LibraryRepository(url: url)
        #expect(try await library!.snapshot().smartFolders.first?.semanticQuery == "海洋生态")
        var hidden = LibraryFolder(name: "私密"); hidden.password = try PasswordDigest.create("password")
        try await library!.saveFolder(hidden)
        let hiddenID = hidden.id
        _ = try await library!.modify(ids: [a.id]) { $0.folderIDs = [hiddenID] }
        try await library!.saveSemanticChunks([SemanticChunk(vector: vector())], for: try #require(try await library!.asset(id: a.id)))
        try await library!.lockFolder(id: hidden.id)
        #expect(try await library!.semanticSearch(vector: vector(), scope: .smart(smart.id), folderVector: vector()).isEmpty)
    }
    @Test func generatedMetadataIsReviewedAtomicAndKeepsManualData() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryRepository(url: root.appendingPathComponent("Metadata.openeagle"), create: true)
        var a = try await add("人工名称", at: root, to: library)
        var b = try await add("另一素材", at: root, to: library)
        a.note = "人工备注"; a.tags = ["原标签"]; try await library.save([a])
        try await library.saveSemanticChunks([SemanticChunk(vector: vector())], for: a)
        let first = GeneratedMetadataChange(assetID: a.id, fingerprint: a.generationFingerprint, summary: "AI 摘要")
        let stale = GeneratedMetadataChange(assetID: b.id, fingerprint: b.generationFingerprint, summary: "旧建议")
        b.note = "编辑后"; try await library.save([b])
        do { _ = try await library.applyGeneratedMetadata([first, stale]); Issue.record("Stale batch must fail atomically") } catch { }
        #expect(try await library.asset(id: a.id)?.aiSummary == nil)
        let previous = try await library.applyGeneratedMetadata([first])
        var current = try #require(try await library.asset(id: a.id))
        #expect(current.name == a.name && current.note == a.note && current.tags == a.tags && current.relativePath == a.relativePath && current.aiSummary == "AI 摘要")
        #expect(try await library.semanticIndexedCount() == 1)
        do { _ = try await library.applyGeneratedMetadata([first]); Issue.record("An already replaced summary must invalidate the suggestion") } catch { }
        _ = try await library.applyGeneratedMetadata([GeneratedMetadataChange(assetID: a.id, fingerprint: current.generationFingerprint, name: "新显示名称", summary: "新摘要")])
        current = try #require(try await library.asset(id: a.id))
        #expect(current.name == "新显示名称" && current.relativePath == a.relativePath && current.note == a.note)
        #expect(try await library.semanticIndexedCount() == 0)
        try await library.save(previous)
        let restored = try #require(try await library.asset(id: a.id))
        #expect(restored.name == a.name && restored.aiSummary == nil)
        #expect(try JSONDecoder().decode(Asset.self, from: JSONEncoder().encode(a)).aiSummary == nil)
        var secret = LibraryFolder(name: "保密"); secret.password = try PasswordDigest.create("secret")
        let secretID = secret.id
        try await library.saveFolder(secret); _ = try await library.modify(ids: [a.id]) { $0.folderIDs = [secretID] }
        let beforeLock = try #require(try await library.asset(id: a.id))
        try await library.lockFolder(id: secret.id)
        do { _ = try await library.applyGeneratedMetadata([GeneratedMetadataChange(assetID: a.id, fingerprint: beforeLock.generationFingerprint, summary: "不能覆盖")]); Issue.record("Locked asset must reject generation changes") } catch { }
        do { _ = try await library.applyOrganization([OrganizationChange(assetID: b.id, tags: ["未应用"], folderIDs: []), OrganizationChange(assetID: a.id, tags: ["保密"], folderIDs: [])]); Issue.record("A locked batch member must fail atomically") } catch { }
        #expect(try await library.asset(id: b.id)?.tags.isEmpty == true)
    }
    private func vector(_ axis: Int = 0) -> [Float] { var value = [Float](repeating: 0, count: 768); value[axis] = 1; return value }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("semantic-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func add(_ name: String, at root: URL, to library: LibraryRepository, folders: [String] = []) async throws -> Asset {
        let file = root.appendingPathComponent(name + ".txt")
        try Data(name.utf8).write(to: file)
        return try await library.importFile(file, folderIDs: folders).asset
    }
    @Test func persistenceVersioningInvalidationAndBackup() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Test.openeagle")
        var library: LibraryRepository? = try LibraryRepository(url: url, create: true)
        var asset = try await add("资料", at: root, to: library!)
        try await library!.saveSemanticChunks([SemanticChunk(vector: vector(0), text: "第一页", page: 1), SemanticChunk(vector: vector(1), text: "第二页", page: 2)], for: asset)
        #expect(try await library!.semanticSearch(vector: vector(1)).first?.page == 2)
        #expect(try await library!.pendingSemanticAssets().isEmpty)
        #expect(try await library!.semanticSearch(vector: vector(), version: "different-model").isEmpty)
        #expect(try await library!.pendingSemanticAssets(version: "different-model").count == 1)
        let backup = root.appendingPathComponent("Backup.openeagle")
        try await library!.backup(to: backup)
        library = nil; library = try LibraryRepository(url: url)
        #expect(try await library!.semanticChunks(for: asset.id).count == 2)
        let restored = try LibraryRepository(url: backup)
        #expect(try await restored.semanticSearch(vector: vector(1)).first?.page == 2)
        asset.favorite = true; asset.openedAt = Date(); try await library!.save([asset])
        #expect(try await library!.semanticIndexedCount() == 1)
        let stale = asset
        asset.note = "人工新备注"; try await library!.save([asset])
        #expect(try await library!.semanticIndexedCount() == 0)
        try await library!.saveSemanticChunks([SemanticChunk(vector: vector())], for: stale)
        #expect(try await library!.semanticIndexedCount() == 0)
        try await library!.saveSemanticChunks([SemanticChunk(vector: vector())], for: asset)
        #expect(try await library!.semanticIndexedCount() == 1)
    }
    @Test func scopesFiltersLiteralFallbackLocksAndTrash() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryRepository(url: root.appendingPathComponent("Test.openeagle"), create: true)
        let parent = LibraryFolder(name: "父级"), child = LibraryFolder(name: "子级", parentID: nil)
        var nested = child; nested.parentID = parent.id
        var secret = LibraryFolder(name: "保密")
        try await library.saveFolder(parent); try await library.saveFolder(nested); try await library.saveFolder(secret)
        var a = try await add("图片", at: root, to: library, folders: [nested.id])
        var b = try await add("猫咪100%_资料", at: root, to: library, folders: [parent.id])
        let hidden = try await add("私密", at: root, to: library, folders: [parent.id, secret.id])
        a.kind = .image; a.width = 1600; a.height = 900; a.rating = 4; a.tags = ["设计"]
        b.kind = .video; b.duration = 60
        try await library.save([a, b])
        try await library.saveSemanticChunks([SemanticChunk(vector: vector(1))], for: a)
        try await library.saveSemanticChunks([SemanticChunk(vector: vector(), seconds: 35)], for: b)
        try await library.saveSemanticChunks([SemanticChunk(vector: vector())], for: hidden)
        secret.password = try PasswordDigest.create("test-secret")
        try await library.saveFolder(secret); try await library.lockFolder(id: secret.id)
        #expect(try await library.semanticSearch(vector: vector()).count == 2)
        #expect(try await library.semanticChunks(for: hidden.id).isEmpty)
        #expect(try await library.pendingSemanticAssets().allSatisfy { $0.id != hidden.id })
        #expect(try await library.semanticSearch(vector: vector(), scope: .folder(parent.id)).map(\.assetID) == [b.id])
        #expect(try await library.semanticSearch(vector: vector(), scope: .folder(parent.id), includeSubfolders: true).count == 2)
        var filter = AssetFilter(); filter.kind = .image; filter.tag = "设计"; filter.minRating = 4; filter.minWidth = 1200; filter.shape = "landscape"
        #expect(try await library.semanticSearch(vector: vector(), filter: filter).map(\.assetID) == [a.id])
        let smart = SmartFolder(name: "设计图片", filters: [filter]); try await library.saveSmartFolder(smart)
        #expect(try await library.semanticSearch(vector: vector(), scope: .smart(smart.id)).map(\.assetID) == [a.id])
        filter = AssetFilter(); filter.query = "猫咪100%_"
        #expect(try await library.semanticSearch(vector: vector(1), filter: filter).first?.assetID == b.id)
        try await library.clearSemanticIndex()
        #expect(try await library.semanticSearch(vector: vector(), filter: filter).first?.literal == true)
        try await library.saveSemanticChunks([SemanticChunk(vector: vector(), seconds: 35)], for: b)
        try await library.setTrashed(ids: [b.id], trashed: true)
        #expect(try await library.semanticSearch(vector: vector()).isEmpty)
        #expect(try await library.semanticSearch(vector: vector(), scope: .trash).first?.location == "0:35")
        try await library.removeToSystemTrash(ids: [b.id])
        #expect(try await library.db.scalar("SELECT COUNT(*) FROM semantic_chunks") == 0)
    }
    @Test func invalidVectorsAndCancellationPreservePreviousIndex() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryRepository(url: root.appendingPathComponent("Test.openeagle"), create: true)
        let asset = try await add("有效素材", at: root, to: library)
        try await library.saveSemanticChunks([SemanticChunk(vector: vector(), page: 2)], for: asset)
        var nan = vector(); nan[1] = .nan
        for invalid in [[], Array(vector().dropLast()), [Float](repeating: 0, count: 768), nan] {
            await #expect(throws: Error.self) { try await library.saveSemanticChunks([SemanticChunk(vector: invalid)], for: asset) }
        }
        await #expect(throws: Error.self) { try await library.saveSemanticChunks([SemanticChunk(vector: vector(), seconds: -1)], for: asset) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await library.saveSemanticChunks([SemanticChunk(vector: vector(1), page: 9)], for: asset)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await library.semanticSearch(vector: vector()).first?.page == 2)
    }
    @Test func organizationAddsOnlyReviewedMetadataAndCanBeUndone() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryRepository(url: root.appendingPathComponent("Test.openeagle"), create: true)
        var folder = LibraryFolder(name: "设计"); folder.autoTags = ["自动标签"]
        try await library.saveFolder(folder)
        var asset = try await add("人工名称", at: root, to: library)
        asset.note = "人工备注"; asset.tags = ["原标签"]; try await library.save([asset])
        let sourceHash = try LibraryRepository.sha256(library.fileURL(for: asset))
        try await library.saveSemanticChunks([SemanticChunk(vector: vector())], for: asset)
        let categories = try await library.organizationCategories(excluding: [asset.id])
        #expect(categories.map(\.name).contains("原标签") && categories.map(\.name).contains("设计"))
        let previous = try await library.applyOrganization([OrganizationChange(assetID: asset.id, tags: [" 推荐 ", "原标签"], folderIDs: [folder.id])])
        let updated = try #require(try await library.asset(id: asset.id))
        #expect(updated.name == "人工名称" && updated.note == "人工备注")
        #expect(updated.tags == ["原标签", "推荐", "自动标签"].sorted() && updated.folderIDs == [folder.id])
        #expect(try LibraryRepository.sha256(library.fileURL(for: updated)) == sourceHash)
        #expect(try await library.semanticIndexedCount() == 0)
        try await library.save(previous)
        #expect(try await library.asset(id: asset.id)?.tags == ["原标签"])
        await #expect(throws: Error.self) { try await library.applyOrganization([OrganizationChange(assetID: asset.id, tags: [], folderIDs: ["missing"])]) }
        folder.password = try PasswordDigest.create("test-secret"); try await library.saveFolder(folder); try await library.lockFolder(id: folder.id)
        #expect(try await library.organizationCategories(excluding: []).allSatisfy { $0.folderID != folder.id })
        await #expect(throws: Error.self) { try await library.applyOrganization([OrganizationChange(assetID: asset.id, tags: [], folderIDs: [folder.id])]) }
    }
    @Test func longChineseTextChunksPreserveCoverage() {
        let text = String(repeating: "中文段落。", count: 1000)
        let chunks = LocalEmbedding.textSegments(text)
        #expect(chunks.count == 6 && chunks.allSatisfy { $0.count <= 1000 })
        #expect(chunks.dropLast().allSatisfy { $0.count == 1000 })
        #expect(LocalEmbedding.textSegments(" \n ").isEmpty)
        #expect(chunks.last == String(text.suffix(500)))
    }
}
