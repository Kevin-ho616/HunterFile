import SwiftUI

struct QuestionView: View {
    var store: AppStore
    @State private var question = ""
    @State private var answer: LibraryAnswer?
    @State private var error = ""
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("素材问答", systemImage: "text.bubble").font(.title2.bold())
            Text("检索范围：\(store.title)。根据最多 5 份已索引素材及 3 幅画面在本机回答，可打开来源核对。文档为摘录、视频为采样画面，未识别视频音频。").font(.caption).foregroundStyle(.secondary)
            TextField("例如：资料中提到哪些海洋生物？", text: $question, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder).disabled(running)
            if running { ProgressView("检索素材并生成回答…") }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let answer {
                        Text(answer.text).textSelection(.enabled)
                        ForEach(answer.sources) { source in
                            Button {
                                dismiss(); store.openAnswerSource(source, question: question)
                            } label: { Label("[\(source.id)] \(source.asset.filename) \(source.hit.location)", systemImage: "doc.text.magnifyingglass") }.buttonStyle(.link)
                        }
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 240)
            HStack {
                Button(running ? "取消生成" : "关闭") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("检索并回答") {
                    let question = question
                    running = true; answer = nil; error = ""
                    task = Task {
                        defer { running = false }
                        do { let result = try await store.askLibrary(question); try Task.checkCancellation(); answer = result }
                        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                    }
                }.buttonStyle(.borderedProminent).disabled(running || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 650, height: 480).onDisappear { task?.cancel() }
    }
}
