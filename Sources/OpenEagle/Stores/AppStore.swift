import SwiftUI
import AppKit
import Observation
import OpenEagleCore

@MainActor @Observable
final class AppStore {
    var repository: LibraryRepository?
    var assets: [Asset] = []
    var total = 0
    var folders: [LibraryFolder] = []
    var smartFolders: [SmartFolder] = []
    var tags: [String: Int] = [:]
    var counts: [String: Int] = [:]
    var folderCounts: [String: Int] = [:]
    var totalBytes: Int64 = 0
    var selection: Set<String> = [] {
        didSet { folderDropTargetID = nil; if selection.isEmpty { showPreview = false } }
    }
    var folderDropTargetID: String?
    var includeSubfolders = false {
        didSet {
            UserDefaults.standard.set(includeSubfolders, forKey: "includeSubfolders")
            selection = []; similarityIDs = nil; limit = 500
            scheduleRefresh()
        }
    }
    var scope: LibraryScope = .all
    var filter = AssetFilter()
    var sort: AssetSortOrder = .newest
    var limit = 500
    var layout = "grid"
    static let thumbnailSizeRange = 120.0...340.0
    var thumbnailSize: Double = 190
    var showInspector = true
    var showFilters = false
    var showPreview = false
    var showTagManager = false
    var showQuickSwitch = false
    var sheet: AppSheet?
    var error: String?
    var notice = ""
    var isBusy = false
    var metadataDrafts: [String: AssetMetadataDraft] = [:]
    var hasUnsavedChanges: Bool { !metadataDrafts.isEmpty }
    var cancelRequested = false
    var progress: Double = 0
    var progressTitle = ""
    var activityErrors: [String] = []
    var similarityIDs: [String]?
    var lockedFolder: LibraryFolder?
    var refreshID = UUID()
    var undoStack: [[Asset]] = []
    var redoStack: [[Asset]] = []
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var workTask: Task<Void, Never>?
    @ObservationIgnored var windows: [NSWindow] = []
    @ObservationIgnored var watcherTask: Task<Void, Never>?
    @ObservationIgnored var apiServer: LocalAPI?
    @ObservationIgnored var initialLibraryTask: Task<Void, Never>?

    var libraryName: String { repository?.root.deletingPathExtension().lastPathComponent ?? "OpenEagle" }
    var selectedAssets: [Asset] { assets.filter { selection.contains($0.id) } }
    var selectedAsset: Asset? { selectedAssets.first }
    var destinationFolderIDs: [String] { if case .folder(let id) = scope { return [id] }; return [] }
    var childFolders: [LibraryFolder] {
        guard case .folder(let id) = scope else { return [] }
        return folders.filter { $0.parentID == id }
    }
    var folderCountHelp: String { includeSubfolders ? "包含子文件夹的素材总数，去重且不随搜索筛选变化" : "直属素材总数，不随搜索筛选变化" }
    var title: String {
        switch scope {
        case .all: return "全部素材"
        case .uncategorized: return "未分类"
        case .untagged: return "未标签"
        case .favorites: return "我的收藏"
        case .recent: return "最近浏览"
        case .trash: return "回收站"
        case .duplicates: return "重复文件"
        case .random: return "随机灵感"
        case .folder(let id): return folders.first { $0.id == id }?.name ?? "文件夹"
        case .tag(let name): return name
        case .smart(let id): return smartFolders.first { $0.id == id }?.name ?? "智能文件夹"
        case .kind(let kind): return kind.title
        }
    }

