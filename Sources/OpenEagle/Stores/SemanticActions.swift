import AppKit
import UniformTypeIdentifiers
import Accelerate
import OpenEagleCore

extension AppStore {
    func localEmbedding() async throws -> LocalEmbedding {
        if let embeddingEngine { return embeddingEngine }
        guard !localModelPath.isEmpty else { throw LibraryError.message("请在设置 → AI 中选择本地模型。") }
        let path = localModelPath
        if embeddingLoadTask == nil {
            embeddingLoadID = UUID()
            embeddingLoadTask = Task.detached {
                try LocalEmbedding(modelURL: URL(fileURLWithPath: path))
            }
        }
        let loadID = embeddingLoadID
        let engine: LocalEmbedding
        do { engine = try await embeddingLoadTask!.value }
        catch { if embeddingLoadID == loadID { embeddingLoadTask = nil }; throw error }
        try Task.checkCancellation()
        guard localModelPath == path, embeddingLoadID == loadID else { throw CancellationError() }
        embeddingEngine = engine
        return engine
    }
    func chooseLocalModel() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "litertlm") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        configureLocalModel(url)
    }
    func configureLocalModel(_ url: URL) {
        resetSemanticIndex()
        embeddingLoadTask?.cancel(); embeddingLoadTask = nil; embeddingEngine = nil; semanticQueryCache = nil
        embeddingLoadID = UUID()
        localModelPath = url.path; UserDefaults.standard.set(url.path, forKey: "localModelPath")
        semanticEnabled = true; startSemanticIndex(resume: true)
    }
    func resetSemanticIndex() {
        semanticIndexTask?.cancel(); semanticImageTask?.cancel()
        semanticIndexID = UUID(); semanticIndexTask = nil; semanticIndexing = false
        semanticFailures = [:]; semanticIndexErrors = [:]; semanticIndexed = 0; semanticProgress = 0
        semanticImageVector = nil; semanticHits = [:]; semanticMessage = ""; semanticIndexTitle = ""
    }
    func pauseSemanticIndex() {
        semanticPaused = true; semanticIndexTask?.cancel()
        semanticIndexTitle = "已暂停，已完成的索引保留"
    }
    func rebuildSemanticIndex() {
        guard let repository else { return }
        resetSemanticIndex()
        Task {
            do { try await repository.clearSemanticIndex(); if self.repository === repository { startSemanticIndex(resume: true) } }
            catch { self.error = error.localizedDescription }
        }
    }
    func startSemanticIndex(resume: Bool = false) {
        if resume { semanticPaused = false; semanticFailures = [:]; semanticIndexErrors = [:] }
        guard semanticEnabled, !localModelPath.isEmpty, !semanticPaused, semanticIndexTask == nil, let repository else { return }
        let token = UUID(); semanticIndexID = token
        semanticIndexTask = Task {
            defer {
                if semanticIndexID == token {
                    semanticIndexing = false; semanticIndexTask = nil
                    if Task.isCancelled, semanticEnabled, !semanticPaused { scheduleRefresh() }
                }
            }
            do {
                let indexed = try await repository.semanticIndexedCount()
                let pending = try await repository.pendingSemanticAssets().filter { semanticFailures[$0.id] != $0.semanticFingerprint }
                try Task.checkCancellation()
                guard self.repository === repository, semanticIndexID == token else { return }
                semanticIndexed = indexed
                guard !pending.isEmpty else { return }
                semanticIndexing = true; semanticIndexTitle = "加载本地模型…"
                let engine = try await localEmbedding()
                for (index, asset) in pending.enumerated() {
                    try Task.checkCancellation()
                    guard self.repository === repository, semanticIndexID == token else { return }
                    semanticIndexTitle = "索引 \(index + 1)/\(pending.count) 项"
                    semanticProgress = Double(index) / Double(pending.count)
                    do {
                        let thumbnail = try? repository.checkedURL("assets/\(asset.id)/thumbnail.png")
                        let chunks = try await engine.chunks(at: repository.checkedURL(asset.relativePath), kind: asset.kind, title: asset.name, metadata: asset.searchable, thumbnail: thumbnail)
                        try Task.checkCancellation()
                        try await repository.saveSemanticChunks(chunks, for: asset)
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        guard semanticIndexID == token else { return }
                        semanticFailures[asset.id] = asset.semanticFingerprint
                        if let current = try await repository.asset(id: asset.id), current.trashedAt == nil {
                            semanticIndexErrors[asset.id] = "\(asset.name)：\(error.localizedDescription)"
                        }
                    }
                }
                guard semanticIndexID == token else { return }
                semanticIndexed = try await repository.semanticIndexedCount(); semanticProgress = 1
                semanticIndexTitle = "已索引 \(semanticIndexed) 项" + (semanticIndexErrors.isEmpty ? "" : "，\(semanticIndexErrors.count) 项失败")
                scheduleRefresh()
            } catch is CancellationError { }
            catch { if semanticIndexID == token { semanticIndexTitle = error.localizedDescription; semanticPaused = true } }
        }
    }
    func chooseSemanticImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        searchSemanticImage(url, name: url.lastPathComponent)
    }
    func searchSemanticImage(_ url: URL, name: String) {
        semanticImageTask?.cancel(); filter.query = ""; similarityIDs = nil; semanticImageVector = nil
        let currentScope = scope, repository = repository
        semanticImageTask = Task {
            do {
                let engine = try await localEmbedding()
                let chunks = try await engine.chunks(at: url, kind: .image, title: name)
                try Task.checkCancellation()
                guard self.repository === repository, scope == currentScope, filter.query.isEmpty else { return }
                semanticImageVector = chunks.first(where: { $0.text.isEmpty })?.vector; semanticImageName = name
                await refresh()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func localOrganizationSuggestions(_ assets: [Asset], in repository: LibraryRepository) async throws -> [AISuggestion] {
        let engine = try await localEmbedding()
        let categories = try await repository.organizationCategories(excluding: Set(assets.map(\.id)))
        guard !categories.isEmpty else { throw LibraryError.message("请先建立标签或文件夹；本地模型会从现有分类中提出候选。") }
        var prototypes: [(OrganizationCategory, [[Float]])] = []
        for category in categories {
            try Task.checkCancellation()
            let vector = try await engine.query(category.description)
            prototypes.append((category, [vector] + category.examples))
        }
        var result: [AISuggestion] = []
        for original in assets {
            try Task.checkCancellation()
            guard let asset = try await repository.asset(id: original.id), asset.trashedAt == nil else { continue }
            var chunks = try await repository.semanticChunks(for: asset.id)
            if chunks.isEmpty {
                let thumbnail = try? repository.checkedURL("assets/\(asset.id)/thumbnail.png")
                chunks = try await engine.chunks(at: repository.checkedURL(asset.relativePath), kind: asset.kind, title: asset.name, metadata: asset.searchable, thumbnail: thumbnail)
                try await repository.saveSemanticChunks(chunks, for: asset)
            }
            var ranked: [(OrganizationCategory, Float)] = []
            for (category, vectors) in prototypes {
                var best: Float = -1
                for prototype in vectors { for chunk in chunks {
                    var score: Float = 0; vDSP_dotpr(prototype, 1, chunk.vector, 1, &score, vDSP_Length(prototype.count)); best = max(best, score)
                } }
                ranked.append((category, best))
            }
            ranked.sort { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }
            let tags = Array(ranked.filter { $0.0.folderID == nil && !asset.tags.contains($0.0.name) }.prefix(1))
            let folders = Array(ranked.filter { $0.0.folderID.map { !asset.folderIDs.contains($0) } == true }.prefix(1))
            let folderIDs = folders.compactMap { $0.0.folderID }
            var suggestion = AISuggestion(id: asset.id, name: asset.name, tags: tags.map { $0.0.name }, note: asset.note, folderIDs: folderIDs, candidateFolderIDs: folderIDs)
            suggestion.explanation = (tags + folders).map { "\($0.0.name) \(String(format: "%.2f", $0.1))" }.joined(separator: " · ")
            result.append(suggestion)
            await Task.yield()
        }
        guard self.repository === repository else { throw LibraryError.message("资源库已切换，请重新生成建议。") }
        return result
    }
    func applyLocalOrganization(_ suggestions: [AISuggestion]) {
        guard let repository else { return }
        let changes = suggestions.map { OrganizationChange(assetID: $0.id, tags: $0.tags, folderIDs: $0.folderIDs) }
        Task {
            do {
                let previous = try await repository.applyOrganization(changes)
                guard self.repository === repository else { return }
                undoStack.append(previous); if undoStack.count > 30 { undoStack.removeFirst() }; redoStack = []
                await refresh()
            } catch { self.error = error.localizedDescription }
        }
    }
}
