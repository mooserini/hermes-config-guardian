import Foundation

public enum TypeTransitionGuard {
    public static func reviewWarning(for changes: [SemanticChange]) -> String? {
        let transitions = changes.filter(\.hasTypeTransition)
        guard !transitions.isEmpty else { return nil }

        let paths = transitions.map(\.path).joined(separator: ", ")
        return "Value type changed for \(paths). Guardian will not assume the new representation behaves like the approved one."
    }

    public static func explanation(for changes: [SemanticChange]) -> String? {
        let transitions = changes.filter(\.hasTypeTransition)
        guard !transitions.isEmpty else { return nil }

        let details = transitions.map { change in
            let beforeType = change.beforeKind?.displayName ?? "unknown type"
            let afterType = change.afterKind?.displayName ?? "unknown type"
            return "\(change.path) changes from \(beforeType) value “\(change.before ?? "<absent>")” to \(afterType) value “\(change.after ?? "<absent>")”."
        }

        var result = details.joined(separator: "\n\n")
        result += "\n\nThis is a value-type change. Guardian will not assume the new representation behaves like the approved one. Documentation describing one value type does not establish that Hermes accepts or assigns equivalent behavior to another type. Verify the exact accepted type before approving, or reject the proposal."

        let remaining = changes.count - transitions.count
        if remaining > 0 {
            result += "\n\n\(remaining) additional change\(remaining == 1 ? " is" : "s are") listed in Review and has not been interpreted here."
        }
        return result
    }
}
