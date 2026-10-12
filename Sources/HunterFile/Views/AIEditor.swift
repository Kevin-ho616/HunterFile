import SwiftUI
import HunterFileCore

struct AIEditor: View {
    var store: AppStore
    @State private var instruction = "生成简洁的中文名称和客观摘要，保留素材中的关键信息。"
    @State private var suggestions: [AISuggestion] = []
    @State private var errors: [String] = []
    @State private var running = false
    @State private var mode = "本地分类"
    @State private var task: Task<Void, Never>?
    @State private var taskID = UUID()
    @Environment(\.dismiss) private var dismiss
    private var reviewed: [AISuggestion] { suggestions.filter(\.selected) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("AI 整理建议", systemImage: "sparkles").font(.title2.bold())
            Picker("整理方式", selection: $mode) { ForEach(["本地分类", "本地生成", "接口生成"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).disabled(running)
            if mode == "本地分类" {
                Text("根据已有标签、文件夹说明和示例素材推荐分类。相似度用于排序。勾选需要应用的素材并审核标签与文件夹，支持撤销。").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(mode == "本地生成" ? "Gemma 在本机生成名称和独立的 AI 摘要，人工备注保留。默认仅应用摘要；勾选“应用名称”后才覆盖显示名称。支持撤销。" : "将向 \(URL(string: UserDefaults.standard.string(forKey: "aiEndpoint") ?? "")?.host ?? "尚未配置的接口") 发送所选 \(store.selection.count) 项的缩略图与名称。请逐项审核后应用。").font(.caption).foregroundStyle(.secondary)
                TextField("整理要求", text: $instruction, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
            }
            if running { ProgressView("处理建议中…") }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach($suggestions) { $suggestion in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("应用：\(store.assets.first { $0.id == suggestion.id }?.filename ?? suggestion.name)", isOn: $suggestion.selected)
                                if mode == "本地分类" { Text(suggestion.name).font(.headline) }
                                else {
                                    TextField("建议名称", text: $suggestion.name).font(.headline)
                                    if mode == "本地生成" { Toggle("应用名称（覆盖显示名称）", isOn: $suggestion.applyName) }
                                }
                                if mode != "本地生成" { TextField("标签", text: Binding(get: { suggestion.tags.joined(separator: ", ") }, set: { suggestion.tags = $0.tagsFromText })) }
                                if mode == "本地分类" {
                                    ForEach(suggestion.candidateFolderIDs, id: \.self) { id in
                                        Toggle("加入 \(store.folders.first { $0.id == id }?.name ?? "文件夹")", isOn: Binding(get: { suggestion.folderIDs.contains(id) }, set: { checked in suggestion.folderIDs.removeAll { $0 == id }; if checked { suggestion.folderIDs.append(id) } }))
                                    }
                                    Text(suggestion.explanation).font(.caption).foregroundStyle(.secondary)
                                } else if mode == "本地生成" {
                                    Text("AI 摘要").font(.caption).foregroundStyle(.secondary)
                                    TextEditor(text: $suggestion.note).font(.body).frame(height: 130).border(.secondary.opacity(0.2)).accessibilityLabel("AI 摘要")
                                } else { TextField("备注", text: $suggestion.note, axis: .vertical).lineLimit(3...7) }
                            }.textFieldStyle(.roundedBorder).padding(10)
                        }.disabled(running)
                    }
                    ForEach(errors.indices, id: \.self) { Text(errors[$0]).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }.frame(height: 320)
            HStack {
                Button(mode == "接口生成" ? "生成建议（发送缩略图）" : "生成建议") { generate() }.disabled(running || store.selection.isEmpty || (mode == "本地分类" && !store.semanticEnabled))
                Spacer()
                Button(running ? "取消生成" : "关闭") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("应用勾选的 \(reviewed.count) 项") {
                    if mode == "本地分类" { store.applyLocalOrganization(reviewed); dismiss(); return }
                    if mode == "本地生成" {
                        let reviewed = reviewed
                        running = true
                        task = Task {
                            defer { running = false }
                            do { try await store.applyLocalMetadata(reviewed); dismiss() }
                            catch { errors.append(error.localizedDescription) }
                        }
                        return
                    }
                    let map = Dictionary(uniqueKeysWithValues: reviewed.map { ($0.id, $0) })
                    store.edit(ids: Set(map.keys)) { if let suggestion = map[$0.id] { $0.name = suggestion.name.safeFilename; $0.tags = Array(Set($0.tags + suggestion.tags)).sorted(); $0.note = suggestion.note } }
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(reviewed.isEmpty || running)
            }
        }.padding(28).frame(width: 720).onAppear { mode = store.semanticEnabled ? "本地分类" : (store.generationModelPath.isEmpty ? "接口生成" : "本地生成") }
            .onChange(of: mode) { task?.cancel(); taskID = UUID(); suggestions = []; errors = []; running = false }
            .onDisappear { task?.cancel() }
    }
    private func generate() {
        guard let repository = store.repository else { return }
        let assets = store.selectedAssets, mode = mode, instruction = instruction, token = UUID()
        taskID = token; running = true; suggestions = []; errors = []
        task = Task {
            defer { if taskID == token { running = false } }
            do {
                if mode == "本地分类" { suggestions = try await store.localOrganizationSuggestions(assets, in: repository) }
                else if mode == "本地生成" { suggestions = try await store.localMetadataSuggestions(assets, in: repository, instruction: instruction) }
                else {
                    for asset in assets {
                        try Task.checkCancellation()
                        do { suggestions.append(try await AIService.suggest(asset: asset, thumbnail: repository.thumbnailURL(for: asset), instruction: instruction)) }
                        catch { if !Task.isCancelled { errors.append("\(asset.name)：\(error.localizedDescription)") } }
                    }
                }
                try Task.checkCancellation()
            } catch { if !Task.isCancelled && taskID == token { errors.append(error.localizedDescription) } }
        }
    }
}
