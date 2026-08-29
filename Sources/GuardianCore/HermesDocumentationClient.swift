import Foundation

public enum DocumentationOrigin: String, Codable, Sendable {
    case installed
    case hosted

    public var label: String {
        switch self {
        case .installed: return "Installed Hermes documentation"
        case .hosted: return "Current hosted Hermes documentation"
        }
    }
}

public struct DocumentationExcerpt: Identifiable, Equatable, Sendable {
    public let settingPath: String
    public let text: String
    public let sourceURL: URL
    public let origin: DocumentationOrigin

    public var id: String { "\(origin.rawValue):\(settingPath):\(sourceURL.absoluteString)" }

    public init(settingPath: String, text: String, sourceURL: URL, origin: DocumentationOrigin) {
        self.settingPath = settingPath
        self.text = text
        self.sourceURL = sourceURL
        self.origin = origin
    }
}

public enum DocumentationAgreement: String, Sendable {
    case matching
    case different
    case installedOnly
    case hostedOnly
    case unavailable

    public var message: String {
        switch self {
        case .matching:
            return "Installed and hosted Hermes documentation agree."
        case .different:
            return "Installed and hosted Hermes documentation differ. Both sources are shown."
        case .installedOnly:
            return "Grounded in the documentation installed with this Hermes build."
        case .hostedOnly:
            return "Grounded in the current hosted Hermes documentation; no matching installed passage was found."
        case .unavailable:
            return "No exact documentation passage was found for this setting."
        }
    }
}

public struct DocumentationLookupResult: Sendable {
    public let excerpts: [DocumentationExcerpt]
    public let agreement: DocumentationAgreement
    public let warning: String?

    public init(excerpts: [DocumentationExcerpt], agreement: DocumentationAgreement, warning: String? = nil) {
        self.excerpts = excerpts
        self.agreement = agreement
        self.warning = warning
    }
}

public enum DocumentationError: LocalizedError {
    case unexpectedResponse
    case corpusTooLarge
    case invalidText

    public var errorDescription: String? {
        switch self {
        case .unexpectedResponse: return "The Hermes documentation server returned an unexpected response."
        case .corpusTooLarge: return "The hosted documentation exceeded Guardian's 10 MB safety limit."
        case .invalidText: return "The hosted documentation was not valid UTF-8 text."
        }
    }
}

private struct DocumentationCacheMetadata: Codable {
    var etag: String?
    var lastModified: String?
    var lastCheckedAt: Date
}

