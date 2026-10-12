import Foundation
import HunterFilesCore

enum WebCollector {
    static func collect(_ text: String, name: String, download: Bool, into repository: LibraryRepository, folders: [String], tags: [String]) async throws -> Asset {
        guard let url = URL(string: text.trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { throw LibraryError.message("请输入有效的 HTTP 或 HTTPS 地址。") }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let local: URL
        if download {
            var request = URLRequest(url: url); request.timeoutInterval = 90
            let (downloaded, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: downloaded) }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw LibraryError.message("下载失败：服务器未返回成功响应。") }
            guard (try downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_147_483_648 else { throw LibraryError.message("网页下载限制为 2 GB，请在浏览器中下载后导入。") }
            local = temp.appendingPathComponent((response.suggestedFilename ?? url.lastPathComponent).safeFilename)
            try FileManager.default.moveItem(at: downloaded, to: local)
        } else {
            local = temp.appendingPathComponent((name.trimmed.isEmpty ? (url.host ?? "书签") : name).safeFilename + ".webloc")
            try PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0).write(to: local)
        }
        let result = try await repository.importFile(local, folderIDs: folders, tags: tags, sourceURL: url.absoluteString)
        var asset = result.asset
        if !name.trimmed.isEmpty && !result.duplicate {
            asset.name = name.trimmed
            _ = try await repository.modify(ids: [asset.id]) { $0.name = name.trimmed }
        }
        return asset
    }
}
