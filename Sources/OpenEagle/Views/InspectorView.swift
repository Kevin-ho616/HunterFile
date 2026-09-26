import SwiftUI
import OpenEagleCore

struct InspectorView: View {
    @Bindable var store: AppStore
    @State private var tagInput = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(store.selection.count > 1 ? "批量编辑" : "素材属性").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if !store.selection.isEmpty { Text("\(store.selection.count) 项").font(.caption).foregroundStyle(.tertiary) }
                }
                if let asset = store.selectedAsset {
                    if store.selection.count == 1 {
                        AssetThumbnail(asset: asset, root: store.repository?.root).frame(maxWidth: .infinity).frame(height: 160).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8)).onTapGesture { store.preview() }
                        AssetMetadataEditor(store: store, asset: asset).id(asset.id)
                    } else {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 40, weight: .light)).foregroundStyle(.tint).frame(maxWidth: .infinity).padding(15)
                        Text("已选中 \(store.selection.count) 个素材").font(.headline)
                        Button("批量重命名…") { store.sheet = .batchRename }.frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("评分与收藏")
                        HStack(spacing: 7) {
                            ForEach(1...5, id: \.self) { index in
                                Button { store.edit { $0.rating = asset.rating == index ? 0 : index } } label: { Image(systemName: index <= asset.rating ? "star.fill" : "star").foregroundStyle(index <= asset.rating ? .orange : .secondary) }.buttonStyle(.plain).help("\(index) 星")
                            }
                            Spacer()
                            Button { store.edit { $0.favorite = !asset.favorite } } label: { Image(systemName: asset.favorite ? "heart.fill" : "heart").foregroundStyle(asset.favorite ? .pink : .secondary) }.buttonStyle(.plain).help("收藏")
                        }.font(.system(size: 16))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle(store.selection.count > 1 ? "共有标签" : "标签")
                        FlowLayout(spacing: 6) {
                            ForEach(commonTags, id: \.self) { tag in
                                HStack(spacing: 5) {
                                    Button(tag) { store.navigate(.tag(tag)) }.buttonStyle(.plain)
                                    Button { store.edit { $0.tags.removeAll { $0 == tag } } } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain)
                                }.font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 5).background(.tint.opacity(0.1), in: Capsule()).foregroundStyle(.tint)
                            }
                        }
                        HStack {
                            TextField("添加标签，逗号分隔", text: $tagInput).textFieldStyle(.roundedBorder).onSubmit(addTags)
                            Button(action: addTags) { Image(systemName: "plus") }.disabled(tagInput.trimmed.isEmpty)
                        }
                        if !tagInput.isEmpty {
                            ForEach(store.tags.keys.filter { $0.localizedCaseInsensitiveContains(tagInput) && !commonTags.contains($0) }.sorted().prefix(5), id: \.self) { tag in
                                Button("# " + tag) { tagInput = tag; addTags() }.buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            sectionTitle("所属文件夹")
                            Spacer()
                            Menu {
                                ForEach(store.folders) { folder in Button(folder.name) { store.addToFolder(folder.id) } }
                            } label: {
                                Label("添加", systemImage: "folder.badge.plus").font(.system(size: 11, weight: .medium))
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("添加到文件夹").help("添加到文件夹")
                        }
                        ForEach(store.folders.filter { asset.folderIDs.contains($0.id) }) { folder in
                            HStack {
                                Button { store.navigate(.folder(folder.id)) } label: { Label(folder.name, systemImage: "folder").font(.caption).lineLimit(1) }.buttonStyle(.plain)
                                Spacer()
                                Button { store.edit { $0.folderIDs.removeAll { $0 == folder.id } } } label: { Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.tertiary) }.buttonStyle(.plain).help("移出该文件夹")
                            }
                        }
                        if asset.folderIDs.isEmpty { Text("尚未分类").font(.caption).foregroundStyle(.tertiary) }
                    }
                    if store.selection.count == 1 {
                        if !asset.colors.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionTitle("颜色类别")
                                HStack(spacing: 7) {
                                    ForEach(asset.colors, id: \.self) { hex in
                                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string); store.notice = "已复制 \(hex)" } label: { RoundedRectangle(cornerRadius: 5).fill(Color(hex: hex)).frame(height: 27) }.buttonStyle(.plain).help("复制 \(hex)")
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("文件信息")
                            metadata("类型", asset.ext.uppercased())
                            metadata("尺寸", asset.dimensions)
                            metadata("文件大小", ByteCountFormatter.string(fromByteCount: asset.byteCount, countStyle: .file))
                            if asset.duration > 0 { metadata("时长", Duration.seconds(asset.duration).formatted(.time(pattern: .hourMinuteSecond))) }
                            metadata("添加日期", asset.importedAt.formatted(date: .abbreviated, time: .shortened))
                            metadata("修改日期", asset.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            metadata("标注", "\(asset.annotations.count) 条")
                        }
                        if !asset.extractedText.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    sectionTitle("识别文字")
                                    Spacer()
                                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(asset.extractedText, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("复制识别文字")
                                }
                                Text(asset.extractedText).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(16)
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Button { store.sheet = .export } label: { Label("导出", systemImage: "square.and.arrow.up") }
                        Spacer()
                        Button { store.revealSelection() } label: { Image(systemName: "folder") }.help("在 Finder 中显示")
                        Button { store.preview() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("预览")
                    }.controlSize(.small)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "cursorarrow.click.2").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(.tertiary)
                        Text("选择素材以查看详情").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text("按住 ⌘ 或 ⇧ 可多选\n为多个素材批量添加标签和分类").font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).lineSpacing(5)
                    }.frame(maxWidth: .infinity).padding(.top, 80)
                    if case .folder(let id) = store.scope, let folder = store.folders.first(where: { $0.id == id }) {
                        Divider()
                        Text(folder.name).font(.headline)
                        if !folder.note.isEmpty { Text(folder.note).font(.caption).foregroundStyle(.secondary) }
                        Button("编辑文件夹与自动标签") { store.sheet = .folder(folder) }.buttonStyle(.link)
                    }
                }
            }.padding(20)
        }
    }
    private var commonTags: [String] {
        guard let first = store.selectedAssets.first else { return [] }
        return store.selectedAssets.dropFirst().reduce(Set(first.tags)) { $0.intersection($1.tags) }.sorted()
    }
    private func addTags() {
        let tags = tagInput.tagsFromText
        guard !tags.isEmpty else { return }
        store.edit { $0.tags = Array(Set($0.tags + tags)).sorted() }; tagInput = ""
    }
    private func sectionTitle(_ text: String) -> some View { Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
    private func metadata(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(name).foregroundStyle(.tertiary); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.system(size: 11))
    }
}