    init(openInitialLibrary: Bool = true) {
        includeSubfolders = UserDefaults.standard.bool(forKey: "includeSubfolders")
        layout = UserDefaults.standard.string(forKey: "layout") ?? "grid"
        thumbnailSize = UserDefaults.standard.object(forKey: "thumbnailSize") as? Double ?? 190
        if openInitialLibrary { initialLibraryTask = Task { await self.openInitialLibrary() } }
    }
    func openInitialLibrary() async {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--library"), arguments.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: arguments[index + 1])
            await openLibrary(url, create: arguments.contains("--create-library") && !FileManager.default.fileExists(atPath: url.path))
            return
        }
        if let path = UserDefaults.standard.string(forKey: "libraryPath") {
            await openLibrary(URL(fileURLWithPath: path), create: false)
        } else {
            let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            let url = base.appendingPathComponent("OpenEagle/我的资源库.openeagle")
            await openLibrary(url, create: !FileManager.default.fileExists(atPath: url.path))
        }
    }
    func openLibrary(_ url: URL, create: Bool) async {
        guard !isBusy else { error = "请等待当前任务完成或取消任务后再切换资源库。"; return }
        guard !hasUnsavedChanges else { error = "请先保存右侧属性中的修改，再切换资源库。"; return }
        if repository?.root == url.standardizedFileURL.resolvingSymlinksInPath() { return }
        do {
            let next = try LibraryRepository(url: url, create: create)
            let recovered = try await next.recoverInterruptedImports()
            refreshTask?.cancel(); watcherTask?.cancel()
            repository = next
            if recovered > 0 { notice = "已恢复 \(recovered) 个中断导入的素材。" }
            selection = []; scope = .all; filter = .init(); similarityIDs = nil; limit = 500
            undoStack = []; redoStack = []
            UserDefaults.standard.set(url.path, forKey: "libraryPath")
            var recent = UserDefaults.standard.stringArray(forKey: "recentLibraries") ?? []
            recent.removeAll { $0 == url.path }; recent.insert(url.path, at: 0)
            UserDefaults.standard.set(Array(recent.prefix(10)), forKey: "recentLibraries")
            await refresh()
            startWatcher()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard let repository else { return }
        let currentScope = scope, currentFilter = filter, currentIncludeSubfolders = includeSubfolders
        do {
            let snapshot = try await repository.snapshot(scope: currentScope, filter: currentFilter, sort: sort, limit: limit, includeSubfolders: currentIncludeSubfolders)
            guard !Task.isCancelled, self.repository === repository, currentScope == scope, currentFilter == filter, currentIncludeSubfolders == includeSubfolders else { return }
            if let similarityIDs {
                let found = try await repository.assets(ids: similarityIDs)
                assets = found; total = found.count
            } else { assets = snapshot.assets; total = snapshot.total }
            folders = snapshot.folders; smartFolders = snapshot.smartFolders
            if case .folder(let id) = currentScope { lockedFolder = try await repository.lockedAncestor(of: id) } else { lockedFolder = nil }
            tags = snapshot.tags; counts = snapshot.counts; folderCounts = snapshot.folderCounts; totalBytes = snapshot.totalBytes
            selection.formIntersection(Set(assets.map(\.id)))
            refreshID = UUID()
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { try? await Task.sleep(for: .milliseconds(150)); guard !Task.isCancelled else { return }; await refresh() }
    }
    func navigate(_ scope: LibraryScope) {
        folderDropTargetID = nil
        self.scope = scope; selection = []; similarityIDs = nil; lockedFolder = nil; filter = .init(); limit = 500
        scheduleRefresh()
    }
    func edit(ids: Set<String>? = nil, _ mutation: @escaping @Sendable (inout Asset) -> Void) {
        guard let repository else { return }
        let ids = Array(ids ?? selection)
        Task {
            do {
                let previous = try await repository.modify(ids: ids, mutation)
                undoStack.append(previous); if undoStack.count > 30 { undoStack.removeFirst() }; redoStack = []
                await refresh()
            } catch { self.error = error.localizedDescription }
        }
    }
    func undo() {
        guard let repository, let previous = undoStack.popLast() else { return }
        Task { do {
            let current = try await repository.assets(ids: previous.map(\.id))
            try await repository.save(previous); redoStack.append(current); await refresh()
        } catch { undoStack.append(previous); self.error = error.localizedDescription } }
    }
    func redo() {
        guard let repository, let next = redoStack.popLast() else { return }
        Task { do {
            let current = try await repository.assets(ids: next.map(\.id))
            try await repository.save(next); undoStack.append(current); await refresh()
        } catch { redoStack.append(next); self.error = error.localizedDescription } }
    }
    func addToFolder(_ id: String, ids: Set<String>? = nil) {
        let autoTags = folders.first { $0.id == id }?.autoTags ?? []
        edit(ids: ids) { asset in asset.folderIDs = Array(Set(asset.folderIDs + [id])); asset.tags = Array(Set(asset.tags + autoTags)).sorted() }
    }
    func moveAssets(ids: Set<String>, fromFolder sourceID: String, toFolder targetID: String, includeSubfolders: Bool) async {
        guard let repository else { return }
        do {
            let previous = try await repository.moveAssets(ids: Array(ids), fromFolder: sourceID, toFolder: targetID, includeSubfolders: includeSubfolders)
            guard self.repository === repository, !previous.isEmpty else { return }
            undoStack.append(previous); if undoStack.count > 30 { undoStack.removeFirst() }; redoStack = []
            await refresh()
        } catch { if self.repository === repository { self.error = error.localizedDescription } }
    }
    func trashSelection() { edit { $0.trashedAt = Date() } }
    func restoreSelection() { edit { $0.trashedAt = nil } }
    func saveFolder(_ folder: LibraryFolder) {
        Task { do { try await repository?.saveFolder(folder); await refresh() } catch { self.error = error.localizedDescription } }
    }
    func newSiblingFolder(of folder: LibraryFolder? = nil) {
        let sibling = folder ?? folders.first { scope == .folder($0.id) }
        sheet = .folder(LibraryFolder(name: "", parentID: sibling?.parentID))
    }
    func moveFolder(_ id: String, toParent parentID: String?, before siblingID: String? = nil) {
        guard let repository else { return }
        Task {
            do {
                try await repository.moveFolder(id: id, toParent: parentID, before: siblingID)
                if self.repository === repository { await refresh() }
            } catch { self.error = error.localizedDescription }
        }
    }
    func preview(_ asset: Asset? = nil) {
        if let asset { selection = [asset.id] }
        guard selectedAsset != nil else { return }
        showPreview = true
        edit { $0.openedAt = Date() }
    }
    func select(_ asset: Asset, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(asset.id) { selection.remove(asset.id) } else { selection.insert(asset.id) }
        } else if modifiers.contains(.shift), let anchor = selectedAssets.first, let a = assets.firstIndex(of: anchor), let b = assets.firstIndex(of: asset) {
            selection.formUnion(assets[min(a, b)...max(a, b)].map(\.id))
        } else { selection = [asset.id] }
    }
    func nextAsset(_ delta: Int) {
        guard !assets.isEmpty else { return }
        let current = selectedAsset.flatMap { assets.firstIndex(of: $0) } ?? 0
        selection = [assets[min(max(current + delta, 0), assets.count - 1)].id]
    }
    func runJob(_ title: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { error = "另一个任务仍在进行中。"; return }
        isBusy = true; cancelRequested = false; progress = 0; progressTitle = title; activityErrors = []
        workTask = Task {
            defer { isBusy = false; workTask = nil; scheduleRefresh() }
            do { try await operation() }
            catch is CancellationError { notice = "任务已取消，已完成的素材已安全保存。" }
            catch { self.error = error.localizedDescription }
        }
    }
    func cancelJob() {
        cancelRequested = true
        if let workTask { workTask.cancel() }
        else { watcherTask?.cancel() }
    }
}

enum AppSheet: Identifiable {
    case folder(LibraryFolder), unlock(LibraryFolder), smart(SmartFolder?), bookmark, batchRename, export, watch, activity, ai
    var id: String {
        switch self {
        case .folder(let folder): return "folder-\(folder.id)"
        case .unlock(let folder): return "unlock-\(folder.id)"
        case .smart: return "smart"
        case .bookmark: return "bookmark"
        case .batchRename: return "rename"
        case .export: return "export"
        case .watch: return "watch"
        case .activity: return "activity"
        case .ai: return "ai"
        }
    }
}
