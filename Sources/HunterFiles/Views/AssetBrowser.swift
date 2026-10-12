import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HunterFilesCore

struct AssetBrowser: View {
    @Bindable var store: AppStore
    @State private var targeted = false
    @State private var confirmEmpty = false
    @State private var hoverPreview: Asset?
    @State private var marqueeSelecting = false
    @FocusState private var browserFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            if store.scope == .duplicates && store.total > 0 {
                HStack {
                    Label("内容完全相同的文件", systemImage: "doc.on.doc")
                    Spacer()
                    Button("合并重复项") {
                        guard let repository = store.repository else { return }
                        store.runJob("合并重复素材…") { let count = try await repository.mergeDuplicates(); store.notice = "已合并 \(count) 项，重复原件保留在回收站。" }
                    }.disabled(store.isBusy)
                }.font(.caption).padding(12).background(.quaternary.opacity(0.25))
            }
            if store.scope == .trash && store.total > 0 {
                HStack {
                    Text("素材仍可恢复")
                    Spacer()
                    Button("恢复所选") { store.restoreSelection() }.disabled(store.selection.isEmpty)
                    Button("清空回收站…") { confirmEmpty = true }.disabled(store.isBusy)
                }.font(.caption).padding(12).background(.quaternary.opacity(0.25))
            }
            if let folder = store.lockedFolder {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.tint)
                    Text("“\(folder.name)”已锁定").font(.title2.bold())
                    Text("输入密码后可浏览这个文件夹中的素材。").foregroundStyle(.secondary)
                    Button("解锁文件夹…") { store.sheet = .unlock(folder) }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else if store.assets.isEmpty && store.filter.isEmpty && (store.scope == .trash || store.scope == .duplicates) {
                ContentUnavailableView(store.scope == .trash ? "回收站是空的" : "没有重复文件", systemImage: store.scope == .trash ? "trash" : "checkmark.circle", description: Text(store.scope == .trash ? "删除的素材会保留在这里，可以随时恢复。" : "按文件内容检查，当前没有可合并的重复素材。"))
            }
            else if store.assets.isEmpty { emptyState }
            else if store.layout == "list" { table }
            else {
                GeometryReader { geometry in
                    let columns = max(1, Int((geometry.size.width - 8) / (store.thumbnailSize + 16)))
                    let width = max(100, (geometry.size.width - 8 - Double(columns - 1) * 16) / Double(columns))
                    ScrollView {
                        if store.layout == "waterfall" {
                            let groups = waterfall(columns: columns, width: width)
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(groups.indices, id: \.self) { column in
                                    LazyVStack(spacing: 16) {
                                        ForEach(groups[column]) { asset in AssetCard(store: store, asset: asset, height: imageHeight(asset, width: width), hoverPreview: $hoverPreview, marqueeSelecting: marqueeSelecting) }
                                    }.frame(width: width)
                                }
                            }.padding(4)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 18) {
                                ForEach(store.assets) { asset in AssetCard(store: store, asset: asset, height: width * 0.83, hoverPreview: $hoverPreview, marqueeSelecting: marqueeSelecting) }
                            }.padding(4)
                        }
                        loadMore
                    }
                    .overlayPreferenceValue(AssetBoundsKey.self) { anchors in
                        GeometryReader { proxy in
                            MarqueeSelection(frames: anchors.mapValues { proxy[$0] }, enabled: !store.showPreview,
                                selection: $store.selection,
                                onBegin: { hoverPreview = nil; marqueeSelecting = true; browserFocused = true },
                                onEnd: { marqueeSelecting = false })
                                .id(store.scope).id(store.layout)
                                .accessibilityHidden(true)
                        }
                    }
                    .focusable().focusEffectDisabled().focused($browserFocused)
                    .onKeyPress(.space) { store.preview(); return .handled }
                    .onKeyPress(.return) { store.preview(); return .handled }
                    .onKeyPress(.rightArrow) { store.nextAsset(1); return .handled }
                    .onKeyPress(.leftArrow) { store.nextAsset(-1); return .handled }
                    .onKeyPress(.downArrow) { store.nextAsset(columns); return .handled }
                    .onKeyPress(.upArrow) { store.nextAsset(-columns); return .handled }
                    .onKeyPress(keys: ["a"]) { press in if press.modifiers.contains(.command) { store.selection = Set(store.assets.map(\.id)); return .handled }; return .ignored }
                }
                .background(ScrollWheelZoom(zoom: $store.thumbnailSize, enabled: !store.showPreview,
                    limits: AppStore.thumbnailSizeRange, requiredModifiers: .option))
            }
        }
        // Keep the drop indicator outside the scrolling viewport, even between rows.
        .clipped()
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.opacity(0.45))
        .overlay {
            if let hoverPreview, !store.showPreview, !targeted {
                QuickLookPreview(url: store.repository?.fileURL(for: hoverPreview))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)) }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if targeted {
                ImportDropBorder().padding(5)
                    .mask { Rectangle().strokeBorder(lineWidth: 12) }
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in store.importURLs(urls); return true } isTargeted: { targeted = $0 }
        .alert("清空 HunterFiles 回收站？", isPresented: $confirmEmpty) {
            Button("取消", role: .cancel) {}
            Button("移入系统废纸篓", role: .destructive) {
                guard let repository = store.repository else { return }
                store.runJob("移入系统废纸篓…") {
                    let ids = try await repository.matchingIDs(scope: .trash, filter: .init())
                    try await repository.removeToSystemTrash(ids: ids)
                    store.undoStack = []; store.redoStack = []; store.notice = "回收站已清空；仍存在的原件及元数据已移入 macOS 废纸篓。"
                }
            }
        } message: { Text("原件及元数据将移入 macOS 废纸篓，并从此资源库移除。此操作不受当前搜索条件影响。") }
    }
    private var emptyState: some View {
        VStack(spacing: 17) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 27).fill(.tint.opacity(0.08)).frame(width: 112, height: 112).rotationEffect(.degrees(-7))
                Image(systemName: store.filter.isEmpty ? "photo.stack" : "magnifyingglass").font(.system(size: 44, weight: .light)).foregroundStyle(.tint)
            }
            Text(store.repository == nil ? "打开你的资源库" : (store.filter.isEmpty ? (store.childFolders.isEmpty ? "让灵感有处可寻" : (store.includeSubfolders ? "此文件夹暂无可见素材" : "此文件夹暂无直属素材")) : "没有找到匹配的素材")).font(.system(size: 24, weight: .semibold))
            Text(store.filter.isEmpty ? ((store.childFolders.isEmpty || store.includeSubfolders) ? "将图片、视频、字体或整个文件夹拖到这里\n整理收藏，随时找回每一个好想法。" : "点击上方子文件夹进入，或勾选“包含子文件夹内容”。") : "试试更短的关键词，或调整筛选条件。").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            HStack(spacing: 12) {
                if store.repository == nil {
                    Button("打开资源库") { store.chooseLibrary(create: false) }.buttonStyle(.borderedProminent)
                    Button("新建资源库") { store.chooseLibrary(create: true) }
                } else if !store.filter.isEmpty {
                    Button("清除筛选") { store.filter = .init() }.buttonStyle(.borderedProminent)
                } else {
                    Button("导入素材…") { store.chooseImport() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.isBusy)
                    Button("添加网页书签") { store.sheet = .bookmark }.controlSize(.large)
                }
            }.padding(.top, 8)
            if (store.counts["all"] ?? 0) == 0 {
                Button("体验示例素材库") { store.loadDemoLibrary() }.buttonStyle(.link).font(.caption).padding(.top, 6).disabled(store.isBusy)
            }
            Spacer()
            HStack(spacing: 22) {
                Label("⌘I 导入", systemImage: "square.and.arrow.down")
                Label("空格预览", systemImage: "space")
                Label("⌘K 快速切换", systemImage: "command")
            }.font(.caption).foregroundStyle(.tertiary).padding(.bottom, 35)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var table: some View {
        VStack(spacing: 0) {
            Table(store.assets, selection: $store.selection) {
                TableColumn("名称") { asset in
                    HStack(spacing: 10) {
                        AssetThumbnail(asset: asset, root: store.repository?.root).frame(width: 36, height: 32)
                        Text(asset.name).lineLimit(1)
                        if let location = store.semanticHits[asset.id]?.location, !location.isEmpty { Text(location).font(.caption).foregroundStyle(.secondary) }
                    }.contextMenu { AssetContextMenu(store: store, asset: asset) }
                }.width(min: 180, ideal: 250)
                TableColumn("类型") { Text($0.ext.uppercased()).font(.caption).foregroundStyle(.secondary) }.width(60)
                TableColumn("尺寸") { Text($0.dimensions).font(.caption).foregroundStyle(.secondary) }.width(100)
                TableColumn("大小") { Text(ByteCountFormatter.string(fromByteCount: $0.byteCount, countStyle: .file)).font(.caption) }.width(85)
                TableColumn("评分") { Text(String(repeating: "★", count: $0.rating)).foregroundStyle(.orange) }.width(75)
                TableColumn("添加日期") { Text($0.importedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }.width(100)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                Button("预览") { store.preview() }.disabled(ids.isEmpty)
                Button("导出…") { store.sheet = .export }.disabled(ids.isEmpty)
                Button("批量重命名…") { store.sheet = .batchRename }.disabled(ids.isEmpty)
            } primaryAction: { ids in store.selection = ids; store.preview() }
            .onKeyPress(.space) { store.preview(); return .handled }
            loadMore
        }
    }
    @ViewBuilder private var loadMore: some View {
        if store.total > store.assets.count {
            Button("加载更多 · 当前 \(store.assets.count) / \(store.total)") { store.limit += 500; store.scheduleRefresh() }.buttonStyle(.link).padding(20)
                .anchorPreference(key: AssetBoundsKey.self, value: .bounds) { ["loadMore": $0] }
        }
    }
    private func imageHeight(_ asset: Asset, width: Double) -> Double {
        guard asset.width > 0, asset.height > 0 else { return width * 0.75 }
        return min(520, max(90, width * Double(asset.height) / Double(asset.width)))
    }
    private func waterfall(columns: Int, width: Double) -> [[Asset]] {
        var groups = [[Asset]](repeating: [], count: columns), heights = [Double](repeating: 0, count: columns)
        for asset in store.assets {
            let shortest = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            groups[shortest].append(asset); heights[shortest] += imageHeight(asset, width: width) + 56
        }
        return groups
    }
}

