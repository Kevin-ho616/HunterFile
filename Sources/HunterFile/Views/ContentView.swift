import SwiftUI
import HunterFileCore

struct ContentView: View {
    @Bindable var store: AppStore
    @FocusState private var searchFocused: Bool
    var body: some View {
        NavigationSplitView {
            SidebarView(store: store).navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 330)
        } detail: {
            HSplitView {
                ZStack {
                    VStack(spacing: 0) {
                        header
                        if store.showFilters { FilterBar(store: store) }
                        if store.similarityIDs != nil {
                            HStack { Label("相似度排序", systemImage: "photo.on.rectangle.angled"); Spacer(); Button("退出相似搜索") { store.similarityIDs = nil; store.scheduleRefresh() } }.font(.caption).padding(12).background(.tint.opacity(0.08))
                        }
                        if !store.semanticMessage.isEmpty {
                            HStack {
                                Label(store.semanticMessage, systemImage: "sparkles")
                                Spacer()
                                if store.semanticImageVector != nil { Button("退出以图搜索") { store.semanticImageVector = nil; store.scheduleRefresh() } }
                            }.font(.caption).padding(12).background(.tint.opacity(0.08))
                        }
                        folderBrowserHeader
                        AssetBrowser(store: store)
                        statusBar
                    }
                    .opacity(store.showPreview ? 0 : 1)
                    .disabled(store.showPreview)
                    .allowsHitTesting(!store.showPreview)
                    .accessibilityHidden(store.showPreview)
                    if store.showPreview { PreviewView(store: store) }
                }.frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
                if store.showInspector { InspectorView(store: store).frame(minWidth: 250, idealWidth: 280, maxWidth: 350) }
            }
            .navigationTitle(store.title)
            .navigationSubtitle(store.libraryName)
        }
        .frame(minWidth: 950, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.chooseImport() } label: { Label("导入", systemImage: "plus") }.help("导入文件或文件夹 ⌘I").disabled(store.isBusy)
                Menu {
                    Button("素材问答…") { store.sheet = .question }.disabled(store.repository == nil)
                    Button("添加网页书签…") { store.sheet = .bookmark }
                    Button("从剪贴板导入") { store.pasteFromClipboard() }
                    Button("导入 Eagle 资源库…") { store.chooseEagleLibrary() }
                    Button("自动导入文件夹…") { store.sheet = .watch }
                    Divider()
                    Button("备份资源库…") { store.chooseBackup() }
                    Button("任务记录") { store.sheet = .activity }
                } label: { Label("更多操作", systemImage: "ellipsis.circle") }
                Button { store.showInspector.toggle() } label: { Label("属性面板", systemImage: "sidebar.right") }.help("属性面板 ⌥⌘I")
            }
        }
        .sheet(item: $store.sheet) { sheet in SheetRouter(store: store, sheet: sheet) }
        .sheet(isPresented: $store.showTagManager) { TagManagerView(store: store) }
        .sheet(isPresented: $store.showQuickSwitch) { QuickSwitchView(store: store) }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: store.filter) {
            store.similarityIDs = nil; store.limit = 500
            if !store.filter.query.isEmpty { store.semanticImageTask?.cancel(); store.semanticImageVector = nil }
            store.scheduleRefresh()
        }
        .onChange(of: store.sort) { store.scheduleRefresh() }
        .onChange(of: store.layout) { UserDefaults.standard.set(store.layout, forKey: "layout") }
        .onChange(of: store.thumbnailSize) { UserDefaults.standard.set(store.thumbnailSize, forKey: "thumbnailSize") }
        .background(FolderDropFeedbackReset {
            if store.folderDropTargetID != nil { store.folderDropTargetID = nil }
        })
        .background {
            Button("搜索") { store.showPreview = false; searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                headerTitle
                Spacer(minLength: 12)
                searchControls
            }
            VStack(alignment: .leading, spacing: 12) {
                headerTitle
                searchControls
            }
        }.padding(.horizontal, 22).padding(.vertical, 20)
    }
    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.title).font(.system(size: 23, weight: .semibold))
            Text("\(store.total.formatted()) " + (store.filter.isEmpty && store.semanticImageVector == nil ? "个素材" : "个匹配素材") + (store.selection.isEmpty ? "" : " · 已选 \(store.selection.count) 项")).font(.system(size: 12)).foregroundStyle(.secondary)
        }.lineLimit(1)
    }
    private var searchControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(store.semanticEnabled ? "描述画面或内容…" : "搜索名称、标签、备注…", text: $store.filter.query).textFieldStyle(.plain).focused($searchFocused)
                if !store.filter.query.isEmpty { Button { store.filter.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
            }.padding(9).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8)).frame(minWidth: 100, maxWidth: 280)
            Toggle("AI 搜索", isOn: Binding(get: { store.semanticEnabled }, set: { enabled in
                if store.localModelPath.isEmpty { store.chooseLocalModel() } else { store.semanticEnabled = enabled }
            })).toggleStyle(.switch).controlSize(.small).font(.system(size: 12, weight: .medium)).fixedSize()
                .help("启用或关闭本地 AI 搜索；未配置时选择检索模型")
            if store.semanticEnabled { Button { store.chooseSemanticImage() } label: { Image(systemName: "photo.on.rectangle") }.buttonStyle(.plain).help("以图搜索素材").accessibilityLabel("以图搜索素材") }
            Button { store.showFilters.toggle() } label: { Image(systemName: "line.3.horizontal.decrease.circle" + (!store.filter.isEmpty ? ".fill" : "")) }.buttonStyle(.plain).font(.title3).help("筛选")
            Menu {
                Picker("排序", selection: $store.sort) { ForEach(AssetSortOrder.allCases, id: \.self) { Text($0.title).tag($0) } }
                Divider()
                Button("保存为智能文件夹…") { store.sheet = .smart(nil) }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 14)).frame(width: 28, height: 28)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("排序").help("排序")
            Picker("布局", selection: $store.layout) {
                Image(systemName: "square.grid.2x2").tag("grid")
                Image(systemName: "rectangle.grid.1x2").tag("waterfall")
                Image(systemName: "list.bullet").tag("list")
            }.pickerStyle(.segmented).labelsHidden().frame(width: 112).help("网格 / 瀑布流 / 列表")
        }
    }
    @ViewBuilder private var folderBrowserHeader: some View {
        if case .folder = store.scope {
            VStack(spacing: 0) {
                HStack {
                    if let parentID = store.folders.first(where: { .folder($0.id) == store.scope })?.parentID {
                        Button { store.navigate(.folder(parentID)) } label: { Label("上级文件夹", systemImage: "chevron.left") }.buttonStyle(.plain)
                    }
                    Spacer()
                    Toggle("包含子文件夹内容", isOn: $store.includeSubfolders).toggleStyle(.checkbox)
                        .help("同时调整文件夹浏览、搜索范围和侧栏计数；同一素材只计一次")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.bottom, 12)
                if store.lockedFolder == nil && !store.childFolders.isEmpty {
                    subfolders
                }
            }.padding(.horizontal, 16).padding(.top, 4)
        }
    }
    private var subfolders: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("子文件夹 · \(store.childFolders.count)").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(store.childFolders) { folder in
                        let targeted = Binding(get: { store.folderDropTargetID == folder.id }, set: {
                            if $0 { store.folderDropTargetID = folder.id }
                            else if store.folderDropTargetID == folder.id { store.folderDropTargetID = nil }
                        })
                        Button { store.navigate(.folder(folder.id)) } label: {
                            HStack(spacing: 10) {
                                FolderSymbol(folder: folder).font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(folder.name).lineLimit(1)
                                    Text("\(store.folderCounts[folder.id] ?? 0) 个素材").font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(width: 160, alignment: .leading).padding(12)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(targeted.wrappedValue ? Color.accentColor : .clear, lineWidth: 2) }
                        }.buttonStyle(.plain).help("打开 \(folder.name)；\(store.folderCountHelp)")
                            .onDrop(of: FolderDropDelegate.types, delegate: FolderDropDelegate(store: store, folder: folder, targeted: targeted, expanded: .constant(false)))
                    }
                }.padding(2)
            }
            Divider()
        }.padding(.horizontal, 4).padding(.bottom, 12)
    }
    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            if store.isBusy {
                HStack(spacing: 10) {
                    ProgressView(value: store.progress).frame(width: 100)
                    Text(store.progressTitle).lineLimit(1)
                    Spacer()
                    Button("取消") { store.cancelJob() }.buttonStyle(.link)
                }.font(.caption).padding(.horizontal, 18).padding(.vertical, 9)
            } else if store.semanticIndexing {
                HStack(spacing: 10) {
                    ProgressView(value: store.semanticProgress).frame(width: 100)
                    Text(store.semanticIndexTitle).lineLimit(1)
                    Spacer()
                    Button(store.semanticPaused ? "继续" : "暂停") { if store.semanticPaused { store.startSemanticIndex(resume: true) } else { store.pauseSemanticIndex() } }.buttonStyle(.link)
                }.font(.caption).padding(.horizontal, 18).padding(.vertical, 9)
            } else {
                HStack(spacing: 12) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text(store.notice.isEmpty ? "本地资源库 · \(ByteCountFormatter.string(fromByteCount: store.totalBytes, countStyle: .file))" : store.notice).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 10)
                    if store.layout != "list" {
                        Image(systemName: "photo").foregroundStyle(.tertiary)
                        Slider(value: $store.thumbnailSize, in: AppStore.thumbnailSizeRange).frame(width: 100).accessibilityLabel("缩略图大小").help("缩略图大小（⌥ Option + 滚轮）")
                        Image(systemName: "photo").font(.body).foregroundStyle(.secondary)
                    }
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 34)
            }
        }
    }
}
