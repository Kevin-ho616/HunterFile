import SwiftUI
import WebKit
import HunterFilesCore

extension AppStore {
    func openPlugin() {
        let panel = NSOpenPanel(); panel.title = "打开 HunterFiles 插件"; panel.message = "选择包含 plugin.json 与 HTML 入口的文件夹。"; panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { openPlugin(at: url) }
    }
    func openPlugin(at folder: URL) {
        do {
            let root = folder.resolvingSymlinksInPath()
            let data = try Data(contentsOf: root.appendingPathComponent("plugin.json"))
            guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any], let name = manifest["name"] as? String, let entry = manifest["entry"] as? String else { throw LibraryError.message("插件的 plugin.json 需要 name 和 entry。") }
            let url = root.appendingPathComponent(entry).standardizedFileURL.resolvingSymlinksInPath()
            guard url.path.hasPrefix(root.path + "/"), ["html", "htm"].contains(url.pathExtension), FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.message("插件入口必须是目录内的 HTML 文件。") }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = name + " · HunterFiles 插件"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PluginWebView(store: self, entry: url, directory: root))
            window.center(); window.makeKeyAndOrderFront(nil); windows.removeAll { !$0.isVisible }; windows.append(window)
        } catch { self.error = error.localizedDescription }
    }
}

private struct PluginWebView: NSViewRepresentable {
    let store: AppStore
    let entry: URL
    let directory: URL
    func makeCoordinator() -> Coordinator { Coordinator(store: store, directory: directory) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "openeagle")
        let bridge = """
        window.hunterfiles = window.hunterfile = window.openeagle = Object.freeze({
          getSelection: () => window.webkit.messageHandlers.openeagle.postMessage({method:'selection'}),
          getLibrary: () => window.webkit.messageHandlers.openeagle.postMessage({method:'library'}),
          saveText: (name, text) => window.webkit.messageHandlers.openeagle.postMessage({method:'saveText', name, text})
        });
        """
        config.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.loadFileURL(entry, allowingReadAccessTo: directory)
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName: "openeagle", contentWorld: .page) }
    final class Coordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        let store: AppStore
        let directory: URL
        init(store: AppStore, directory: URL) { self.store = store; self.directory = directory }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
            guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, url.isFileURL, url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(directory.path + "/"), let payload = message.body as? [String: Any], let method = payload["method"] as? String else { replyHandler(nil, "无效插件请求"); return }
            Task { @MainActor in
                do {
                    switch method {
                    case "selection":
                        let data = try JSONEncoder().encode(store.selectedAssets)
                        replyHandler(try JSONSerialization.jsonObject(with: data), nil)
                    case "library": replyHandler(["name": store.libraryName, "count": store.counts["all"] ?? 0, "tags": store.tags], nil)
                    case "saveText":
                        guard let text = payload["text"] as? String, text.utf8.count <= 8_000_000 else { throw LibraryError.message("文本超过 8 MB") }
                        let panel = NSSavePanel(); panel.nameFieldStringValue = (payload["name"] as? String ?? "export.txt").safeFilename
                        if panel.runModal() == .OK, let url = panel.url { try Data(text.utf8).write(to: url, options: .atomic); replyHandler(true, nil) }
                        else { replyHandler(false, nil) }
                    default: replyHandler(nil, "不支持的插件方法")
                    }
                } catch { replyHandler(nil, error.localizedDescription) }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.isFileURL && url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(directory.path + "/") { decisionHandler(.allow) }
            else { decisionHandler(.cancel) }
        }
    }
}
