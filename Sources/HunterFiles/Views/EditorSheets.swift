import SwiftUI
import HunterFilesCore

struct SheetRouter: View {
    var store: AppStore
    var sheet: AppSheet
    var body: some View {
        switch sheet {
        case .folder(let folder): FolderEditor(store: store, folder: folder)
        case .unlock(let folder): FolderUnlockView(store: store, folder: folder)
        case .smart(let folder): SmartFolderEditor(store: store, folder: folder)
        case .bookmark: BookmarkEditor(store: store)
        case .batchRename: BatchRenameEditor(store: store)
        case .export: ExportEditor(store: store)
        case .watch: WatchFolderEditor(store: store)
        case .activity: ActivityView(store: store)
        case .ai: AIEditor(store: store)
        case .question: QuestionView(store: store)
        }
    }
}

private struct FolderEditor: View {
    var store: AppStore
    @State var folder: LibraryFolder
    @State private var tags = ""
    @State private var password = ""
    @State private var removePassword = false
    @State private var showIconPicker = false
    @State private var lockedAncestor: LibraryFolder?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(store.folders.contains { $0.id == folder.id } ? "编辑文件夹" : "新建文件夹").font(.title2.bold())
            if let lockedAncestor {
                Text("请先解锁“\(lockedAncestor.name)”再修改文件夹。").foregroundStyle(.secondary)
                SecureField("现有密码", text: $password).textFieldStyle(.roundedBorder)
                Button("解锁") {
                    Task { do { try await store.repository?.unlockFolder(id: lockedAncestor.id, password: password); self.lockedAncestor = try await store.repository?.lockedAncestor(of: folder.id); password = ""; await store.refresh() } catch { store.error = error.localizedDescription } }
                }.buttonStyle(.borderedProminent)
            } else {
            Form {
                TextField("名称", text: $folder.name)
                LabeledContent("图标") {
                    HStack(spacing: 10) {
                        FolderSymbol(folder: folder, size: 22)
                        Button("选择图标…") { showIconPicker = true }
                            .popover(isPresented: $showIconPicker) { FolderIconPicker(icon: $folder.icon, color: Color(hex: folder.color)) }
                        Text(FolderIcons.title(for: folder.icon)).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Picker("上级文件夹", selection: $folder.parentID) {
                    Text("资源库根目录").tag(nil as String?)
                    ForEach(store.folders.filter { $0.id != folder.id }) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("自动标签", text: $tags, prompt: Text("逗号分隔"))
                Text("新添加到该文件夹的素材会获得这些标签。").font(.caption).foregroundStyle(.secondary)
                TextField("描述", text: $folder.note, axis: .vertical).lineLimit(3...5)
                SecureField(folder.password == nil ? "设置密码" : "更改密码", text: $password, prompt: Text("留空不更改，至少 6 位"))
                if folder.password != nil { Toggle("移除密码保护", isOn: $removePassword) }
                Text("密码用于隐藏应用内的素材，原始文件不会加密。关闭应用后自动锁定，也可右键立即锁定。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("颜色")
                    ForEach(MediaService.palette, id: \.self) { hex in Button { folder.color = hex } label: { Circle().fill(Color(hex: hex)).frame(width: 18, height: 18).overlay { Circle().stroke(folder.color == hex ? Color.primary : Color.clear, lineWidth: 2).padding(-2) } }.buttonStyle(.plain) }
                }
            }.textFieldStyle(.roundedBorder)
            }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") {
                folder.autoTags = tags.tagsFromText
                Task { do {
                    if removePassword { folder.password = nil }
                    else if !password.isEmpty { let value = password; folder.password = try await Task.detached { try PasswordDigest.create(value) }.value }
                    try await store.repository?.saveFolder(folder); await store.refresh(); dismiss()
                } catch { store.error = error.localizedDescription } }
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(folder.name.trimmed.isEmpty || lockedAncestor != nil) }
        }.padding(28).frame(width: 520).task { tags = folder.autoTags.joined(separator: ", "); lockedAncestor = try? await store.repository?.lockedAncestor(of: folder.id) }
    }
}

