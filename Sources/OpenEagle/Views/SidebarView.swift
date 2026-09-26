import SwiftUI
import OpenEagleCore

struct SidebarView: View {
    @Bindable var store: AppStore
    @State private var folderSearch = ""
    @State private var pendingDelete: LibraryFolder?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage).resizable().interpolation(.high).scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("OpenEagle").font(.system(size: 15, weight: .semibold))
                    Menu {
                        Button("新建资源库…") { store.chooseLibrary(create: true) }
                        Button("打开资源库…") { store.chooseLibrary(create: false) }
                        Divider()
                        ForEach(UserDefaults.standard.stringArray(forKey: "recentLibraries") ?? [], id: \.self) { path in
                            Button(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) { Task { await store.openLibrary(URL(fileURLWithPath: path), create: false) } }
                        }
                    } label: { Text(store.libraryName).font(.caption).lineLimit(1).foregroundStyle(.secondary) }.menuStyle(.borderlessButton)
                }
                Spacer()
            }.padding(.horizontal, 17).padding(.top, 18).padding(.bottom, 21)
            List(selection: Binding<LibraryScope?>(get: { store.scope }, set: { if let value = $0 { store.navigate(value) } })) {
                Section("资源库") {
                    row("全部素材", "square.grid.2x2", .all, count: store.counts["all"])
                    row("未分类", "tray", .uncategorized, count: store.counts["uncategorized"])
                    row("未标签", "tag", .untagged, count: store.counts["untagged"])
                    row("我的收藏", "heart", .favorites, count: store.counts["favorites"])
                    row("最近浏览", "clock", .recent)
                    row("随机灵感", "shuffle", .random)
                }
                Section("类型") {
                    ForEach(AssetKind.allCases, id: \.self) { kind in row(kind.title, kind.symbol, .kind(kind), count: store.counts[kind.rawValue]) }
                }
                Section {
                    ForEach(store.smartFolders) { folder in
                        row(folder.name, "folder.badge.gearshape", .smart(folder.id))
                            .contextMenu {
                                Button("编辑条件…") { store.sheet = .smart(folder) }
                                Button("删除智能文件夹", role: .destructive) { Task { do { try await store.repository?.deleteSmartFolder(id: folder.id); store.navigate(.all) } catch { store.error = error.localizedDescription } } }
                            }
                    }
                    if store.smartFolders.isEmpty { Text("保存常用筛选条件").font(.caption).foregroundStyle(.tertiary) }
                } header: {
                    HStack { Text("智能文件夹"); Spacer(); Button { store.sheet = .smart(nil) } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("新建智能文件夹") }
                }
                Section {
                    if folderSearch.isEmpty {
                        ForEach(store.folders.filter { $0.parentID == nil }) { folder in FolderTree(store: store, folder: folder, pendingDelete: $pendingDelete) }
                            .onInsert(of: [FolderDragItem.type]) { index, _ in FolderDragItem.insert(at: index, into: nil, in: store) }
                    } else {
                        ForEach(store.folders.filter { $0.name.localizedCaseInsensitiveContains(folderSearch) }) { folder in
                            HStack { FolderSymbol(folder: folder); Text(folder.name).lineLimit(1); Spacer(); Text((store.folderCounts[folder.id] ?? 0).formatted()).font(.caption).foregroundStyle(.tertiary).help(store.folderCountHelp) }.tag(LibraryScope.folder(folder.id)).padding(.vertical, 2)
                        }
                    }
                    if store.folders.isEmpty { Button("创建第一个文件夹") { store.sheet = .folder(LibraryFolder(name: "")) }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary) }
                } header: {
                    HStack { Text("文件夹"); Spacer(); Text("\(store.folders.count)").foregroundStyle(.tertiary); Button { store.sheet = .folder(LibraryFolder(name: "")) } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("新建顶层文件夹") }
                        .help("拖到顶层文件夹之间或列表末尾，可移到顶层")
                }
                Section("工具") {
                    Button { store.showTagManager = true } label: { Label("标签管理", systemImage: "tag.circle") }.buttonStyle(.plain)
                    row("重复文件", "doc.on.doc", .duplicates)
                    row("回收站", "trash", .trash, count: store.counts["trash"])
                }
            }.listStyle(.sidebar)
            HStack { Image(systemName: "line.3.horizontal.decrease"); TextField("筛选文件夹", text: $folderSearch).textFieldStyle(.plain) }.font(.caption).foregroundStyle(.secondary).padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6)).padding(12)
        }
        .alert("删除文件夹？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除分类", role: .destructive) {
                guard let folder = pendingDelete else { return }
                Task { do { try await store.repository?.deleteFolder(id: folder.id); store.navigate(.all) } catch { store.error = error.localizedDescription } }
                pendingDelete = nil
            }
        } message: { Text("将删除“\(pendingDelete?.name ?? "")”和它的子文件夹分类，所有原始素材保留在资源库中。") }
    }
    private func row(_ title: String, _ icon: String, _ scope: LibraryScope, count: Int? = nil) -> some View {
        HStack { Label(title, systemImage: icon); Spacer(); if let count, count > 0 { Text(count.formatted()).font(.caption).foregroundStyle(.tertiary).monospacedDigit() } }.tag(scope).padding(.vertical, 2)
    }
}

