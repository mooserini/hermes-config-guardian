import Foundation

public enum SensitiveValueDetector {
    public static func shouldRedact(_ text: String) -> Bool {
        let lower = text.lowercased()
        let sensitiveHints = [
            "api_key", "apikey", "access_token", "refreshtoken", "refresh_token",
            "auth_token", "bearer", "password", "passphrase", "secret",
            "credential", "authorization", "webhook", "/users/",
            "sk-", "ghp_", "github_pat_", "xoxb-", "xoxp-"
        ]
        if sensitiveHints.contains(where: lower.contains) || text.contains("@") {
            return true
        }

        return text.split { !$0.isLetter && !$0.isNumber }.contains { token in
            guard token.count >= 24 else { return false }
            return token.contains(where: \.isLetter) && token.contains(where: \.isNumber)
        }
    }
}
