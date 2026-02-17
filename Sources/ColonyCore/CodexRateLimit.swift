import Foundation

public struct CodexRateLimits: Codable, Sendable {
    public struct Window: Codable, Sendable {
        public let usedPercent: Double?
        public let windowMinutes: Int?
        public let resetsAt: Int?
    }

    public struct Credits: Codable, Sendable {
        public let hasCredits: Bool?
        public let unlimited: Bool?
        public let balance: Double?
    }

    public let limitId: String?
    public let limitName: String?
    public let primary: Window?
    public let secondary: Window?
    public let credits: Credits?
    public let planType: String?
}

public struct CodexRateLimitSnapshot: Sendable {
    public let timestamp: Date?
    public let sourceFile: String
    public let rateLimits: CodexRateLimits

    public init(timestamp: Date?, sourceFile: String, rateLimits: CodexRateLimits) {
        self.timestamp = timestamp
        self.sourceFile = sourceFile
        self.rateLimits = rateLimits
    }
}

public enum CodexRateLimitError: Error, CustomStringConvertible {
    case sessionsDirNotFound(String)
    case noRateLimitFound

    public var description: String {
        switch self {
        case let .sessionsDirNotFound(path):
            return "Codex sessions directory not found: \(path)"
        case .noRateLimitFound:
            return "No codex rate limit info found in recent Codex sessions."
        }
    }
}

public struct CodexRateLimitReader {
    private struct RolloutLine: Codable {
        let timestamp: String?
        let payload: Payload?

        struct Payload: Codable {
            let type: String?
            let rateLimits: CodexRateLimits?
        }
    }

    public init() {}

    public func latestCodexRateLimit(sessionsDir: URL? = nil) throws -> CodexRateLimitSnapshot {
        let dir = sessionsDir ?? Self.defaultSessionsDir()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw CodexRateLimitError.sessionsDirNotFound(dir.path)
        }

        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let fm = FileManager.default

        var candidates: [(url: URL, mtime: Date)] = []
        if let e = fm.enumerator(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
            for case let url as URL in e {
                if url.pathExtension != "jsonl" { continue }
                if !url.lastPathComponent.hasPrefix("rollout-") { continue }
                guard let rv = try? url.resourceValues(forKeys: keys) else { continue }
                guard rv.isRegularFile == true else { continue }
                candidates.append((url, rv.contentModificationDate ?? .distantPast))
            }
        }

        candidates.sort { $0.mtime > $1.mtime }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tsParser = ISO8601DateFormatter()
        tsParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tsParserNoFrac = ISO8601DateFormatter()
        tsParserNoFrac.formatOptions = [.withInternetDateTime]

        for (url, _) in candidates.prefix(80) {
            if let snap = try Self.lastRateLimitInFile(url: url, decoder: decoder, tsParser: tsParser, tsParserNoFrac: tsParserNoFrac) {
                // Prefer codex limits if multiple kinds exist.
                if snap.rateLimits.limitId == nil || snap.rateLimits.limitId == "codex" {
                    return snap
                }
            }
        }

        throw CodexRateLimitError.noRateLimitFound
    }

    private static func lastRateLimitInFile(
        url: URL,
        decoder: JSONDecoder,
        tsParser: ISO8601DateFormatter,
        tsParserNoFrac: ISO8601DateFormatter
    ) throws -> CodexRateLimitSnapshot? {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        // Scan from the end: the last token_count event contains the latest rate limits.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for raw in lines.reversed() {
            // Fast path: avoid decoding most lines.
            if !raw.contains("\"rate_limits\"") { continue }
            if !raw.contains("\"type\":\"token_count\"") { continue }

            guard let lineData = raw.data(using: .utf8) else { continue }
            guard let obj = try? decoder.decode(RolloutLine.self, from: lineData) else { continue }
            guard obj.payload?.type == "token_count" else { continue }
            guard let rl = obj.payload?.rateLimits else { continue }

            let ts = obj.timestamp.flatMap { tsParser.date(from: $0) ?? tsParserNoFrac.date(from: $0) }
            return CodexRateLimitSnapshot(timestamp: ts, sourceFile: url.path, rateLimits: rl)
        }
        return nil
    }

    private static func defaultSessionsDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }
}
