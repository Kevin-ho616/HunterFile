import Foundation
import CommonCrypto
import Security

public struct PasswordDigest: Codable, Hashable, Sendable {
    public let salt: Data
    public let digest: Data
    public let rounds: UInt32
    public static func create(_ password: String) throws -> Self {
        guard password.count >= 6 else { throw LibraryError.message("文件夹密码至少需要 6 个字符。") }
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LibraryError.message("无法生成密码盐。") }
        let salt = Data(bytes), rounds: UInt32 = 200_000
        return Self(salt: salt, digest: try derive(password, salt: salt, rounds: rounds), rounds: rounds)
    }
    public func verifies(_ password: String) throws -> Bool {
        guard rounds >= 100_000 && rounds <= 2_000_000, salt.count == 16, digest.count == 32 else { return false }
        let value = try Self.derive(password, salt: salt, rounds: rounds)
        return zip(value, digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private static func derive(_ password: String, salt: Data, rounds: UInt32) throws -> Data {
        var output = [UInt8](repeating: 0, count: 32)
        let status = password.withCString { text in
            salt.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), text, password.utf8.count, salt.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &output, output.count)
            }
        }
        guard status == kCCSuccess else { throw LibraryError.message("密码处理失败。") }
        return Data(output)
    }
}

extension LibraryRepository {
    func inaccessibleIDs(in folders: [LibraryFolder]) -> Set<String> {
        var ids: Set<String> = []
        for folder in folders where folder.password != nil && !unlockedFolders.contains(folder.id) { ids.formUnion(descendants(folder.id, in: folders)) }
        return ids
    }
    func visibility(in folders: [LibraryFolder]) -> (String, [String?]) {
        let ids = inaccessibleIDs(in: folders).sorted()
        guard !ids.isEmpty else { return ("1", []) }
        return ("NOT EXISTS (SELECT 1 FROM json_each(assets.data,'$.folderIDs') WHERE value IN (\(ids.map { _ in "?" }.joined(separator: ","))))", ids)
    }
    public func lockedAncestor(of id: String) throws -> LibraryFolder? {
        let folders = try allFolders()
        var next: String? = id, visited: Set<String> = [], locked: LibraryFolder?
        while let current = next, visited.insert(current).inserted, let folder = folders.first(where: { $0.id == current }) {
            if folder.password != nil && !unlockedFolders.contains(folder.id) { locked = folder }
            next = folder.parentID
        }
        return locked
    }
    public func unlockFolder(id: String, password: String) throws {
        guard let folder = try allFolders().first(where: { $0.id == id }), let digest = folder.password else { return }
        guard try digest.verifies(password) else { throw LibraryError.message("密码不正确。") }
        unlockedFolders.insert(id)
    }
    public func lockFolder(id: String) throws {
        let ids = descendants(id, in: try allFolders())
        unlockedFolders.subtract(ids)
    }
}
