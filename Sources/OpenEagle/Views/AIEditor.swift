import SwiftUI
import OpenEagleCore

struct AIEditor: View {
    var store: AppStore
    @State private var instruction = "生成简洁的中文名称、准确的分类标签和一段描述。保留可以用于未来搜索的视觉信息。"
    @State private var suggestions: [AISuggestion] = []
    @State private var errors: [String] = []
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("AI 整理建议", systemImage: "sparkles").font(.title2.bold())
            Text("将向 \(URL(string: UserDefaults.standard.string(forKey: "aiEndpoint") ?? "")?.host ?? "尚未配置的接口") 发送所选 \(store.selection.count) 项的缩略图与名称。生成后可逐项编辑，再统一应用。").font(.caption).foregroundStyle(.secondary)
            TextField("整理要求", text: $instruction, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
            if running { ProgressView("生成建议中…") }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach($suggestions) { $suggestion in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("名称", text: $suggestion.name).font(.headline)
                                TextField("标签", text: Binding(get: { suggestion.tags.joined(separator: ", ") }, set: { suggestion.tags = $0.tagsFromText }))
                                TextField("备注", text: $suggestion.note, axis: .vertical).lineLimit(3...6)
                            }.textFieldStyle(.roundedBorder).padding(10)
                        }
                    }
                    ForEach(errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }.frame(height: 320)
            HStack {
                Button("生成建议（发送缩略图）") { generate() }.disabled(running || store.selection.isEmpty)
                Spacer()
                Button(running ? "取消生成" : "关闭") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("应用 \(suggestions.count) 项建议") {
                    let map = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.id, $0) })
                    store.edit(ids: Set(map.keys)) { if let suggestion = map[$0.id] { $0.name = suggestion.name.safeFilename; $0.tags = Array(Set($0.tags + suggestion.tags)).sorted(); $0.note = suggestion.note } }
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(suggestions.isEmpty || running)
            }
        }.padding(28).frame(width: 680).onDisappear { task?.cancel() }
    }
    private func generate() {
        guard let repository = store.repository else { return }
        let assets = store.selectedAssets
        running = true; suggestions = []; errors = []
        task = Task {
            defer { running = false }
            for asset in assets {
                if Task.isCancelled { break }
                do { suggestions.append(try await AIService.suggest(asset: asset, thumbnail: repository.thumbnailURL(for: asset), instruction: instruction)) }
                catch { if !Task.isCancelled { errors.append("\(asset.name)：\(error.localizedDescription)") } }
            }
        }
    }
}
