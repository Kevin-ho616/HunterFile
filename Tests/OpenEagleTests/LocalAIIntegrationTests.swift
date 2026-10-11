import Foundation
import AppKit
import PDFKit
import Testing
import OpenEagleCore
@testable import OpenEagle

struct LocalAIIntegrationTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENEAGLE_TEST_MODEL"] != nil))
    func realModelIndexPauseResumeSearchAndClassification() async throws {
        let model = try #require(ProcessInfo.processInfo.environment["OPENEAGLE_TEST_MODEL"])
        let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("test-output/ai-fixtures")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard.object(forKey: "semanticEnabled")
        let store = AppStore(openInitialLibrary: false)
        defer {
            store.refreshTask?.cancel(); store.semanticIndexTask?.cancel()
            UserDefaults.standard.set(defaults, forKey: "semanticEnabled")
            try? FileManager.default.removeItem(at: root)
        }
        let repository = try LibraryRepository(url: root.appendingPathComponent("Integration.openeagle"), create: true)
        var ocean = LibraryFolder(name: "海洋资料"); ocean.note = "海底生物、珊瑚礁、鱼类和海水生态"; ocean.autoTags = ["海洋主题"]
        var space = LibraryFolder(name: "航天资料"); space.note = "火箭、卫星、宇航员和宇宙探索"; space.autoTags = ["航天主题"]
        try await repository.saveFolder(ocean); try await repository.saveFolder(space)
        var imported: [String: Asset] = [:]
        for file in ["image-01.png", "image-02.png", "document-01.pdf", "document-02.pdf", "video-scenes.mov"] {
            let folders = file == "image-01.png" ? [space.id] : (file == "image-02.png" ? [ocean.id] : [])
            imported[file] = try await repository.importFile(fixtures.appendingPathComponent(file), folderIDs: folders).asset
        }
        let scan = PDFDocument()
        let image = try #require(NSImage(contentsOf: fixtures.appendingPathComponent("image-02.png")))
        let page = try #require(PDFPage(image: image)); scan.insert(page, at: 0)
        let scanURL = root.appendingPathComponent("scanned.pdf"); #expect(scan.write(to: scanURL))
        imported["scanned.pdf"] = try await repository.importFile(scanURL).asset
        store.repository = repository; store.localModelPath = model; store.semanticEnabled = true
        store.refreshTask?.cancel(); store.startSemanticIndex(resume: true)
        let indexing = try #require(store.semanticIndexTask)
        for _ in 0..<1000 {
            if try await repository.semanticIndexedCount() > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        store.pauseSemanticIndex(); await indexing.value
        let partial = try await repository.semanticIndexedCount()
        #expect(partial > 0 && partial < 6)
        store.startSemanticIndex(resume: true)
        await store.semanticIndexTask?.value
        store.refreshTask?.cancel()
        #expect(store.semanticIndexErrors.isEmpty)
        #expect(try await repository.semanticIndexedCount() == 6)
        #expect(try await repository.pendingSemanticAssets().isEmpty)
        let engine = try #require(store.embeddingEngine)
        let queries: [(String, AssetKind, String, Int?, Range<Double>?)] = [
            ("保护珊瑚和鱼类的资料", .document, "document-02.pdf", 2, nil),
            ("带火箭图案的宣传海报", .image, "image-01.png", nil, nil),
            ("出现猫的画面", .video, "video-scenes.mov", nil, 48..<54)
        ]
        var evidence: [[String: Any]] = []
        for (query, kind, file, page, seconds) in queries {
            var filter = AssetFilter(); filter.query = query; filter.kind = kind
            let vector = try await engine.query(query)
            let hits = try await repository.semanticSearch(vector: vector, filter: filter)
            let first = try #require(hits.first)
            #expect(first.assetID == imported[file]?.id)
            if let page { #expect(first.page == page) }
            if let seconds { #expect(first.seconds.map { seconds.contains($0) } == true) }
            evidence.append(["query": query, "file": file, "location": first.location, "score": first.score])
        }
        let scanned = try #require(imported["scanned.pdf"])
        let scanChunks = try await repository.semanticChunks(for: scanned.id)
        #expect(scanChunks.contains { $0.page == 1 && !$0.text.isEmpty })
        let document = try #require(imported["document-02.pdf"])
        let suggestions = try await store.localOrganizationSuggestions([document], in: repository)
        #expect(suggestions.first?.folderIDs == [ocean.id])
        #expect(suggestions.first?.tags == ["海洋主题"])
        store.applyLocalOrganization(suggestions)
        for _ in 0..<100 where store.undoStack.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let changed = try #require(try await repository.asset(id: document.id))
        #expect(changed.folderIDs == [ocean.id] && changed.name == document.name && changed.note == document.note)
        #expect(store.undoStack.count == 1)
        let report: [String: Any] = ["files": 6, "pauseRetained": partial, "queries": evidence, "scannedPDFOCR": true, "classificationFolder": ocean.name]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: fixtures.deletingLastPathComponent().appendingPathComponent("ai-native-integration.json"), options: .atomic)
    }
}