private struct FolderTree: View {
    var store: AppStore
    var folder: LibraryFolder
    @Binding var pendingDelete: LibraryFolder?
    @State private var expanded = true
    private var folderDropTargeted: Bool { store.folderDropTargetID == folder.id }
    private var dropTarget: Binding<Bool> {
        Binding(get: { folderDropTargeted }, set: { targeted in
            if targeted { store.folderDropTargetID = folder.id }
            else if folderDropTargeted { store.folderDropTargetID = nil }
        })
    }
    var children: [LibraryFolder] { store.folders.filter { $0.parentID == folder.id } }
    private var siblings: [LibraryFolder] { store.folders.filter { $0.parentID == folder.parentID } }
    private var siblingIndex: Int { siblings.firstIndex(where: { $0.id == folder.id }) ?? 0 }
    var body: some View {
        Group {
            if children.isEmpty { label }
            else {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(children) { FolderTree(store: store, folder: $0, pendingDelete: $pendingDelete) }
                        .onInsert(of: [FolderDragItem.type]) { index, _ in FolderDragItem.insert(at: index, into: folder.id, in: store) }
                } label: { label }
            }
        }.tag(LibraryScope.folder(folder.id))
    }
    private var label: some View {
        HStack {
            FolderSymbol(folder: folder)
            Text(folder.name).lineLimit(1)
            Spacer()
            Text((store.folderCounts[folder.id] ?? 0).formatted()).font(.caption).foregroundStyle(.tertiary).help(store.folderCountHelp)
        }.frame(height: 24).contentShape(Rectangle())
            .contextMenu {
                Button("编辑文件夹…") { store.sheet = .folder(folder) }
                Button("新建同级文件夹…") { store.newSiblingFolder(of: folder) }
                Button("新建子文件夹…") { store.sheet = .folder(LibraryFolder(name: "", parentID: folder.id)) }
                Menu("调整位置") {
                    Button("上移") { store.moveFolder(folder.id, toParent: folder.parentID, before: siblings[siblingIndex - 1].id) }.disabled(siblingIndex == 0)
                    Button("下移") { store.moveFolder(folder.id, toParent: folder.parentID, before: siblings.dropFirst(siblingIndex + 2).first?.id) }.disabled(siblingIndex >= siblings.count - 1)
                    Button("移到顶层") { store.moveFolder(folder.id, toParent: nil) }.disabled(folder.parentID == nil)
                }
                Button("添加所选素材") { store.addToFolder(folder.id) }.disabled(store.selection.isEmpty)
                Button("导出文件夹及子文件夹中的素材…") { store.exportFolder(folder) }.disabled(store.isBusy)
                if folder.password != nil {
                    Button("解锁文件夹…") { store.sheet = .unlock(folder) }
                    Button("立即锁定") {
                        guard !store.hasUnsavedChanges else { store.error = "请先保存素材属性，再锁定文件夹。"; return }
                        Task { do {
                            store.showPreview = false
                            for window in store.windows { window.close() }
                            store.windows = []
                            try await store.repository?.lockFolder(id: folder.id); store.selection = []; await store.refresh()
                        } catch { store.error = error.localizedDescription } }
                    }
                }
                Divider()
                Button("删除文件夹分类…", role: .destructive) { pendingDelete = folder }
            }
            .background {
                RoundedRectangle(cornerRadius: 6).fill(folderDropTargeted ? Color.accentColor.opacity(0.16) : .clear)
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(folderDropTargeted ? Color.accentColor : .clear, lineWidth: 1.5) }
                    .padding(.horizontal, -6).padding(.vertical, -4)
            }
            .overlay {
                FolderDragSource(folder: folder, libraryPath: store.repository?.root.path ?? "") {
                    store.navigate(.folder(folder.id))
                }.accessibilityHidden(true)
            }
            .onDrop(of: FolderDropDelegate.types, delegate: FolderDropDelegate(store: store, folder: folder, targeted: dropTarget, expanded: $expanded))
            .task(id: folderDropTargeted) {
                guard folderDropTargeted else { return }
                try? await Task.sleep(for: .milliseconds(650))
                if !Task.isCancelled { expanded = true }
            }
            .onChange(of: store.folders) { dropTarget.wrappedValue = false }
            .onDisappear { dropTarget.wrappedValue = false }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x6E83E8
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
