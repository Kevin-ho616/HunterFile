import SwiftUI
import OpenEagleCore

struct TagManagerView: View {
    var store: AppStore
    @State private var search = ""
    @State private var selected: String?
    @State private var replacement = ""
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("标签管理").font(.title2.bold()); Spacer(); Text("\(store.tags.count) 个标签").foregroundStyle(.secondary) }
            TextField("搜索标签", text: $search).textFieldStyle(.roundedBorder)
            List(selection: $selected) {
                ForEach(store.tags.keys.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }.sorted(), id: \.self) { tag in
                    HStack { Label(tag, systemImage: "tag"); Spacer(); Text("\(store.tags[tag] ?? 0) 个素材").font(.caption).foregroundStyle(.secondary) }.tag(tag)
                }
            }.frame(height: 300)
            if let selected {
                Text("将“\(selected)”重命名或合并到已有标签：").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("新标签名称", text: $replacement).textFieldStyle(.roundedBorder)
                    Button("应用") { rename(selected, to: replacement.trimmed) }.disabled(replacement.trimmed.isEmpty)
                    Button("删除标签…", role: .destructive) { confirmDelete = true }
                }
            }
            HStack { Button("查看所选标签的素材") { if let selected { store.navigate(.tag(selected)); dismiss() } }.disabled(selected == nil); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 570)
        .alert("从所有素材移除此标签？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("移除标签", role: .destructive) { if let selected { rename(selected, to: "") } }
        } message: { Text("素材文件会保留，文件夹自动标签也会更新。") }
    }
    private func rename(_ old: String, to new: String) {
        Task { do { try await store.repository?.renameTag(old, to: new); await store.refresh(); selected = nil; replacement = "" } catch { store.error = error.localizedDescription } }
    }
}

struct QuickSwitchView: View {
    var store: AppStore
    @State private var query = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    private var matches: [(String, String, LibraryScope)] {
        let base: [(String, String, LibraryScope)] = [("全部素材", "square.grid.2x2", .all), ("我的收藏", "heart", .favorites), ("未分类", "tray", .uncategorized), ("最近浏览", "clock", .recent), ("回收站", "trash", .trash)]
        let all = base + store.folders.map { ($0.name, "folder", .folder($0.id)) } + store.smartFolders.map { ($0.name, "folder.badge.gearshape", .smart($0.id)) } + store.tags.keys.sorted().map { ($0, "tag", .tag($0)) }
        return Array(all.filter { query.isEmpty || $0.0.localizedCaseInsensitiveContains(query) }.prefix(30))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("快速切换文件夹、标签…", text: $query).textFieldStyle(.plain).focused($focused).onSubmit { if let first = matches.first { store.navigate(first.2); dismiss() } }; Text("esc").font(.caption).foregroundStyle(.tertiary) }.font(.title3).padding(22)
            Divider()
            ScrollView {
                VStack(spacing: 3) { ForEach(Array(matches.enumerated()), id: \.offset) { _, match in Button { store.navigate(match.2); dismiss() } label: { HStack { Label(match.0, systemImage: match.1); Spacer(); Image(systemName: "return").foregroundStyle(.tertiary) }.padding(10).contentShape(Rectangle()) }.buttonStyle(.plain) } }.padding(10)
            }.frame(maxHeight: 400)
            HStack { Text("按回车打开第一个结果"); Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }.font(.caption).foregroundStyle(.secondary).padding(14)
        }.frame(width: 540).onAppear { focused = true }
    }
}

struct WatchFolder: Codable, Identifiable, Sendable {
    var id = UUID().uuidString
    var path: String
    var folderID: String?
    var enabled = true
    var signatures: [String: String] = [:]
}

struct WatchFolderEditor: View {
    var store: AppStore
    @State private var watches: [WatchFolder] = []
    @State private var selectedFolder: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("自动导入文件夹").font(.title2.bold())
            Text("应用运行时每 10 秒检查一次。首次添加会导入目录中的现有文件，之后仅处理新文件或已修改的文件，原文件保留。").font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($watches) { $watch in
                    HStack { Toggle(isOn: $watch.enabled) { VStack(alignment: .leading) { Text(URL(fileURLWithPath: watch.path).lastPathComponent); Text(watch.path).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }; Spacer(); Button { watches.removeAll { $0.id == watch.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
                }
            }.frame(height: 220)
            Picker("新监控目录的导入位置", selection: $selectedFolder) { Text("未分类").tag(nil as String?); ForEach(store.folders) { Text($0.name).tag(Optional($0.id)) } }
            HStack {
                Button("添加文件夹…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url, !watches.contains(where: { $0.path == url.path }) {
                        let resolved = url.resolvingSymlinksInPath().path, root = store.repository?.root.path ?? ""
                        guard resolved != root, !resolved.hasPrefix(root + "/"), !root.hasPrefix(resolved + "/") else { store.error = "监控目录不能包含资源库或位于资源库内部。"; return }
                        watches.append(WatchFolder(path: url.path, folderID: selectedFolder))
                    }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { Task { do { try await store.repository?.setPreference("watchFolders", value: watches); store.startWatcher(); dismiss() } catch { store.error = error.localizedDescription } } }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 610).task { watches = (try? await store.repository?.preference("watchFolders", as: [WatchFolder].self)) ?? [] }
    }
}

extension AppStore {
    func startWatcher() {
        watcherTask?.cancel()
        guard let repository else { return }
        watcherTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard let self, !self.isBusy, self.repository === repository else { continue }
                do {
                    var watches = try await repository.preference("watchFolders", as: [WatchFolder].self) ?? []
                    var changed = false
                    for index in watches.indices where watches[index].enabled {
                        let watch = watches[index]
                        let candidates = try await Task.detached { () throws -> [(URL, String)] in
                            let folder = URL(fileURLWithPath: watch.path).resolvingSymlinksInPath()
                            guard folder.path != repository.root.path, !folder.path.hasPrefix(repository.root.path + "/"), !repository.root.path.hasPrefix(folder.path + "/") else { return [] }
                            guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw LibraryError.message("自动导入目录不可访问：\(watch.path)") }
                            var output: [(URL, String)] = []
                            while let url = files.nextObject() as? URL {
                                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey])
                                guard values.isRegularFile == true, values.isSymbolicLink != true, let modified = values.contentModificationDate, Date().timeIntervalSince(modified) > 5 else { continue }
                                let signature = "\(values.fileSize ?? 0)-\(modified.timeIntervalSince1970)"
                                if watch.signatures[url.path] != signature { output.append((url, signature)) }
                            }
                            return output
                        }.value
                        guard !Task.isCancelled, self.repository === repository, !self.isBusy else { break }
                        if !candidates.isEmpty {
                            self.isBusy = true
                            defer { self.isBusy = false }
                            for (url, signature) in candidates {
                                try Task.checkCancellation()
                                self.progressTitle = "自动导入 · \(url.lastPathComponent)"
                                do {
                                    let result = try await repository.importFile(url, folderIDs: watch.folderID.map { [$0] } ?? [])
                                    if !result.duplicate { await self.analyze(result.asset, in: repository) }
                                    watches[index].signatures[url.path] = signature; changed = true
                                } catch { self.activityErrors.append("自动导入 \(url.lastPathComponent)：\(error.localizedDescription)") }
                            }
                        }
                    }
                    if changed { try await repository.setPreference("watchFolders", value: watches); await self.refresh(); self.notice = "自动导入已完成" }
                } catch is CancellationError { return }
                catch { self.notice = error.localizedDescription }
            }
        }
    }
}
