import Foundation

public enum HermesSettingKnowledge {
    private static let verifiedFacts: [String: String] = [
        "compression.idle_compact_after_seconds": "This is an opt-in, time-based compaction trigger. A value of 0 disables idle-triggered compaction. A value above 0 means that when an eligible session resumes after at least that many seconds of inactivity, Hermes may compact accumulated history before the first reply. It still skips contexts at or below the post-compression target and honors failure cooldown, anti-thrash, and per-session locking guards.",
    ]

    public static func verifiedFact(for path: String) -> String? {
        verifiedFacts[path]
    }
}
