import Foundation
import Network
import Security
import HunterFilesCore

enum Secrets {
    // Keep the existing Keychain namespace so saved tokens survive the product rename.
    private static var service: String { ["com.kevin.OpenEagle.QA", "com.kevin.HunterFile.QA", "com.kevin.HunterFiles.QA"].contains(Bundle.main.bundleIdentifier ?? "") ? "com.kevin.OpenEagle.QA" : "com.kevin.OpenEagle" }
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LibraryError.message("无法将凭据保存在钥匙串。") }
        } else if status != errSecSuccess { throw LibraryError.message("无法更新钥匙串凭据。") }
    }
    static func apiToken() throws -> String {
        if let token = read("api-token") { return token }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LibraryError.message("无法创建采集令牌。") }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try write(token, account: "api-token")
        return token
    }
}

final class LocalAPI {
    typealias Handler = @MainActor (String, String, Data) async -> (Int, Data)
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.kevin.HunterFiles.api")
    private let token: String
    private let handler: Handler
    init(token: String, handler: @escaping Handler, onError: @escaping @MainActor (String) -> Void) throws {
        self.token = token; self.handler = handler
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 41596)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { state in if case .failed(let error) = state { Task { @MainActor in onError(error.localizedDescription) } } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
        }
        listener.start(queue: queue)
    }
    func stop() { listener.cancel() }
    deinit { listener.cancel() }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            var data = accumulated
            if let chunk { data.append(chunk) }
            guard data.count <= 16 * 1024 * 1024 else { self.reply(connection, status: 413, data: Self.json(["error": "请求过大"])); return }
            guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || error != nil || data.count > 32768 { connection.cancel() } else { self.receive(connection, accumulated: data) }
                return
            }
            let header = String(decoding: data[..<separator.lowerBound], as: UTF8.self)
            let lines = header.components(separatedBy: "\r\n")
            let first = (lines.first ?? "").split(separator: " ")
            guard first.count == 3 else { self.reply(connection, status: 400, data: Self.json(["error": "无效 HTTP 请求"])); return }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmed
            }
            guard headers["transfer-encoding"] == nil else { self.reply(connection, status: 400, data: Self.json(["error": "需要 Content-Length"])); return }
            guard let length = Int(headers["content-length"] ?? "0"), length >= 0, length <= 16 * 1024 * 1024 else { self.reply(connection, status: 413, data: Self.json(["error": "请求长度无效"])); return }
            guard data.count - separator.upperBound >= length else {
                if complete || error != nil { connection.cancel() } else { self.receive(connection, accumulated: data) }
                return
            }
            let method = String(first[0]), path = String(first[1])
            if method == "OPTIONS" { self.reply(connection, status: 200, data: Data()); return }
            if method == "GET" && path == "/health" { self.reply(connection, status: 200, data: Self.json(["application": "HunterFiles", "version": "1.0"])); return }
            guard Self.constantTimeEqual(headers["authorization"] ?? "", "Bearer " + self.token) else { self.reply(connection, status: 401, data: Self.json(["error": "需要有效的采集令牌"])); return }
            let body = data.subdata(in: separator.upperBound..<(separator.upperBound + length))
            Task { @MainActor in
                let (status, result) = await self.handler(method, path, body)
                self.reply(connection, status: status, data: result)
            }
        }
    }
    private func reply(_ connection: NWConnection, status: Int, data: Data) {
        let message = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 409: "Conflict", 413: "Payload Too Large", 500: "Internal Server Error"][status] ?? "OK"
        let header = "HTTP/1.1 \(status) \(message)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(data.count)\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }
    static func json(_ value: Any) -> Data { (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8) }
    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

