import Foundation
import UniformTypeIdentifiers

public enum AssetKind: String, Codable, CaseIterable, Sendable {
    case image, video, audio, document, font, bookmark, other
    public var title: String {
        switch self {
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        case .document: return "文档"
        case .font: return "字体"
        case .bookmark: return "书签"
        case .other: return "其他"
        }
    }
    public var symbol: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .document: return "doc.richtext"
        case .font: return "character.book.closed"
        case .bookmark: return "link"
        case .other: return "doc"
        }
    }
    public static func detect(_ ext: String) -> Self {
        let ext = ext.lowercased()
        if ["ttf", "otf", "ttc", "woff", "woff2"].contains(ext) { return .font }
        if ["webloc", "url"].contains(ext) { return .bookmark }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) || ["svg", "psd", "ai", "eps", "avif"].contains(ext) { return .image }
        if type.conforms(to: .movie) || ["mkv", "webm"].contains(ext) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) || type.conforms(to: .pdf) || ["pages", "key", "numbers", "docx", "pptx", "xlsx"].contains(ext) { return .document }
        return .other
    }
}

public struct Annotation: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var text: String
    public var date = Date()
    public init(x: Double, y: Double, width: Double, height: Double, text: String) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.text = text
    }
}

public struct Asset: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var name: String
    public var ext: String
    public var kind: AssetKind
    public var relativePath = ""
    public var byteCount: Int64 = 0
    public var width = 0
    public var height = 0
    public var duration: Double = 0
    public var hash = ""
    public var colors: [String] = []
    public var tags: [String] = []
    public var folderIDs: [String] = []
    public var rating = 0
    public var favorite = false
    public var note = ""
    public var sourceURL = ""
    public var extractedText = ""
    public var annotations: [Annotation] = []
    public var importedAt = Date()
    public var modifiedAt = Date()
    public var fileDate = Date()
    public var openedAt: Date?
    public var trashedAt: Date?
    public init(name: String, ext: String) {
        self.name = name; self.ext = ext.lowercased(); self.kind = .detect(ext)
    }
    public var filename: String { ext.isEmpty ? name : "\(name).\(ext)" }
    public var dimensions: String { width > 0 ? "\(width) × \(height)" : "—" }
    public var searchable: String {
        ([name, ext, note, sourceURL, extractedText] + tags + annotations.map(\.text)).joined(separator: " ").searchFolded
    }
}

public struct LibraryFolder: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var name: String
    public var parentID: String?
    public var sortOrder: Int?
    public var color = "#6E83E8"
    public var icon: String?
    public var autoTags: [String] = []
    public var note = ""
    public var createdAt = Date()
    public var password: PasswordDigest?
    public init(name: String, parentID: String? = nil) { self.name = name; self.parentID = parentID }
}

public enum LibraryScope: Hashable, Sendable {
    case all, uncategorized, untagged, favorites, recent, trash, duplicates, random
    case folder(String), tag(String), smart(String), kind(AssetKind)
}

public enum AssetSortOrder: String, Codable, CaseIterable, Sendable {
    case newest, oldest, name, modified, size, rating, random
    public var title: String {
        switch self {
        case .newest: return "添加时间 · 最新优先"
        case .oldest: return "添加时间 · 最早优先"
        case .name: return "名称 · A → Z"
        case .modified: return "最近修改"
        case .size: return "文件大小"
        case .rating: return "星级评分"
        case .random: return "随机排列"
        }
    }
    var sql: String {
        switch self {
        case .newest: return "imported DESC, id"
        case .oldest: return "imported ASC, id"
        case .name: return "name COLLATE NOCASE ASC, id"
        case .modified: return "modified DESC, id"
        case .size: return "bytes DESC, id"
        case .rating: return "rating DESC, imported DESC, id"
        case .random: return "random()"
        }
    }
}

public struct AssetFilter: Codable, Equatable, Sendable {
    public var query = ""
    public var kind: AssetKind?
    public var ext = ""
    public var tag = ""
    public var minRating = 0
    public var color = ""
    public var shape = ""
    public var minWidth = 0
    public var minHeight = 0
    public var minBytes: Int64 = 0
    public var maxBytes: Int64 = 0
    public var days = 0
    public init() {}
    public var isEmpty: Bool { self == AssetFilter() }
}

public struct SmartFolder: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var name: String
    public var filters: [AssetFilter]
    public var matchAll: Bool
    public init(name: String, filters: [AssetFilter], matchAll: Bool = true) {
        self.name = name; self.filters = filters; self.matchAll = matchAll
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name && lhs.filters == rhs.filters && lhs.matchAll == rhs.matchAll }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct LibrarySnapshot: Sendable {
    public var assets: [Asset]
    public var total: Int
    public var folders: [LibraryFolder]
    public var smartFolders: [SmartFolder]
    public var tags: [String: Int]
    public var counts: [String: Int]
    public var folderCounts: [String: Int]
    public var totalBytes: Int64
}

public struct ImportResult: Sendable {
    public var asset: Asset
    public var duplicate: Bool
}

public enum LibraryError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let value): return value } }
}

public extension String {
    var searchFolded: String { folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var safeFilename: String {
        let value = components(separatedBy: CharacterSet(charactersIn: "/\\:\0\n\r")).joined(separator: "_").trimmed
        return value.isEmpty || value == "." || value == ".." ? "Untitled" : String(value.prefix(180))
    }
    var tagsFromText: [String] {
        Array(Set(components(separatedBy: CharacterSet(charactersIn: ",，;；\n")).map(\.trimmed).filter { !$0.isEmpty })).sorted()
    }
}