private struct ImportDropBorder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) / 5 * 360
            let gradient = AngularGradient(colors: [.cyan, .blue, .purple, .pink, .orange, .cyan], center: .center, angle: .degrees(angle))
            let border = RoundedRectangle(cornerRadius: 12, style: .continuous)
            ZStack {
                border.strokeBorder(gradient, lineWidth: 6).blur(radius: 4).opacity(0.45)
                border.strokeBorder(gradient, lineWidth: 2.5)
            }
        }
    }
}

struct AssetCard: View {
    var store: AppStore
    var asset: Asset
    var height: Double
    @Binding var hoverPreview: Asset?
    var marqueeSelecting = false
    @State private var hovered = false
    @State private var hoverTask: Task<Void, Never>?
    var selected: Bool { store.selection.contains(asset.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.32))
                AssetThumbnail(asset: asset, root: store.repository?.root).padding(5)
                if hovered || asset.favorite {
                    Button { dismissHoverPreview(); store.edit(ids: [asset.id]) { $0.favorite.toggle() } } label: {
                        Image(systemName: asset.favorite ? "heart.fill" : "heart").foregroundStyle(asset.favorite ? .pink : .primary).padding(6).background(.regularMaterial, in: Circle())
                    }.buttonStyle(.plain).padding(7).help("收藏素材")
                }
                VStack { Spacer(); HStack {
                    Text(asset.ext.uppercased()).font(.system(size: 9, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 3).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .opacity(hovered || asset.kind == .video || asset.kind == .audio ? 1 : 0)
                    Spacer()
                    if asset.duration > 0 { Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond))).font(.system(size: 10)).padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4)) }
                    Button { dismissHoverPreview(); store.preview(asset) } label: {
                        Image(systemName: "plus.magnifyingglass").font(.system(size: 13, weight: .medium))
                            .frame(width: 28, height: 28).background(.regularMaterial, in: Circle()).contentShape(Circle())
                    }.buttonStyle(.plain).accessibilityLabel("放大预览").help("悬停半秒放大，点击打开预览")
                        .onHover { inside in
                            dismissHoverPreview()
                            if inside && !marqueeSelecting && !store.showPreview && UserDefaults.standard.bool(forKey: "hoverPreview") {
                                hoverTask = Task { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { hoverPreview = asset } }
                            }
                        }
                }.padding(8) }
            }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 2.5) }
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.name).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1).foregroundStyle(selected ? Color.accentColor : .primary)
                if let location = store.semanticHits[asset.id]?.location, !location.isEmpty { Text(location).font(.system(size: 10)).foregroundStyle(.tint) }
                HStack(spacing: 5) {
                    Text(asset.width > 0 ? asset.dimensions : ByteCountFormatter.string(fromByteCount: asset.byteCount, countStyle: .file)).font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer(minLength: 2)
                    if asset.rating > 0 { Text(String(repeating: "★", count: asset.rating)).font(.system(size: 8)).foregroundStyle(.orange) }
                    if !asset.note.isEmpty { Image(systemName: "text.bubble").font(.system(size: 9)).foregroundStyle(.tertiary) }
                }
            }.padding(.horizontal, 3)
        }
        .anchorPreference(key: AssetBoundsKey.self, value: .bounds) { [asset.id: $0] }
        .contentShape(Rectangle())
        // Select without waiting for the double-click recognition window.
        .onTapGesture { dismissHoverPreview(); store.select(asset) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { dismissHoverPreview(); store.preview(asset) })
        .onHover { inside in
            guard hovered != inside else { return }
            hovered = inside
            if !inside { dismissHoverPreview() }
        }
        .onChange(of: marqueeSelecting) { if marqueeSelecting { dismissHoverPreview() } }
        .onChange(of: store.selection) { dismissHoverPreview() }
        .onChange(of: store.thumbnailSize) { dismissHoverPreview() }
        .onChange(of: store.showPreview) { if store.showPreview { dismissHoverPreview() } }
        .onDisappear { dismissHoverPreview() }
        .contextMenu { AssetContextMenu(store: store, asset: asset) }
        .onDrag {
            dismissHoverPreview()
            if !selected { store.selection = [asset.id] }
            let provider = NSItemProvider(object: (store.repository?.fileURL(for: asset) ?? URL(fileURLWithPath: "/")) as NSURL)
            let draggedIDs = Data(store.selection.joined(separator: ",").utf8)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in completion(draggedIDs, nil); return nil }
            return provider
        }
        .accessibilityElement(children: .contain).accessibilityLabel(asset.filename).accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction { dismissHoverPreview(); store.select(asset) }
        .accessibilityAction(named: "预览") { store.preview(asset) }
    }
    private func dismissHoverPreview() {
        hoverTask?.cancel()
        if hoverPreview?.id == asset.id { hoverPreview = nil }
    }
}

