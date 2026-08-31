import Foundation

public struct SkillsBaseline: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let rootPath: String
    public let recordedAt: Date
    public let files: [String: String]

    public var manifest: SkillsManifest {
        SkillsManifest(files: files)
    }
}

public final class SkillsIntegrityStore: @unchecked Sendable {
    public let stateDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(stateDirectory: URL, fileManager: FileManager = .default) {
        self.stateDirectory = stateDirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> SkillsBaseline? {
        let url = baselineURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(SkillsBaseline.self, from: Data(contentsOf: url))
    }

    @discardableResult
    public func record(
        rootURL: URL,
        manifest: SkillsManifest,
        at date: Date = Date()
    ) throws -> SkillsBaseline {
        try prepareStateDirectory()
        let baseline = SkillsBaseline(
            formatVersion: 1,
            rootPath: rootURL.standardizedFileURL.path,
            recordedAt: date,
            files: manifest.files
        )
        let data = try encoder.encode(baseline)
        try data.write(to: baselineURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: baselineURL.path)
        return baseline
    }

    private var baselineURL: URL {
        stateDirectory.appendingPathComponent("skills-baseline.json")
    }

    private func prepareStateDirectory() throws {
        try fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stateDirectory.path)
    }
}
