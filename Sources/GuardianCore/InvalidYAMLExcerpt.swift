import Foundation
import Yams

public enum InvalidYAMLExcerpt {
    public static func summary(error: Error) -> String {
        guard let yamlError = error as? YamlError else {
            return error.localizedDescription
        }
        switch yamlError {
        case let .reader(problem, _, _, _):
            return "YAML text could not be read: \(problem)."
        case let .scanner(_, problem, mark, _),
             let .parser(_, problem, mark, _),
             let .composer(_, problem, mark, _):
            return "YAML syntax error at line \(mark.line), column \(mark.column): \(problem)."
        case let .duplicatedKeysInMapping(duplicates, _):
            return "YAML contains duplicate keys: \(duplicates.sorted().joined(separator: ", "))."
        case .dataCouldNotBeDecoded:
            return "The file could not be decoded as YAML text."
        default:
            return "The YAML parser could not read this configuration."
        }
    }

    public static func extract(
        from data: Data,
        error: Error,
        maxCharacters: Int = 240
    ) -> String? {
        guard maxCharacters > 0,
              let text = String(data: data, encoding: .utf8) else { return nil }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return nil }

        let markedIndex = lineNumber(from: error).map { min(max($0 - 1, 0), lines.count - 1) }
        let preferred = markedIndex.flatMap { index in
            stride(from: index, through: max(index - 1, 0), by: -1)
                .map { lines[$0] }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let fallback = lines.last { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let raw = preferred ?? fallback else { return nil }

        let fragment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return nil }
        if isSensitive(fragment) { return "[redacted invalid line]" }
        return String(fragment.prefix(maxCharacters))
    }

    private static func lineNumber(from error: Error) -> Int? {
        guard let yamlError = error as? YamlError else { return nil }
        switch yamlError {
        case let .scanner(_, _, mark, _),
             let .parser(_, _, mark, _),
             let .composer(_, _, mark, _):
            return mark.line
        case let .duplicatedKeysInMapping(_, context):
            return context.mark.line
        default:
            return nil
        }
    }

    private static func isSensitive(_ fragment: String) -> Bool {
        let lower = fragment.lowercased()
        let sensitiveHints = [
            "api_key", "apikey", "access_token", "refreshtoken", "refresh_token",
            "auth_token", "bearer", "password", "passphrase", "secret",
            "credential", "authorization", "webhook", "/users/",
            "sk-", "ghp_", "github_pat_", "xoxb-", "xoxp-"
        ]
        if sensitiveHints.contains(where: lower.contains) || fragment.contains("@") {
            return true
        }

        return fragment.split { !$0.isLetter && !$0.isNumber }.contains { token in
            guard token.count >= 24 else { return false }
            return token.contains(where: \.isLetter) && token.contains(where: \.isNumber)
        }
    }
}