struct AssetThumbnail: View {
    var asset: Asset
    var root: URL?
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center) }
            else {
                VStack(spacing: 12) {
                    Image(systemName: asset.kind.symbol).font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.tint.opacity(0.7))
                    Text(asset.ext.uppercased()).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(root?.path ?? "")/\(asset.id)/\(asset.width)/\(asset.colors)") {
            guard let root else { return }
            image = await ThumbnailCache.shared.image(at: root.appendingPathComponent("assets/\(asset.id)/thumbnail.png"))
        }
    }
}

struct AssetContextMenu: View {
    var store: AppStore
    var asset: Asset
    private var ids: Set<String> { store.selection.contains(asset.id) ? store.selection : [asset.id] }
    var body: some View {
        Button("预览") { store.preview(asset) }
        Button("在默认应用中打开") { store.selection = ids; store.openExternally() }
        Button("在 Finder 中显示") { store.selection = ids; store.revealSelection() }
        Divider()
        Button(asset.favorite ? "取消收藏" : "加入收藏") { store.edit(ids: ids) { $0.favorite = !asset.favorite } }
        Menu("评分") { ForEach(0...5, id: \.self) { rating in Button(rating == 0 ? "取消评分" : String(repeating: "★", count: rating)) { store.edit(ids: ids) { $0.rating = rating } } } }
        Menu("添加到文件夹") { ForEach(store.folders) { folder in Button(folder.name) { store.addToFolder(folder.id, ids: ids) } } }
        Button("批量重命名…") { store.selection = ids; store.sheet = .batchRename }
        Button("导出…") { store.selection = ids; store.sheet = .export }
        Button("复制原文件") { store.selection = ids; store.copyFiles() }
        Divider()
        if asset.kind == .image {
            Button("识别文字（本地）") { store.selection = ids; store.recognizeSelection() }
            Button("查找相似图片") { store.selection = [asset.id]; store.findSimilar() }
        }
        if asset.trashedAt == nil { Button("移到回收站", role: .destructive) { store.edit(ids: ids) { $0.trashedAt = Date() } } }
        else { Button("恢复素材") { store.edit(ids: ids) { $0.trashedAt = nil } } }
    }
}
