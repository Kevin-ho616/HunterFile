import Foundation
import SQLite3

final class SQLite {
    private var handle: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开资源库"
            sqlite3_close(handle); handle = nil
            throw LibraryError.message(message)
        }
        sqlite3_busy_timeout(handle, 5000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = FULL")
        try execute("PRAGMA foreign_keys = ON")
    }
    deinit { sqlite3_close(handle) }
    func execute(_ sql: String, _ values: [String?] = [], blob: Data? = nil) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        if let blob {
            let status = blob.withUnsafeBytes { sqlite3_bind_blob(statement, Int32(values.count + 1), $0.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard status == SQLITE_OK else { throw error() }
        }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw error() }
    }
    func rows(_ sql: String, _ values: [String?] = []) throws -> [[String: String]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: String]] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                if let text = sqlite3_column_text(statement, column) { row[String(cString: sqlite3_column_name(statement, column))] = String(cString: text) }
            }
            rows.append(row)
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw error() }
        return rows
    }
    func scalar(_ sql: String, _ values: [String?] = []) throws -> Int {
        Int(try rows(sql, values).first?.values.first ?? "0") ?? 0
    }
    func forEachBlob(_ sql: String, _ values: [String?], _ visit: ([String: String], Data) throws -> Void) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            var row: [String: String] = [:], blob = Data()
            for column in 0..<sqlite3_column_count(statement) {
                if sqlite3_column_type(statement, column) == SQLITE_BLOB {
                    if let bytes = sqlite3_column_blob(statement, column) { blob = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column))) }
                } else if let text = sqlite3_column_text(statement, column) { row[String(cString: sqlite3_column_name(statement, column))] = String(cString: text) }
            }
            try visit(row, blob)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw error() }
    }
    func transaction<T>(_ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try operation(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func backup(to url: URL) throws {
        var destination: OpaquePointer?
        guard sqlite3_open(url.path, &destination) == SQLITE_OK else {
            sqlite3_close(destination); throw LibraryError.message("无法创建备份数据库")
        }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", handle, "main") else { throw error() }
        let status = sqlite3_backup_step(backup, -1)
        let final = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE && final == SQLITE_OK else { throw LibraryError.message("数据库备份失败，原资源库未修改") }
    }
    private func prepare(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        for (offset, value) in values.enumerated() {
            let status: Int32
            if let value { status = sqlite3_bind_text(statement, Int32(offset + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            else { status = sqlite3_bind_null(statement, Int32(offset + 1)) }
            if status != SQLITE_OK { sqlite3_finalize(statement); throw error() }
        }
        return statement
    }
    private func error() -> LibraryError { .message("资源库数据库：\(String(cString: sqlite3_errmsg(handle)))") }
}