extension AppStore {
    func configureAPI() {
        apiServer?.stop(); apiServer = nil
        guard UserDefaults.standard.bool(forKey: "apiEnabled") else { return }
        do {
            apiServer = try LocalAPI(token: Secrets.apiToken(), handler: { [weak self] method, path, body in
                guard let self else { return (500, LocalAPI.json(["error": "应用不可用"])) }
                return await self.handleAPI(method, path: path, body: body)
            }, onError: { [weak self] message in self?.error = "浏览器采集服务：\(message)" })
        } catch { self.error = error.localizedDescription }
    }
    private func handleAPI(_ method: String, path: String, body: Data) async -> (Int, Data) {
        guard let repository else { return (409, LocalAPI.json(["error": "请先打开资源库"])) }
        do {
            var components = URLComponents(string: "http://127.0.0.1" + path)
            // URLSearchParams and urllib encode query spaces as '+'. Preserve escaped literal plus signs.
            let query = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
            components?.percentEncodedQuery = query
            let route = components?.path ?? path
            if method == "GET" && route == "/items" {
                var filter = AssetFilter(); filter.query = components?.queryItems?.first { $0.name == "q" }?.value ?? ""
                if components?.queryItems?.contains(where: { $0.name == "semantic" && $0.value == "1" }) == true {
                    guard semanticEnabled, !filter.query.trimmed.isEmpty else { throw LibraryError.message("请启用本地 AI，并提供 q 查询。") }
                    let vector = try await localEmbedding().query(filter.query)
                    let result = try await repository.semanticResults(vector: vector, filter: filter)
                    guard self.repository === repository else { throw LibraryError.message("资源库已切换，请重试。") }
                    struct SemanticResult: Encodable { let total: Int; let items: [Asset]; let matches: [SemanticHit] }
                    return (200, try JSONEncoder().encode(SemanticResult(total: result.total, items: result.assets, matches: result.hits)))
                }
                let snapshot = try await repository.snapshot(filter: filter, limit: 500)
                struct Result: Encodable { let total: Int; let items: [Asset] }
                return (200, try JSONEncoder().encode(Result(total: snapshot.total, items: snapshot.assets)))
            }
            if method == "GET" && route == "/folders" { return (200, try JSONEncoder().encode(try await repository.allFolders())) }
            if method == "GET" && route == "/status" { return (200, LocalAPI.json(["busy": isBusy, "progress": progress, "message": notice, "errors": activityErrors])) }
            guard method == "POST", let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { return (404, LocalAPI.json(["error": "接口不存在"])) }
            if route == "/folders" {
                guard let name = payload["name"] as? String else { throw LibraryError.message("需要文件夹名称") }
                let folder = LibraryFolder(name: name, parentID: payload["parentID"] as? String)
                try await repository.saveFolder(folder); await refresh()
                return (200, try JSONEncoder().encode(folder))
            }
            if route == "/items/update" {
                guard let ids = payload["ids"] as? [String], !ids.isEmpty, ids.count <= 1000 else { throw LibraryError.message("ids 应包含 1–1000 个素材标识") }
                let name = payload["name"] as? String, note = payload["note"] as? String, tags = payload["tags"] as? [String], rating = payload["rating"] as? Int
                let old = try await repository.modify(ids: ids) { item in
                    if let name { item.name = name }
                    if let note { item.note = note }
                    if let tags { item.tags = Array(Set(item.tags + tags)).sorted() }
                    if let rating { item.rating = rating }
                }
                undoStack.append(old); redoStack = []; await refresh()
                return (200, LocalAPI.json(["updated": old.count]))
            }
            if route == "/collect" {
                guard !isBusy else { return (409, LocalAPI.json(["error": "应用正在处理其他任务，请稍后重试"])) }
                guard let entries = payload["items"] as? [[String: Any]], !entries.isEmpty, entries.count <= 500 else { throw LibraryError.message("每次采集需要 1–500 项") }
                let folderIDs = payload["folderIDs"] as? [String] ?? []
                let tags = payload["tags"] as? [String] ?? []
                isBusy = true; cancelRequested = false; progress = 0; activityErrors = []
                defer { isBusy = false }
                var ids: [String] = []
                for (index, entry) in entries.enumerated() {
                    if cancelRequested { activityErrors.append("剩余采集已取消"); break }
                    progress = Double(index) / Double(entries.count); progressTitle = "浏览器采集 \(index + 1)/\(entries.count)"
                    do {
                        let asset: Asset
                        if entry["download"] as? Bool == false {
                            asset = try await WebCollector.collect(entry["url"] as? String ?? "", name: entry["name"] as? String ?? "", download: false, into: repository, folders: folderIDs, tags: tags)
                        } else if let dataURL = entry["dataURL"] as? String, dataURL.hasPrefix("data:image/png;base64,"), let bytes = Data(base64Encoded: String(dataURL.dropFirst("data:image/png;base64,".count))) {
                            guard bytes.count < 12 * 1024 * 1024 else { throw LibraryError.message("截图超过 12 MB") }
                            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
                            defer { try? FileManager.default.removeItem(at: temp) }
                            try bytes.write(to: temp)
                            let result = try await repository.importFile(temp, folderIDs: folderIDs, tags: tags, sourceURL: entry["sourceURL"] as? String ?? "")
                            var imported = result.asset
                            if !result.duplicate {
                                let name = (entry["name"] as? String ?? "网页截图").safeFilename
                                imported.name = name
                                _ = try await repository.modify(ids: [imported.id]) { $0.name = name }
                            }
                            asset = imported
                        } else {
                            asset = try await WebCollector.collect(entry["url"] as? String ?? "", name: entry["name"] as? String ?? "", download: entry["download"] as? Bool ?? true, into: repository, folders: folderIDs, tags: tags)
                        }
                        await analyze(asset, in: repository)
                        if let source = entry["sourceURL"] as? String { _ = try await repository.modify(ids: [asset.id]) { $0.sourceURL = source } }
                        if entry["download"] as? Bool == false, let dataURL = entry["dataURL"] as? String, dataURL.hasPrefix("data:image/png;base64,"), let bytes = Data(base64Encoded: String(dataURL.dropFirst("data:image/png;base64,".count))), bytes.count < 12 * 1024 * 1024 {
                            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
                            defer { try? FileManager.default.removeItem(at: temp) }
                            try bytes.write(to: temp)
                            let info = await MediaService.shared.analyze(temp, kind: .image, thumbnail: repository.thumbnailURL(for: asset))
                            try await repository.updateAnalysis(id: asset.id, width: info.width, height: info.height, duration: 0, colors: info.colors)
                        }
                        ids.append(asset.id)
                    } catch { activityErrors.append(error.localizedDescription) }
                }
                notice = "浏览器已采集 \(ids.count) 项" + (activityErrors.isEmpty ? "" : "，\(activityErrors.count) 项未完成，请查看任务记录"); await refresh()
                return (200, LocalAPI.json(["ids": ids, "imported": ids.count, "errors": activityErrors]))
            }
            return (404, LocalAPI.json(["error": "接口不存在"]))
        } catch { return (400, LocalAPI.json(["error": error.localizedDescription])) }
    }
}
