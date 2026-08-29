import Foundation

public enum ChangeKind: String, Codable, Sendable {
    case added
    case removed
    case changed
}

public struct SemanticChange: Identifiable, Codable, Equatable, Sendable {
    public let path: String
    public let kind: ChangeKind
    public let before: String?
    public let after: String?

    public var id: String { path }

    public init(path: String, kind: ChangeKind, before: String?, after: String?) {
        self.path = path
        self.kind = kind
        self.before = before
        self.after = after
    }
}

public enum SemanticDiffer {
    public static func changes(from approved: InspectedYAML, to proposed: InspectedYAML) -> [SemanticChange] {
        let old = approved.flattenedValues
        let new = proposed.flattenedValues
        let paths = Set(old.keys).union(new.keys).sorted()

        return paths.compactMap { path in
            let before = old[path]
            let after = new[path]
            guard before != after else { return nil }
            let sensitive = isSensitive(path)
            let safeBefore = sensitive && before != nil ? "<redacted>" : before
            let safeAfter = sensitive && after != nil ? "<redacted>" : after

            if before == nil {
                return SemanticChange(path: path, kind: .added, before: nil, after: safeAfter)
            }
            if after == nil {
                return SemanticChange(path: path, kind: .removed, before: safeBefore, after: nil)
            }
            return SemanticChange(path: path, kind: .changed, before: safeBefore, after: safeAfter)
        }
    }

    public static func isSensitive(_ path: String) -> Bool {
        let lower = path.lowercased()
        return ["api_key", "apikey", "token", "secret", "password", "credential", "authorization", "webhook"]
            .contains { lower.contains($0) }
    }
}
