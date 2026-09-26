import SwiftUI
import AppKit
import OpenEagleCore

@main
struct OpenEagleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup("OpenEagle", id: "library") {
            ContentView(store: store)
                .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
                .onOpenURL { url in
                    Task {
                        await store.initialLibraryTask?.value
                        if url.isFileURL && url.pathExtension.lowercased() == "openeagle" { await store.openLibrary(url, create: false) }
                        else if url.isFileURL { store.importURLs([url]) }
                    }
                }
                .task { delegate.store = store; store.configureAPI() }
        }
        .defaultSize(width: 1380, height: 880)
        .windowStyle(.titleBar)
        .commands { LibraryCommands(store: store) }
        Settings { SettingsView(store: store) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.isBusy == true || store?.hasUnsavedChanges == true else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "仍有任务或未保存的编辑"; alert.informativeText = "返回应用可保存修改。直接退出会丢弃尚未保存的编辑，并取消剩余任务。"
        alert.addButton(withTitle: "继续运行"); alert.addButton(withTitle: "取消任务并退出")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

struct LibraryCommands: Commands {
    var store: AppStore
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建资源库…") { store.chooseLibrary(create: true) }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("打开资源库…") { store.chooseLibrary(create: false) }.keyboardShortcut("o")
            Divider()
            Button("导入文件或文件夹…") { store.chooseImport() }.keyboardShortcut("i")
            Button("导入 Eagle 资源库…") { store.chooseEagleLibrary() }
            Button("添加网页书签…") { store.sheet = .bookmark }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("截取屏幕区域…") { store.captureScreenshot() }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(store.isBusy)
            Divider()
            Button("导出所选素材…") { store.sheet = .export }.keyboardShortcut("e").disabled(store.selection.isEmpty)
            Button("备份完整资源库…") { store.chooseBackup() }
        }
        CommandGroup(replacing: .undoRedo) {
            Button("撤销素材编辑") { store.undo() }.keyboardShortcut("z").disabled(store.undoStack.isEmpty)
            Button("重做素材编辑") { store.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store.redoStack.isEmpty)
        }
        CommandMenu("素材") {
            Button("预览") { store.preview() }.keyboardShortcut("y").disabled(store.selection.isEmpty)
            Button("在默认应用中打开") { store.openExternally() }.keyboardShortcut(.return, modifiers: .command).disabled(store.selection.isEmpty)
            Button("在 Finder 中显示") { store.revealSelection() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(store.selection.isEmpty)
            Button("复制原文件") { store.copyFiles() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(store.selection.isEmpty)
            Button("从剪贴板导入") { store.pasteFromClipboard() }.keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button("全选已加载素材") { store.selection = Set(store.assets.map(\.id)) }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button("批量重命名…") { store.sheet = .batchRename }.disabled(store.selection.isEmpty)
            Button("移到回收站") { store.trashSelection() }.keyboardShortcut(.delete, modifiers: .command).disabled(store.selection.isEmpty || store.scope == .trash)
            Button("恢复所选素材") { store.restoreSelection() }.disabled(store.selection.isEmpty || store.scope != .trash)
            Divider()
            Button("识别文字（本地）") { store.recognizeSelection() }.disabled(store.selection.isEmpty || store.isBusy)
            Button("自动分类标签（本地）") { store.recognizeSelection(classify: true) }.disabled(store.selection.isEmpty || store.isBusy)
            Button("查找相似图片") { store.findSimilar() }.disabled(store.selectedAsset?.kind != .image || store.isBusy)
            Button("AI 整理…") { store.sheet = .ai }.disabled(store.selection.isEmpty || store.isBusy)
        }
        CommandMenu("整理") {
            Button("新建文件夹…") { store.newSiblingFolder() }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("新建智能文件夹…") { store.sheet = .smart(nil) }
            Button("标签管理…") { store.showTagManager = true }
            Button("查找重复文件") { store.navigate(.duplicates) }
            Button("自动导入文件夹…") { store.sheet = .watch }
        }
        CommandGroup(after: .sidebar) {
            Button("切换属性面板") { store.showInspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
            Button("快速切换…") { store.showQuickSwitch = true }.keyboardShortcut("k")
            Button("筛选素材") { store.showFilters.toggle() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("刷新资源库") { store.scheduleRefresh() }.keyboardShortcut("r")
        }
        CommandGroup(replacing: .help) {
            Button("OpenEagle 使用说明") {
                let path = Bundle.main.resourceURL?.appendingPathComponent("USER-GUIDE.md")
                if let path { NSWorkspace.shared.open(path) }
            }
        }
    }
}