private struct FolderUnlockView: View {
    var store: AppStore
    var folder: LibraryFolder
    @State private var password = ""
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("解锁 \(folder.name)", systemImage: "lock.open").font(.title2.bold())
            SecureField("文件夹密码", text: $password).textFieldStyle(.roundedBorder).onSubmit(unlock)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("解锁", action: unlock).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(password.isEmpty) }
        }.padding(28).frame(width: 410)
    }
    private func unlock() {
        Task { do { try await store.repository?.unlockFolder(id: folder.id, password: password); await store.refresh(); dismiss() } catch { self.error = error.localizedDescription } }
    }
}

private struct SmartFolderEditor: View {
    var store: AppStore
    var folder: SmartFolder?
    @State private var name = ""
    @State private var filters: [AssetFilter] = [.init()]
    @State private var matchAll = true
    @State private var semantic = false
    @State private var description = ""
    @State private var minimum = 0.6
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("智能文件夹").font(.title2.bold())
            Text("自动收集符合条件的素材，原文件不会重复复制。").font(.caption).foregroundStyle(.secondary)
            TextField("文件夹名称", text: $name).textFieldStyle(.roundedBorder)
            Toggle("按语义描述收集素材（本地 AI）", isOn: $semantic)
            if semantic {
                TextField("例如：海洋生物、珊瑚与水下摄影", text: $description, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
                HStack { Text("相关度门槛 \(minimum, specifier: "%.2f")"); Slider(value: $minimum, in: 0...1, step: 0.05) }
                Text("门槛越高，收集越严格；相关度不是概率。只收集已索引且可访问的素材，再叠加下方规则。").font(.caption).foregroundStyle(.secondary)
            }
            Picker("规则关系", selection: $matchAll) { Text("满足所有规则组").tag(true); Text("满足任一规则组").tag(false) }.pickerStyle(.segmented)
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(filters.indices, id: \.self) { index in
                        GroupBox {
                            VStack(spacing: 15) {
                                HStack { Text("规则组 \(index + 1)").font(.headline); Spacer(); if filters.count > 1 { Button("移除") { filters.remove(at: index) }.buttonStyle(.link) } }
                                AdvancedFilters(filter: $filters[index])
                            }.padding(12)
                        }
                    }
                }
            }.frame(maxHeight: 520)
            HStack {
                Button("添加规则组") { filters.append(.init()) }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    var smart = folder ?? SmartFolder(name: name, filters: filters)
                    smart.name = name.trimmed; smart.filters = filters; smart.matchAll = matchAll
                    smart.semanticQuery = semantic ? description.trimmed : nil; smart.minimumSimilarity = semantic ? minimum : nil
                    Task { do { try await store.repository?.saveSmartFolder(smart); await store.refresh(); store.navigate(.smart(smart.id)); dismiss() } catch { store.error = error.localizedDescription } }
                }.buttonStyle(.borderedProminent).disabled(name.trimmed.isEmpty || (semantic && description.trimmed.isEmpty))
            }
        }.padding(28).frame(width: 510).onAppear {
            if let folder { name = folder.name; filters = folder.filters; matchAll = folder.matchAll; semantic = folder.isSemantic; description = folder.semanticQuery ?? ""; minimum = folder.minimumSimilarity ?? 0.6 }
            else {
                filters = [store.filter]
                if store.semanticEnabled && !store.filter.query.trimmed.isEmpty { semantic = true; description = store.filter.query; filters[0].query = "" }
            }
        }
    }
}

private struct BookmarkEditor: View {
    var store: AppStore
    @State private var url = ""
    @State private var name = ""
    @State private var tags = ""
    @State private var download = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("收集网页灵感", systemImage: "link").font(.title2.bold())
            Form {
                TextField("网址", text: $url, prompt: Text("https://…"))
                TextField("名称", text: $name, prompt: Text("可选"))
                TextField("标签", text: $tags, prompt: Text("逗号分隔，可选"))
                Picker("保存方式", selection: $download) { Text("网页书签").tag(false); Text("下载链接指向的文件").tag(true) }
                Text(download ? "适用于图片、视频、音频和文档的直链。" : "保存网址，之后可在默认浏览器中打开。").font(.caption).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") { dismiss(); store.saveWeb(url, name: name, download: download, tags: tags.tagsFromText) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(url.trimmed.isEmpty || store.isBusy) }
        }.padding(28).frame(width: 490).onAppear {
            if let text = NSPasteboard.general.string(forType: .string), ["https://", "http://"].contains(where: text.hasPrefix) { url = text.trimmed }
        }
    }
}

