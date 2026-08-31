import Foundation

/// A read-only presentation of one file-backed Hermes skill proposal.
///
/// Guardian deliberately does not replay, approve, reject, or otherwise mutate
/// these records. It makes the existing Hermes queue inspectable and gives the
/// human the exact identifier needed in Hermes' own review surface.
public struct PendingSkillProposal: Identifiable, Equatable, Sendable {
    public let id: String
    public let action: String
    public let origin: String
    public let summary: String
    public let createdAt: Date?
    public let recordText: String?
    public let issue: String?

    public var title: String {
        summary.isEmpty ? "Pending skill proposal" : summary
    }
}

public enum PendingSkillProposalReader: Sendable {
    public static func load(
        from directory: URL,
        fileManager: FileManager = .default
    ) -> [PendingSkillProposal] {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return contents
            .filter { url in
                guard url.pathExtension.lowercased() == "json" else { return false }
                return (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            }
            .map { proposal(from: $0) }
            .sorted { lhs, rhs in
                switch (lhs.createdAt, rhs.createdAt) {
                case let (left?, right?): return left < right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.id < rhs.id
                }
            }
    }

    private static func proposal(from url: URL) -> PendingSkillProposal {
        let fallbackID = url.deletingPathExtension().lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let record = object as? [String: Any] else {
                return unreadable(id: fallbackID, issue: "The pending record is not a JSON object.")
            }

            let prettyData = try JSONSerialization.data(
                withJSONObject: record,
                options: [.prettyPrinted, .sortedKeys]
            )
            let recordText = String(decoding: prettyData, as: UTF8.self)
            return PendingSkillProposal(
                id: string(record["id"]) ?? fallbackID,
                action: string(record["action"]) ?? "unknown action",
                origin: string(record["origin"]) ?? "unknown origin",
                summary: string(record["summary"]) ?? "",
                createdAt: date(record["created_at"]),
                recordText: recordText,
                issue: nil
            )
        } catch {
            return unreadable(id: fallbackID, issue: "Guardian could not read this pending record.")
        }
    }

    private static func unreadable(id: String, issue: String) -> PendingSkillProposal {
        PendingSkillProposal(
            id: id,
            action: "unavailable",
            origin: "unavailable",
            summary: "Pending skill proposal",
            createdAt: nil,
            recordText: nil,
            issue: issue
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
        if let text = value as? String, let seconds = TimeInterval(text) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}
