import Foundation

public struct SkillsManifest: Equatable, Sendable {
    public let files: [String: String]

    public init(files: [String: String]) {
        self.files = files
    }

    /// Hermes keeps its own usage, hub, curator, archive, and Finder metadata
    /// beneath the skills root. That housekeeping is not active skill content
    /// and must not turn an ordinary skill invocation into integrity drift.
    public static func tracks(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = components.first, first.first != "." else { return false }
        return components.last != ".DS_Store"
    }

    public var activeSkillContent: SkillsManifest {
        SkillsManifest(files: files.filter { Self.tracks(relativePath: $0.key) })
    }

    public static func load(
        from root: URL,
        fileManager: FileManager = .default
    ) -> SkillsManifestLoadResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return .unavailable("The skills directory is missing.")
        }
        guard isDirectory.boolValue else {
            return .unavailable("The skills path exists but is not a directory.")
        }

        var walkError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [],
            errorHandler: { _, error in
                walkError = error
                return false
            }
        ) else {
            return .unavailable("The skills directory is unreadable.")
        }

        var files: [String: String] = [:]
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in enumerator {
            if let walkError {
                return .unavailable("The skills directory is unreadable: \(walkError.localizedDescription)")
            }
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isRegularFileKey])
            } catch {
                return .unavailable("A skill file could not be inspected: \(relativePath(url, rootPath: rootPath))")
            }
            guard values.isRegularFile == true else { continue }
            let relative = relativePath(url, rootPath: rootPath)
            guard !relative.isEmpty, SkillsManifest.tracks(relativePath: relative) else { continue }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                return .unavailable("A skill file could not be read: \(relative)")
            }
            files[relative] = ApprovalStore.sha256(data)
        }
        if let walkError {
            return .unavailable("The skills directory is unreadable: \(walkError.localizedDescription)")
        }
        return .success(SkillsManifest(files: files))
    }

    private static func relativePath(_ url: URL, rootPath: String) -> String {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        let dropped = path.dropFirst(rootPath.count)
        if dropped.hasPrefix("/") {
            return String(dropped.dropFirst())
        }
        return String(dropped)
    }
}

public enum SkillsManifestLoadResult: Equatable, Sendable {
    case success(SkillsManifest)
    case unavailable(String)
}

public struct SkillsDrift: Equatable, Sendable {
    public let added: [String]
    public let changed: [String]
    public let removed: [String]

    public static let clean = SkillsDrift(added: [], changed: [], removed: [])

    public init(added: [String], changed: [String], removed: [String]) {
        self.added = added
        self.changed = changed
        self.removed = removed
    }

    public var totalCount: Int { added.count + changed.count + removed.count }
    public var isClean: Bool { totalCount == 0 }

    public static func comparing(baseline: SkillsManifest, current: SkillsManifest) -> SkillsDrift {
        let normalizedBaseline = baseline.activeSkillContent
        let normalizedCurrent = current.activeSkillContent
        let baselineKeys = Set(normalizedBaseline.files.keys)
        let currentKeys = Set(normalizedCurrent.files.keys)
        let added = currentKeys.subtracting(baselineKeys).sorted()
        let removed = baselineKeys.subtracting(currentKeys).sorted()
        let changed = baselineKeys.intersection(currentKeys)
            .filter { normalizedBaseline.files[$0] != normalizedCurrent.files[$0] }
            .sorted()
        return SkillsDrift(added: added, changed: changed, removed: removed)
    }
}

public enum SkillsIntegrityState: Equatable, Sendable {
    case baselineNotRecorded
    case clean
    case drifted(SkillsDrift)
    case unavailable(String)

    public static func make(
        baseline: SkillsBaseline?,
        current: SkillsManifestLoadResult
    ) -> SkillsIntegrityState {
        switch current {
        case let .unavailable(message):
            return .unavailable(message)
        case let .success(manifest):
            guard let baseline else { return .baselineNotRecorded }
            let drift = SkillsDrift.comparing(baseline: baseline.manifest, current: manifest)
            return drift.isClean ? .clean : .drifted(drift)
        }
    }

    public var displayText: String {
        switch self {
        case .baselineNotRecorded:
            return "Skills integrity — baseline not recorded"
        case .clean:
            return "Skills integrity — matches recorded baseline"
        case let .drifted(drift):
            let count = drift.totalCount
            return "Skills integrity — \(count) file\(count == 1 ? "" : "s") differ"
        case .unavailable:
            return "Skills integrity — unavailable"
        }
    }

    public var isClean: Bool {
        if case .clean = self { return true }
        return false
    }

    public var needsAttention: Bool {
        switch self {
        case .drifted, .unavailable:
            return true
        case .baselineNotRecorded, .clean:
            return false
        }
    }

    public var drift: SkillsDrift? {
        if case let .drifted(drift) = self { return drift }
        return nil
    }

    public var unavailableMessage: String? {
        if case let .unavailable(message) = self { return message }
        return nil
    }

    public var attentionFingerprint: String {
        switch self {
        case .baselineNotRecorded:
            return "integrity:none"
        case .clean:
            return "integrity:clean"
        case let .drifted(drift):
            return "integrity:drift:added=\(drift.added.joined(separator: ","))+changed=\(drift.changed.joined(separator: ","))+removed=\(drift.removed.joined(separator: ","))"
        case let .unavailable(message):
            return "integrity:unavailable:\(message)"
        }
    }
}
