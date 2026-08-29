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
    public let beforeKind: YAMLValueKind?
    public let afterKind: YAMLValueKind?

    public var id: String { path }

    public var hasTypeTransition: Bool {
        guard let beforeKind, let afterKind else { return false }
        return beforeKind != afterKind
    }

    public init(
        path: String,
        kind: ChangeKind,
        before: String?,
        after: String?,
        beforeKind: YAMLValueKind? = nil,
        afterKind: YAMLValueKind? = nil
    ) {
        self.path = path
        self.kind = kind
        self.before = before
        self.after = after
        self.beforeKind = beforeKind
        self.afterKind = afterKind
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
            let beforeKind = approved.flattenedKinds[path]
            let afterKind = proposed.flattenedKinds[path]
            let sensitivePath = isSensitive(path)
            let safeBefore = before.map {
                sensitivePath || SensitiveValueDetector.shouldRedact($0) ? "<redacted>" : $0
            }
            let safeAfter = after.map {
                sensitivePath || SensitiveValueDetector.shouldRedact($0) ? "<redacted>" : $0
            }

            if before == nil {
                return SemanticChange(path: path, kind: .added, before: nil, after: safeAfter, afterKind: afterKind)
            }
            if after == nil {
                return SemanticChange(path: path, kind: .removed, before: safeBefore, after: nil, beforeKind: beforeKind)
            }
            return SemanticChange(
                path: path,
                kind: .changed,
                before: safeBefore,
                after: safeAfter,
                beforeKind: beforeKind,
                afterKind: afterKind
            )
        }
    }

    public static func isSensitive(_ path: String) -> Bool {
        let segments = path.lowercased().split { character in
            character == "." || character == "[" || character == "]"
        }

        return segments.contains { segment in
            let words = segment.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            let collapsed = words.joined()

            if ["secrets", "credentials"].contains(String(segment)) { return true }
            if [
                "apikey", "accesstoken", "refreshtoken", "authtoken", "bearertoken",
                "clientsecret", "password", "passphrase", "authorization", "webhookurl"
            ].contains(collapsed) { return true }
            if words.contains("secret") || words.contains("password") || words.contains("credential") {
                return true
            }
            if words == ["token"] || words == ["webhook"] { return true }
            return false
        }
    }
}