public actor HermesDocumentationClient {
    public static let hostedCorpusURL = URL(string: "https://hermes-agent.nousresearch.com/docs/llms-full.txt")!

    private let cacheDirectory: URL
    private let installedDocsDirectory: URL?
    private let hostedCorpusURL: URL
    private let refreshInterval: TimeInterval
    private let session: URLSession
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        cacheDirectory: URL,
        installedDocsDirectory: URL?,
        hostedCorpusURL: URL = HermesDocumentationClient.hostedCorpusURL,
        refreshInterval: TimeInterval = 6 * 60 * 60,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.cacheDirectory = cacheDirectory
        self.installedDocsDirectory = installedDocsDirectory
        self.hostedCorpusURL = hostedCorpusURL
        self.refreshInterval = refreshInterval
        self.session = session
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func lookup(settingPaths: [String], forceRefresh: Bool = false) async -> DocumentationLookupResult {
        let uniquePaths = Array(Set(settingPaths)).sorted()
        let installed = findInstalledExcerpts(for: uniquePaths)
        var hosted: [DocumentationExcerpt] = []
        var warning: String?

        do {
            if let corpus = try await loadHostedCorpus(forceRefresh: forceRefresh) {
                hosted = DocumentationExcerptExtractor.hostedExcerpts(
                    for: uniquePaths,
                    corpus: corpus,
                    canonicalBaseURL: URL(string: "https://hermes-agent.nousresearch.com/docs/")!
                )
            }
        } catch {
            warning = "Hosted documentation refresh failed; Guardian used available local or cached evidence. \(error.localizedDescription)"
        }

        let excerpts = merge(installed: installed, hosted: hosted)
        return DocumentationLookupResult(
            excerpts: excerpts,
            agreement: agreement(installed: installed, hosted: hosted),
            warning: warning
        )
    }

    private func findInstalledExcerpts(for paths: [String]) -> [DocumentationExcerpt] {
        guard let installedDocsDirectory,
              fileManager.fileExists(atPath: installedDocsDirectory.path),
              let enumerator = fileManager.enumerator(
                at: installedDocsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [] }

        var best: [String: (score: Int, excerpt: DocumentationExcerpt)] = [:]
        var inspectedFiles = 0

        for case let fileURL as URL in enumerator {
            guard inspectedFiles < 1_000 else { break }
            guard ["md", "mdx"].contains(fileURL.pathExtension.lowercased()) else { continue }
            inspectedFiles += 1
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) <= 2_000_000,
                  let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let relative = fileURL.path.replacingOccurrences(of: installedDocsDirectory.path + "/", with: "")
            let sourceURL = canonicalURL(forRelativeDocumentationPath: relative)
            for path in paths {
                guard let candidate = DocumentationExcerptExtractor.bestExcerpt(for: path, in: text) else { continue }
                let excerpt = DocumentationExcerpt(
                    settingPath: path,
                    text: candidate.text,
                    sourceURL: sourceURL,
                    origin: .installed
                )
                if candidate.score > (best[path]?.score ?? Int.min) {
                    best[path] = (candidate.score, excerpt)
                }
            }
        }
        return paths.compactMap { best[$0]?.excerpt }
    }

    private func loadHostedCorpus(forceRefresh: Bool) async throws -> String? {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheDirectory.path)

        let corpusURL = cacheDirectory.appendingPathComponent("llms-full.txt")
        let metadataURL = cacheDirectory.appendingPathComponent("llms-full-metadata.json")
        var metadata = loadMetadata(from: metadataURL)

        if !forceRefresh,
           fileManager.fileExists(atPath: corpusURL.path),
           let checked = metadata?.lastCheckedAt,
           Date().timeIntervalSince(checked) < refreshInterval {
            return try readCorpus(at: corpusURL)
        }

        var request = URLRequest(url: hostedCorpusURL)
        request.timeoutInterval = 20
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.setValue("HermesConfigGuardian/0.1", forHTTPHeaderField: "User-Agent")
        if let etag = metadata?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = metadata?.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DocumentationError.unexpectedResponse }
            if http.statusCode == 304, fileManager.fileExists(atPath: corpusURL.path) {
                metadata?.lastCheckedAt = Date()
                if let metadata { try writeMetadata(metadata, to: metadataURL) }
                return try readCorpus(at: corpusURL)
            }
            guard http.statusCode == 200 else { throw DocumentationError.unexpectedResponse }
            guard data.count <= 10_000_000 else { throw DocumentationError.corpusTooLarge }
            guard String(data: data, encoding: .utf8) != nil else { throw DocumentationError.invalidText }

            try data.write(to: corpusURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: corpusURL.path)
            let updated = DocumentationCacheMetadata(
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                lastCheckedAt: Date()
            )
            try writeMetadata(updated, to: metadataURL)
            return String(decoding: data, as: UTF8.self)
        } catch {
            if fileManager.fileExists(atPath: corpusURL.path) {
                return try readCorpus(at: corpusURL)
            }
            throw error
        }
    }

    private func readCorpus(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= 10_000_000 else { throw DocumentationError.corpusTooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw DocumentationError.invalidText }
        return text
    }

    private func loadMetadata(from url: URL) -> DocumentationCacheMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(DocumentationCacheMetadata.self, from: data)
    }

    private func writeMetadata(_ metadata: DocumentationCacheMetadata, to url: URL) throws {
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func canonicalURL(forRelativeDocumentationPath relative: String) -> URL {
        var path = relative
        if path.hasSuffix(".mdx") { path.removeLast(4) }
        else if path.hasSuffix(".md") { path.removeLast(3) }
        if path.hasSuffix("/index") { path.removeLast("/index".count) }
        return URL(string: "https://hermes-agent.nousresearch.com/docs/\(path)")!
    }

    private func merge(installed: [DocumentationExcerpt], hosted: [DocumentationExcerpt]) -> [DocumentationExcerpt] {
        var result: [DocumentationExcerpt] = []
        for excerpt in installed + hosted {
            let duplicate = result.contains {
                $0.settingPath == excerpt.settingPath &&
                DocumentationExcerptExtractor.normalized($0.text) == DocumentationExcerptExtractor.normalized(excerpt.text)
            }
            if !duplicate { result.append(excerpt) }
        }
        return result
    }

    private func agreement(installed: [DocumentationExcerpt], hosted: [DocumentationExcerpt]) -> DocumentationAgreement {
        guard !installed.isEmpty || !hosted.isEmpty else { return .unavailable }
        guard !installed.isEmpty else { return .hostedOnly }
        guard !hosted.isEmpty else { return .installedOnly }

        for local in installed {
            guard let remote = hosted.first(where: { $0.settingPath == local.settingPath }) else { return .different }
            if DocumentationExcerptExtractor.normalized(local.text) != DocumentationExcerptExtractor.normalized(remote.text) {
                return .different
            }
        }
        return .matching
    }
}

