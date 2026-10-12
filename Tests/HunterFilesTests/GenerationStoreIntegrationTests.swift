import Foundation
import Testing
import HunterFilesCore
@testable import HunterFiles

@Suite(.serialized) struct GenerationStoreIntegrationTests {
    @MainActor @Test(.enabled(if: (ProcessInfo.processInfo.environment["HUNTERFILES_TEST_GENERATION_MODEL"] ?? ProcessInfo.processInfo.environment["HUNTERFILE_TEST_GENERATION_MODEL"]) != nil && ProcessInfo.processInfo.environment["OPENEAGLE_TEST_MODEL"] != nil))
    func actualMixedLibraryMetadataSemanticFolderAndGroundedAnswers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hunter-generation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalDefault = UserDefaults.standard.object(forKey: "semanticEnabled")
        let store = AppStore(openInitialLibrary: false)
        defer { store.refreshTask?.cancel(); store.semanticIndexTask?.cancel(); store.releaseGenerationModel(); UserDefaults.standard.set(originalDefault, forKey: "semanticEnabled"); try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository(url: root.appendingPathComponent("Mixed.openeagle"), create: true)
        let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("test-output/ai-fixtures")
        var originals: [Asset] = []
        let embedding = try LocalEmbedding(modelURL: URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OPENEAGLE_TEST_MODEL"])))
        for filename in ["image-02.png", "document-02.pdf", "video-scenes.mov"] {
            var asset = try await repository.importFile(fixtures.appendingPathComponent(filename)).asset
            asset.note = "这是人工备注，必须保留。"; try await repository.save([asset])
            let chunks = try await embedding.chunks(at: repository.checkedURL(asset.relativePath), kind: asset.kind, title: asset.name, metadata: asset.searchable)
            try await repository.saveSemanticChunks(chunks, for: asset); originals.append(asset)
        }
        store.repository = repository; store.embeddingEngine = embedding; store.semanticEnabled = true; store.localModelPath = ""
        store.generationModelPath = try #require((ProcessInfo.processInfo.environment["HUNTERFILES_TEST_GENERATION_MODEL"] ?? ProcessInfo.processInfo.environment["HUNTERFILE_TEST_GENERATION_MODEL"]))
        store.refreshTask?.cancel(); await store.refresh()
        var imageFilter = AssetFilter(); imageFilter.kind = .image
        var smart = SmartFolder(name: "海洋主题", filters: [imageFilter]); smart.semanticQuery = "海洋生物、珊瑚与水下摄影"; smart.minimumSimilarity = 0.6
        try await repository.saveSmartFolder(smart)
        store.scope = .smart(smart.id); await store.refresh()
        #expect(store.assets.map(\.id) == [originals[0].id])
        store.scope = .all; await store.refresh()
        let suggestions = try await store.localMetadataSuggestions(originals, in: repository, instruction: "简短中文名称与客观摘要。")
        #expect(suggestions.count == 3 && suggestions.allSatisfy { !$0.name.isEmpty && !$0.note.isEmpty && !$0.applyName })
        #expect(suggestions[0].note.contains("海") || suggestions[0].note.contains("鱼"))
        #expect(suggestions[1].note.contains("珊瑚") || suggestions[1].note.contains("海洋"))
        var reviewed = suggestions
        reviewed[1].selected = false; reviewed[2].selected = false
        try await store.applyLocalMetadata(reviewed)
        let changed = try #require(try await repository.asset(id: originals[0].id))
        #expect(changed.name == originals[0].name && changed.note == originals[0].note && changed.aiSummary == suggestions[0].note)
        #expect(try await repository.asset(id: originals[1].id)?.aiSummary == nil)
        #expect(try await repository.asset(id: originals[2].id)?.aiSummary == nil)
        store.undo()
        for _ in 0..<100 where store.redoStack.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(try await repository.asset(id: originals[0].id)?.aiSummary == nil)
        store.redo()
        for _ in 0..<100 where store.undoStack.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(try await repository.asset(id: originals[0].id)?.aiSummary == suggestions[0].note)
        store.scope = .kind(.document); store.filter = .init(); await store.refresh()
        let documentAnswer = try await store.askLibrary("保护珊瑚和鱼类的资料提到了什么海洋生物？")
        #expect(documentAnswer.text.contains("珊瑚") || documentAnswer.text.contains("鱼"))
        #expect(documentAnswer.sources.count == 1 && documentAnswer.sources.first?.hit.page == 2 && documentAnswer.sources.first?.asset.id == originals[1].id)
        store.scope = .kind(.video); await store.refresh()
        let videoAnswer = try await store.askLibrary("视频中出现猫的画面是什么？")
        #expect(videoAnswer.text.contains("猫"))
        #expect(videoAnswer.sources.first?.hit.seconds.map { (48..<54).contains($0) } == true)
        store.filter.ext = "nonexistent"
        let missing = try await store.askLibrary("这里有没有素材？")
        #expect(missing.sources.isEmpty && missing.text.contains("没有足够"))
        let report: [String: Any] = ["metadata": suggestions.map { ["name": $0.name, "summary": $0.note] }, "documentAnswer": documentAnswer.text, "documentPage": documentAnswer.sources.first?.hit.page ?? -1, "videoAnswer": videoAnswer.text, "videoSeconds": videoAnswer.sources.first?.hit.seconds ?? -1, "reviewUndoRedo": true, "semanticFolder": true]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: fixtures.deletingLastPathComponent().appendingPathComponent("hunterfiles-generation-integration.json"), options: .atomic)
    }
}