struct AssetMetadataDraft: Equatable {
    struct Fields: Equatable {
        var name: String
        var note: String
        var source: String
    }
    let original: Fields
    var edited: Fields
    init(_ asset: Asset) {
        original = Fields(name: asset.name, note: asset.note, source: asset.sourceURL)
        edited = original
    }
    func apply(to asset: inout Asset) {
        if edited.name != original.name { asset.name = edited.name }
        if edited.note != original.note { asset.note = edited.note }
        if edited.source != original.source { asset.sourceURL = edited.source }
    }
}

private struct AssetMetadataEditor: View {
    var store: AppStore
    var asset: Asset
    private var dirty: Bool { store.metadataDrafts[asset.id] != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("名称", text: field(\.name)).font(.system(size: 15, weight: .medium)).textFieldStyle(.plain).onSubmit(save)
            Text(asset.ext.uppercased() + " · " + asset.kind.title).font(.caption).foregroundStyle(.tertiary)
            Divider()
            Text("备注").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            TextEditor(text: field(\.note)).font(.system(size: 12)).scrollContentBackground(.hidden).frame(height: 85).padding(5).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Image(systemName: "link").foregroundStyle(.tertiary)
                TextField("来源网址", text: field(\.source)).textFieldStyle(.plain).font(.caption).onSubmit(save)
                if let url = URL(string: field(\.source).wrappedValue), ["http", "https"].contains(url.scheme ?? "") { Link(destination: url) { Image(systemName: "arrow.up.right.square").font(.caption) } }
            }
            if dirty { Button("保存修改", action: save).buttonStyle(.borderedProminent).controlSize(.small) }
        }.onDisappear { if dirty { save() } }
    }
    private func field(_ key: WritableKeyPath<AssetMetadataDraft.Fields, String>) -> Binding<String> {
        Binding(get: { (store.metadataDrafts[asset.id] ?? AssetMetadataDraft(asset)).edited[keyPath: key] }, set: { value in
            var draft = store.metadataDrafts[asset.id] ?? AssetMetadataDraft(asset)
            draft.edited[keyPath: key] = value
            store.metadataDrafts[asset.id] = draft.edited == draft.original ? nil : draft
        })
    }
    private func save() {
        guard var draft = store.metadataDrafts[asset.id], let repository = store.repository else { return }
        draft.edited.name = draft.edited.name.trimmed.isEmpty ? draft.original.name : draft.edited.name.trimmed
        draft.edited.source = draft.edited.source.trimmed
        let changes = draft, id = asset.id
        store.metadataDrafts[id] = changes
        Task {
            do {
                let previous = try await repository.modify(ids: [id]) { changes.apply(to: &$0) }
                store.undoStack.append(previous); store.redoStack = []
                await store.refresh()
                if store.metadataDrafts[id] == changes { store.metadataDrafts.removeValue(forKey: id) }
            } catch { store.error = error.localizedDescription }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { positions(width: proposal.width ?? 260, subviews: subviews).1 }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = positions(width: bounds.width, subviews: subviews).0
        for (index, view) in subviews.enumerated() { view.place(at: CGPoint(x: bounds.minX + points[index].x, y: bounds.minY + points[index].y), proposal: .unspecified) }
    }
    private func positions(width: CGFloat, subviews: Subviews) -> ([CGPoint], CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; line = max(line, size.height)
        }
        return (points, CGSize(width: width, height: y + line))
    }
}
