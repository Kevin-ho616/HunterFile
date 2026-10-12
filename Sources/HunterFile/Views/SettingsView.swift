import SwiftUI
import HunterFileCore

struct SettingsView: View {
    @Bindable var store: AppStore
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("hoverPreview") private var hoverPreview = false
    @AppStorage("allowDuplicates") private var allowDuplicates = false
    @AppStorage("apiEnabled") private var apiEnabled = false
    @AppStorage("aiEndpoint") private var aiEndpoint = ""
    @AppStorage("aiModel") private var aiModel = ""
    @State private var aiKey = ""
    @State private var saved = false
    var body: some View {
        TabView {
            Form {
                Section("界面") {
                    Picker("外观", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                    Toggle("悬停放大镜 0.5 秒后预览", isOn: $hoverPreview)
                }
                Section("导入") {
                    Toggle("允许导入重复文件", isOn: $allowDuplicates)
                    Text("默认按文件内容跳过重复项，并合并新标签和文件夹归属。").font(.caption).foregroundStyle(.secondary)
                    Button("管理自动导入文件夹…") { store.sheet = .watch }
                }
                Section("当前资源库") {
                    Text(store.repository?.root.path ?? "未打开").font(.caption).textSelection(.enabled)
                    HStack {
                        Button("在 Finder 中显示") { if let root = store.repository?.root { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root.path) } }
                        Button("完整备份…") { store.chooseBackup() }.disabled(store.isBusy)
                    }
                }
            }.formStyle(.grouped).tabItem { Label("通用", systemImage: "gearshape") }
            Form {
                Section("浏览器与自动化") {
                    Toggle("启用本地采集 API", isOn: $apiEnabled).onChange(of: apiEnabled) { store.configureAPI() }
                    LabeledContent("服务地址", value: "http://127.0.0.1:41596")
                    Text("仅监听本机回环地址。读取或写入素材都需要采集令牌。浏览器扩展可保存图片、网页书签和当前页面截图。").font(.caption).foregroundStyle(.secondary)
                    Button("复制采集令牌") {
                        do { let token = try Secrets.apiToken(); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(token, forType: .string) } catch { store.error = error.localizedDescription }
                    }
                    Button("打开浏览器扩展文件夹") { if let url = Bundle.main.resourceURL?.appendingPathComponent("browser-extension") { NSWorkspace.shared.open(url) } }
                    Text("Chrome / Edge：扩展管理 → 开发者模式 → 加载已解压的扩展，然后在扩展设置中粘贴令牌。").font(.caption).foregroundStyle(.secondary)
                }
                Section("插件") {
                    Text("支持 HunterFile HTML / JavaScript 插件。插件只在主动打开时运行。").font(.caption).foregroundStyle(.secondary)
                    Button("打开本地插件…") { store.openPlugin() }
                    Button("打开内置素材统计插件") { if let url = Bundle.main.resourceURL?.appendingPathComponent("plugins/selection-stats") { store.openPlugin(at: url) } }
                }
            }.formStyle(.grouped).tabItem { Label("扩展", systemImage: "puzzlepiece.extension") }
            Form {
                Section("本地 AI 搜索与分类") {
                    Toggle("启用本地 AI", isOn: $store.semanticEnabled)
                    HStack {
                        Text(store.localModelPath.isEmpty ? "尚未选择模型" : URL(fileURLWithPath: store.localModelPath).lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer(); Button("选择模型…") { store.chooseLocalModel() }
                    }
                    Link("下载 EmbeddingGemma 2 文字与视觉模型（约 388 MB）", destination: LocalEmbedding.modelURL)
                    Text("下载后选择 .litertlm 文件。图片、视频画面和 PDF 在本机建立索引，不需要 API Key。首次建立索引后可重复使用。").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(store.semanticIndexTitle.isEmpty ? "已索引 \(store.semanticIndexed) 项" : store.semanticIndexTitle).font(.caption).lineLimit(2)
                        Spacer()
                        if store.semanticIndexing && !store.semanticPaused { Button("暂停") { store.pauseSemanticIndex() } }
                        else { Button(store.semanticPaused ? "继续建立" : "更新索引") { store.startSemanticIndex(resume: true) }.disabled(!store.semanticEnabled || store.localModelPath.isEmpty) }
                    }
                    if store.semanticIndexing { ProgressView(value: store.semanticProgress) }
                    Button("重新建立索引") { store.rebuildSemanticIndex() }.disabled(!store.semanticEnabled || store.localModelPath.isEmpty || store.semanticIndexing)
                    if !store.semanticIndexErrors.isEmpty { ScrollView { Text(store.semanticIndexErrors.values.sorted().joined(separator: "\n")).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }.frame(maxHeight: 80) }
                }
                Section("本地名称、摘要与素材问答") {
                    Text(store.generationModelPath.isEmpty ? "尚未选择生成模型" : URL(fileURLWithPath: store.generationModelPath).lastPathComponent).lineLimit(1).truncationMode(.middle)
                    HStack { Button("选择生成模型…") { store.chooseGenerationModel() }; Button("释放生成模型") { store.releaseGenerationModel() }.disabled(store.generationEngine == nil && store.generationLoadTask == nil) }
                    Link("下载 Gemma 4 E2B 生成模型（约 2.59 GB）", destination: LocalGeneration.modelURL)
                    Text(store.generationStatus).font(.caption).foregroundStyle(.secondary)
                    Text("下载后选择 .litertlm 文件；首次使用时校验并加载。名称和摘要在 AI 整理中预览后应用，问答可打开引用来源。先完成检索索引；文档与视频仅使用摘录和采样画面，视频音频未转写。").font(.caption).foregroundStyle(.secondary)
                }
                Section("接口生成（可选）") {
                    TextField("接口地址", text: $aiEndpoint, prompt: Text("https://…/v1/chat/completions"))
                    TextField("视觉模型名称", text: $aiModel)
                    SecureField("API Key", text: $aiKey)
                    Button(saved ? "已保存到钥匙串" : "保存 API Key") {
                        do { try Secrets.write(aiKey, account: "ai-key"); saved = true } catch { store.error = error.localizedDescription }
                    }
                    Text("使用兼容 Chat Completions 的视觉模型。只有在“AI 整理”中点击生成建议时，才会将选中素材的缩略图和名称发送到你填写的接口。所有建议须经预览后再应用。").font(.caption).foregroundStyle(.secondary)
                }
                Section("本地智能工具") {
                    Text("文字识别、图像分类和相似图片检索使用 Apple Vision，在本机完成，无需 API Key。").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("AI", systemImage: "sparkles") }.onAppear { aiKey = Secrets.read("ai-key") ?? "" }
            VStack(spacing: 15) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage).resizable().interpolation(.high).scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
                Text("HunterFile").font(.largeTitle.bold())
                Text("1.0.0 · 原生 macOS 素材管理器").foregroundStyle(.secondary)
                Text("收藏灵感，整理创作。\n本地存储 · 原始素材 · 开放接口").multilineTextAlignment(.center).font(.body).foregroundStyle(.secondary)
                Text("独立实现，与 Eagle 官方无关联。").font(.caption).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label("关于", systemImage: "info.circle") }
        }.frame(width: 610, height: 500)
    }
}
