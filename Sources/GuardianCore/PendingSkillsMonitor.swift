import Foundation

public enum PendingSkillsState: Equatable, Sendable {
    case none
    case awaitingReview(Int)
    case unavailable(String)

    public var displayText: String {
        switch self {
        case .none:
            return "Pending skills — none"
        case let .awaitingReview(count):
            return "Pending skills — \(count) awaiting review"
        case .unavailable:
            return "Pending skills — unavailable"
        }
    }

    public var needsAttention: Bool {
        if case .awaitingReview = self { return true }
        return false
    }

    public var count: Int {
        if case let .awaitingReview(count) = self { return count }
        return 0
    }

    public var attentionFingerprint: String {
        switch self {
        case .none:
            return "pending:none"
        case let .awaitingReview(count):
            return "pending:\(count)"
        case let .unavailable(message):
            return "pending:unavailable:\(message)"
        }
    }
}

public enum PendingSkillsMonitor: Sendable {
    public static func evaluate(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> PendingSkillsState {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            return .none
        }
        guard isDirectory.boolValue else {
            return .unavailable("The pending skills path exists but is not a directory.")
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return .unavailable("The pending skills directory is unreadable.")
        }

        var count = 0
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard url.pathExtension.lowercased() == "json" else { continue }
            count += 1
        }
        return count == 0 ? .none : .awaitingReview(count)
    }
}
