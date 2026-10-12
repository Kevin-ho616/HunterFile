import Foundation
import Testing
import HunterFileCore
@testable import HunterFile

@Suite(.serialized) struct SemanticStoreTests {
    @MainActor @Test func semanticSmartFolderNeverFallsBackAndMetadataUndoRedo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("semantic-smart-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard.object(forKey: "semanticEnabled")
        let store = AppStore(openInitialLibrary: false)
        defer { store.refreshTask?.cancel(); UserDefaults.standard.set(defaults, forKey: "semanticEnabled"); try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository(url: root.appendingPathComponent("Test.openeagle"), create: true)
        let file = root.appendingPathComponent("原名.txt"); try Data("内容".utf8).write(to: file)
        let asset = try await repository.importFile(file).asset
        var vector = [Float](repeating: 0, count: 768); vector[0] = 1
        try await repository.saveSemanticChunks([SemanticChunk(vector: vector, page: 2)], for: asset)
        var folder = SmartFolder(name: "语义", filters: [.init()]); folder.semanticQuery = "海洋"; folder.minimumSimilarity = 0.8
        try await repository.saveSmartFolder(folder)
        store.repository = repository; store.localModelPath = ""; store.scope = .smart(folder.id); store.semanticEnabled = false
        store.refreshTask?.cancel(); await store.refresh()
        #expect(store.assets.isEmpty && store.semanticMessage.contains("启用本地 AI"))
        store.semanticEnabled = true; store.refreshTask?.cancel(); await store.refresh()
        #expect(store.assets.isEmpty && store.semanticMessage.contains("暂不可用"))
        store.semanticFolderCache = ("海洋", vector); await store.refresh()
        #expect(store.assets.map(\.id) == [asset.id] && store.semanticHits[asset.id]?.page == 2)
        var suggestion = AISuggestion(id: asset.id, name: "建议名称", tags: [], note: "新摘要")
        suggestion.fingerprint = asset.generationFingerprint
        var skipped = suggestion; skipped.id = "unselected"; skipped.selected = false
        try await store.applyLocalMetadata([suggestion, skipped])
        let changed = try #require(try await repository.asset(id: asset.id))
        #expect(changed.name == asset.name && changed.aiSummary == "新摘要")
        #expect(store.undoStack.count == 1)
        store.undo()
        for _ in 0..<100 where store.redoStack.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(try await repository.asset(id: asset.id)?.aiSummary == nil)
        store.redo()
        for _ in 0..<100 where store.undoStack.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(try await repository.asset(id: asset.id)?.aiSummary == "新摘要")
        suggestion.selected = false; suggestion.tags = ["未审核的分类"]
        store.applyLocalOrganization([suggestion])
        #expect(try await repository.asset(id: asset.id)?.tags.isEmpty == true)
        #expect(store.undoStack.count == 1)
        do { _ = try await store.localGeneration(); Issue.record("No model must produce a useful setup error") }
        catch { #expect(error.localizedDescription.contains("生成模型")) }
    }
    @MainActor @Test func semanticRefreshUsesFiltersAndOrganizationUndoRedo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("semantic-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard.object(forKey: "semanticEnabled")
        let store = AppStore(openInitialLibrary: false)
        defer {
            store.refreshTask?.cancel(); store.semanticIndexTask?.cancel()
            UserDefaults.standard.set(defaults, forKey: "semanticEnabled")
            try? FileManager.default.removeItem(at: root)
        }
        let repository = try LibraryRepository(url: root.appendingPathComponent("Test.openeagle"), create: true)
        let file = root.appendingPathComponent("人工名称.txt"); try Data("内容".utf8).write(to: file)
        var asset = try await repository.importFile(file).asset
        asset.note = "人工备注"; try await repository.save([asset])
        var vector = [Float](repeating: 0, count: 768); vector[0] = 1
        try await repository.saveSemanticChunks([SemanticChunk(vector: vector, page: 2)], for: asset)
        var folder = LibraryFolder(name: "归类"); try await repository.saveFolder(folder)
        store.repository = repository; store.localModelPath = ""; store.semanticEnabled = true
        store.filter.query = "自然语言描述"; store.filter.kind = .document
        store.semanticQueryCache = (store.filter.query, vector)
        store.refreshTask?.cancel(); await store.refresh()
        #expect(store.assets.map(\.id) == [asset.id] && store.semanticHits[asset.id]?.page == 2)
        store.filter.kind = .image; await store.refresh()
        #expect(store.assets.isEmpty)
        store.filter = .init(); await store.refresh()
        store.applyLocalOrganization([AISuggestion(id: asset.id, name: "不能覆盖名称", tags: ["推荐"], note: "不能覆盖备注", folderIDs: [folder.id])])
        for _ in 0..<100 where store.undoStack.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.undoStack.count == 1)
        var current = try #require(try await repository.asset(id: asset.id))
        #expect(current.name == "人工名称" && current.note == "人工备注" && current.tags == ["推荐"] && current.folderIDs == [folder.id])
        store.undo()
        for _ in 0..<100 where store.redoStack.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        current = try #require(try await repository.asset(id: asset.id))
        #expect(current.tags.isEmpty && current.folderIDs.isEmpty)
        store.redo()
        for _ in 0..<100 where store.undoStack.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(try await repository.asset(id: asset.id)?.tags == ["推荐"])
        store.semanticIndexErrors[asset.id] = "人工名称：索引失败"
        folder.password = try PasswordDigest.create("test-secret")
        try await repository.saveFolder(folder); try await repository.lockFolder(id: folder.id)
        await store.refresh()
        #expect(store.semanticIndexErrors.isEmpty && store.assets.isEmpty)
    }
    @MainActor @Test func missingModelFallsBackToKeywords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("semantic-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard.object(forKey: "semanticEnabled")
        let store = AppStore(openInitialLibrary: false)
        defer {
            store.refreshTask?.cancel()
            UserDefaults.standard.set(defaults, forKey: "semanticEnabled")
            try? FileManager.default.removeItem(at: root)
        }
        let repository = try LibraryRepository(url: root.appendingPathComponent("Test.openeagle"), create: true)
        let file = root.appendingPathComponent("关键词.txt"); try Data("正文".utf8).write(to: file)
        let asset = try await repository.importFile(file).asset
        store.repository = repository; store.localModelPath = ""; store.semanticEnabled = true
        store.filter.query = "关键词"; store.refreshTask?.cancel(); await store.refresh()
        #expect(store.assets.map(\.id) == [asset.id])
        #expect(store.semanticMessage.contains("关键词搜索"))
        #expect(store.semanticIndexTask == nil && store.error == nil)
    }
}
