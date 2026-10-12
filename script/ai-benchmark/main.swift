import Foundation
import Darwin
import HunterFilesCore

struct Fixtures: Decodable {
    struct Media: Decodable { var file: String; var kind: String }
    struct Query: Decodable {
        var query: String; var kind: String; var expected: String
        var page: Int?; var secondsStart: Double?; var secondsEnd: Double?
        var anyDocument: Bool?; var alsoExpected: [String]?
    }
    var controlled: Bool; var assets: [Media]; var queries: [Query]
}
struct Indexed {
    var file: String; var kind: String; var chunk: SemanticChunk
}
struct Ranked: Codable {
    var file: String; var score: Float; var page: Int?; var seconds: Double?
}
struct QueryResult: Codable {
    var query: String; var kind: String; var expected: String; var expectedPage: Int?
    var expectedSecondsStart: Double?; var expectedSecondsEnd: Double?
    var rank: Int?; var locationHit: Bool; var seconds: Double; var top: [Ranked]
}
struct Metrics: Codable {
    var queries: Int; var top1: Int; var top10: Int; var locationHits: Int; var mrr: Double
}
struct Report: Codable {
    var controlled: Bool; var generatedAt: Date; var modelRevision: String; var modelSHA256: String
    var indexVersion: String; var backend: String; var files: Int; var chunks: Int
    var initializeSeconds: Double; var indexSeconds: Double; var queryMedianSeconds: Double
    var queryP95Seconds: Double; var peakRSSBytes: Int64
    var metrics: [String: Metrics]; var results: [QueryResult]
}

@main struct Benchmark {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 5, ["cpu", "gpu"].contains(args[3]) else {
            throw LibraryError.message("Usage: swift run HunterFilesAIBenchmark MODEL.litertlm FIXTURE_DIR cpu|gpu REPORT.json")
        }
        let root = URL(fileURLWithPath: args[2], isDirectory: true)
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        guard fixtures.controlled, fixtures.queries.count == 50 else { throw LibraryError.message("Expected 50 controlled fixture queries.") }
        var start = Date()
        let engine = try LocalEmbedding(modelURL: URL(fileURLWithPath: args[1]), useGPU: args[3] == "gpu")
        let initializeSeconds = Date().timeIntervalSince(start)
        print("Initialized \(args[3]): \(initializeSeconds)s"); fflush(stdout)
        var indexed: [Indexed] = []
        start = Date()
        for media in fixtures.assets {
            let url = root.appendingPathComponent(media.file).standardizedFileURL
            guard url.path.hasPrefix(root.standardizedFileURL.path + "/"), let kind = AssetKind(rawValue: media.kind) else { throw LibraryError.message("Invalid fixture path or kind.") }
            let chunks = try await engine.chunks(at: url, kind: kind, title: media.file)
            indexed += chunks.map { Indexed(file: media.file, kind: media.kind, chunk: $0) }
            print("Indexed \(media.file): \(chunks.count) chunks"); fflush(stdout)
        }
        let indexSeconds = Date().timeIntervalSince(start)
        var results: [QueryResult] = []
        for query in fixtures.queries {
            start = Date()
            let vector = try await engine.query(query.query)
            let candidates = indexed.filter { query.kind == "all" || $0.kind == query.kind }
            var byFile: [String: Ranked] = [:]
            for entry in candidates {
                let score = zip(vector, entry.chunk.vector).reduce(Float(0)) { $0 + $1.0 * $1.1 }
                if byFile[entry.file].map({ $0.score >= score }) != true {
                    byFile[entry.file] = Ranked(file: entry.file, score: score, page: entry.chunk.page, seconds: entry.chunk.seconds)
                }
            }
            let ranking = byFile.values.sorted { $0.score == $1.score ? $0.file < $1.file : $0.score > $1.score }
            let relevant = Set([query.expected] + (query.alsoExpected ?? []))
            let rank = ranking.firstIndex { query.anyDocument == true || relevant.contains($0.file) }.map { $0 + 1 }
            let first = ranking.first
            var locationHit = rank == 1
            if let page = query.page { locationHit = locationHit && first?.page == page }
            if let low = query.secondsStart, let high = query.secondsEnd {
                locationHit = locationHit && first?.seconds.map { $0 >= low && $0 < high } == true
            }
            let elapsed = Date().timeIntervalSince(start)
            results.append(QueryResult(query: query.query, kind: query.kind, expected: query.expected, expectedPage: query.page, expectedSecondsStart: query.secondsStart, expectedSecondsEnd: query.secondsEnd, rank: rank, locationHit: locationHit, seconds: elapsed, top: Array(ranking.prefix(10))))
            print("Query \(results.count)/50: rank \(rank.map(String.init) ?? "none"), location \(locationHit)"); fflush(stdout)
        }
        func metrics(_ values: [QueryResult]) -> Metrics {
            Metrics(queries: values.count, top1: values.filter { $0.rank == 1 }.count, top10: values.filter { ($0.rank ?? Int.max) <= 10 }.count, locationHits: values.filter(\.locationHit).count, mrr: values.reduce(0) { $0 + ($1.rank.map { 1 / Double($0) } ?? 0) } / Double(max(1, values.count)))
        }
        var allMetrics = ["all": metrics(results)]
        for kind in ["image", "document", "video"] { allMetrics[kind] = metrics(results.filter { $0.kind == kind }) }
        let times = results.map(\.seconds).sorted()
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let report = Report(controlled: true, generatedAt: Date(), modelRevision: LocalEmbedding.modelRevision, modelSHA256: LocalEmbedding.modelSHA256, indexVersion: LocalEmbedding.indexVersion, backend: args[3], files: fixtures.assets.count, chunks: indexed.count, initializeSeconds: initializeSeconds, indexSeconds: indexSeconds, queryMedianSeconds: times[times.count / 2], queryP95Seconds: times[Int(Double(times.count - 1) * 0.95)], peakRSSBytes: Int64(usage.ru_maxrss), metrics: allMetrics, results: results)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        assert(indexed.allSatisfy { $0.chunk.vector.count == 768 && $0.chunk.vector.allSatisfy(\.isFinite) })
        print("Saved report: \(args[4]); top1 \(allMetrics["all"]!.top1)/50, location \(allMetrics["all"]!.locationHits)/50")
    }
}