private struct BatchRenameEditor: View {
    var store: AppStore
    @State private var pattern = "{name}"
    @State private var start = 1
    @State private var find = ""
    @State private var replace = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("批量重命名 \(store.selection.count) 个素材").font(.title2.bold())
            Form {
                TextField("命名模板", text: $pattern)
                Text("{name} 原名    {n} 三位序号    {date} 添加日期").font(.caption).foregroundStyle(.secondary)
                Stepper("起始序号：\(start)", value: $start, in: 0...999999)
                TextField("查找文本", text: $find)
                TextField("替换为", text: $replace)
            }.textFieldStyle(.roundedBorder)
            GroupBox("预览") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(store.selectedAssets.prefix(5).enumerated()), id: \.element.id) { index, asset in HStack { Text(asset.name).foregroundStyle(.secondary); Image(systemName: "arrow.right"); Text(renamed(asset, index: index)).fontWeight(.medium) }.font(.caption).lineLimit(1) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("应用重命名") {
                let names = Dictionary(uniqueKeysWithValues: store.selectedAssets.enumerated().map { ($0.element.id, renamed($0.element, index: $0.offset)) })
                store.edit { if let name = names[$0.id] { $0.name = name } }; dismiss()
            }.buttonStyle(.borderedProminent).disabled(pattern.trimmed.isEmpty) }
        }.padding(28).frame(width: 540)
    }
    private func renamed(_ asset: Asset, index: Int) -> String {
        let date = asset.importedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        var value = pattern.replacingOccurrences(of: "{name}", with: asset.name).replacingOccurrences(of: "{n}", with: String(format: "%03d", start + index)).replacingOccurrences(of: "{date}", with: date)
        if !find.isEmpty { value = value.replacingOccurrences(of: find, with: replace) }
        return value.safeFilename
    }
}

private struct ExportEditor: View {
    var store: AppStore
    @State private var metadata = true
    @State private var format = "original"
    @State private var pixels = 0
    @State private var rotate = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("导出 \(store.selection.count) 个素材").font(.title2.bold())
            Form {
                Picker("格式", selection: $format) { Text("原始文件").tag("original"); Text("可迁移素材包").tag("pack"); Text("PNG 图片").tag("png"); Text("JPEG 图片").tag("jpg"); Text("TIFF 图片").tag("tiff") }
                if format == "original" { Toggle("同时导出 JSON 元数据", isOn: $metadata) }
                else if format == "pack" { Text("包含原件、文件夹层级、标签、评分、备注与标注，可导入其他 HunterFiles 资源库。密码保护不会导出。").font(.caption).foregroundStyle(.secondary) }
                else {
                    TextField("最长边 / px（0 保留）", value: $pixels, format: .number)
                    Toggle("顺时针旋转 90°", isOn: $rotate)
                    Text("转换仅支持可读取的静态位图；JPEG 以 92% 质量编码。动画会导出首帧。").font(.caption).foregroundStyle(.secondary)
                }
                Text("同名文件会自动编号，资源库中的原件保持完整。").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("选择导出文件夹…") { dismiss(); store.exportSelection(metadata: metadata, format: format, maxPixels: max(0, pixels), rotate: rotate) }.buttonStyle(.borderedProminent).disabled(store.selection.isEmpty || store.isBusy) }
        }.padding(28).frame(width: 470)
    }
}

struct ActivityView: View {
    var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("任务记录").font(.title2.bold())
            Text(store.notice.isEmpty ? "尚无完成的任务" : store.notice).font(.body)
            if store.isBusy { ProgressView(store.progressTitle, value: store.progress) }
            ScrollView { Text(store.activityErrors.isEmpty ? "没有错误或警告。" : store.activityErrors.joined(separator: "\n\n")).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.frame(height: 260).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 600)
    }
}