public enum DocumentationExcerptExtractor {
    public struct Candidate: Equatable, Sendable {
        public let text: String
        public let score: Int
    }

    public static func bestExcerpt(for settingPath: String, in document: String) -> Candidate? {
        let leaf = settingPath.split(separator: ".").last.map(String.init) ?? settingPath
        let lines = document.components(separatedBy: .newlines)
        var best: Candidate?

        for index in lines.indices {
            let line = lines[index]
            guard line.localizedCaseInsensitiveContains(leaf) || line.localizedCaseInsensitiveContains(settingPath) else { continue }
            let score = scoreLine(line, leaf: leaf, fullPath: settingPath)
            guard score > 0 else { continue }
            let text = boundedParagraph(around: index, lines: lines)
            let candidate = Candidate(text: sanitize(text), score: score)
            if !candidate.text.isEmpty, candidate.score > (best?.score ?? Int.min) { best = candidate }
        }
        return best
    }

    public static func hostedExcerpts(
        for settingPaths: [String],
        corpus: String,
        canonicalBaseURL: URL
    ) -> [DocumentationExcerpt] {
        let lines = corpus.components(separatedBy: .newlines)
        var currentSource: String?
        var best: [String: (score: Int, excerpt: DocumentationExcerpt)] = [:]

        for index in lines.indices {
            let line = lines[index]
            if let source = sourcePath(fromMarker: line) {
                currentSource = source
                continue
            }
            for path in settingPaths {
                let leaf = path.split(separator: ".").last.map(String.init) ?? path
                guard line.localizedCaseInsensitiveContains(leaf) || line.localizedCaseInsensitiveContains(path) else { continue }
                let score = scoreLine(line, leaf: leaf, fullPath: path)
                guard score > 0 else { continue }
                let text = sanitize(boundedParagraph(around: index, lines: lines))
                guard !text.isEmpty else { continue }
                let url = canonicalURL(forSourcePath: currentSource, base: canonicalBaseURL)
                let excerpt = DocumentationExcerpt(settingPath: path, text: text, sourceURL: url, origin: .hosted)
                if score > (best[path]?.score ?? Int.min) { best[path] = (score, excerpt) }
            }
        }
        return settingPaths.compactMap { best[$0]?.excerpt }
    }

    public static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func scoreLine(_ line: String, leaf: String, fullPath: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("`\(leaf)` is") || trimmed.hasPrefix("`\(leaf)` ") { return 120 }
        if trimmed.hasPrefix("| `\(leaf)` |") { return 100 }
        if trimmed.localizedCaseInsensitiveContains(fullPath) { return 80 }
        if trimmed.localizedCaseInsensitiveContains("`\(leaf)`") { return 60 }
        return 20
    }

    private static func boundedParagraph(around index: Int, lines: [String]) -> String {
        if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            return lines[index]
        }
        var start = index
        var end = index
        while start > 0, index - start < 3, !lines[start - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            start -= 1
        }
        while end + 1 < lines.count, end - index < 8, !lines[end + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            end += 1
        }
        return lines[start...end].joined(separator: "\n")
    }

    private static func sanitize(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("<!--") && !trimmed.hasPrefix(":::")
            }
        var result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > 3_500 { result = String(result.prefix(3_500)) + "…" }
        return result
    }

    private static func sourcePath(fromMarker line: String) -> String? {
        let prefix = "<!-- source: "
        guard line.hasPrefix(prefix), line.hasSuffix(" -->") else { return nil }
        return String(line.dropFirst(prefix.count).dropLast(4))
    }

    private static func canonicalURL(forSourcePath source: String?, base: URL) -> URL {
        guard var source else { return HermesDocumentationClient.hostedCorpusURL }
        source = source.replacingOccurrences(of: "website/docs/", with: "")
        if source.hasSuffix(".mdx") { source.removeLast(4) }
        else if source.hasSuffix(".md") { source.removeLast(3) }
        if source.hasSuffix("/index") { source.removeLast("/index".count) }
        return base.appendingPathComponent(source)
    }
}
