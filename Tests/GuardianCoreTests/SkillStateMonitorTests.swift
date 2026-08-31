import Foundation
import XCTest
@testable import GuardianCore

final class SkillStateMonitorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-skill-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testPendingSkillsEmptyDirectoryIsNone() throws {
        let pending = temporaryDirectory.appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)

        XCTAssertEqual(PendingSkillsMonitor.evaluate(at: pending), .none)
        XCTAssertEqual(PendingSkillsMonitor.evaluate(at: pending).displayText, "Pending skills — none")
    }

    func testPendingSkillsMissingDirectoryIsNone() {
        let pending = temporaryDirectory.appendingPathComponent("missing-pending", isDirectory: true)
        XCTAssertEqual(PendingSkillsMonitor.evaluate(at: pending), .none)
    }

    func testPendingSkillsCountsJSONRecordsWithoutParsing() throws {
        let pending = temporaryDirectory.appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        try Data("{\"not\": \"parsed\"}".utf8).write(to: pending.appendingPathComponent("aaa.json"))
        try Data("{".utf8).write(to: pending.appendingPathComponent("bbb.json"))
        try Data("ignore".utf8).write(to: pending.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(
            at: pending.appendingPathComponent("nested", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(PendingSkillsMonitor.evaluate(at: pending), .awaitingReview(2))
        XCTAssertEqual(
            PendingSkillsMonitor.evaluate(at: pending).displayText,
            "Pending skills — 2 awaiting review"
        )
    }

    func testPendingSkillProposalReaderShowsRecordsWithoutMutatingThem() throws {
        let pending = temporaryDirectory.appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        let record = pending.appendingPathComponent("abc123.json")
        let source = """
        {"id":"abc123","action":"batch","origin":"assistant_tool","summary":"batch(1 ops: create) on example-skill","created_at":1700000000,"payload":{"action":"batch"}}
        """
        try Data(source.utf8).write(to: record)
        try Data("{".utf8).write(to: pending.appendingPathComponent("broken.json"))

        let before = try directoryFingerprint(pending)
        let proposals = PendingSkillProposalReader.load(from: pending)

        XCTAssertEqual(proposals.map(\.id), ["abc123", "broken"])
        XCTAssertEqual(proposals.first?.summary, "batch(1 ops: create) on example-skill")
        XCTAssertTrue(proposals.first?.recordText?.contains("example-skill") == true)
        XCTAssertEqual(proposals.last?.issue, "Guardian could not read this pending record.")
        XCTAssertEqual(try directoryFingerprint(pending), before)
    }

    func testSkillsManifestIsDeterministicAndHashesRegularFilesByRelativePath() throws {
        let skills = try makeSkillsTree()
        let first = try loadManifest(skills)
        let second = try loadManifest(skills)

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.files["alpha/SKILL.md"],
            ApprovalStore.sha256(Data("alpha-body\n".utf8))
        )
        XCTAssertEqual(
            first.files["beta/nested/notes.txt"],
            ApprovalStore.sha256(Data("nested-body\n".utf8))
        )
        XCTAssertEqual(first.files.keys.sorted(), ["alpha/SKILL.md", "beta/nested/notes.txt"])
    }

    func testHermesOperationalMetadataIsExcludedFromActiveSkillIntegrity() throws {
        let skills = try makeSkillsTree()
        try Data("usage\n".utf8).write(to: skills.appendingPathComponent(".usage.json"))
        try FileManager.default.createDirectory(
            at: skills.appendingPathComponent(".hub", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("cache\n".utf8).write(to: skills.appendingPathComponent(".hub/lock.json"))
        try Data("finder\n".utf8).write(to: skills.appendingPathComponent("alpha/.DS_Store"))
        try Data("tracked\n".utf8).write(to: skills.appendingPathComponent("alpha/.env.example"))

        let manifest = try loadManifest(skills)

        XCTAssertNil(manifest.files[".usage.json"])
        XCTAssertNil(manifest.files[".hub/lock.json"])
        XCTAssertNil(manifest.files["alpha/.DS_Store"])
        XCTAssertNotNil(manifest.files["alpha/.env.example"])
    }

    func testExistingBaselineMetadataDoesNotCreateSyntheticDrift() {
        let baseline = SkillsManifest(files: [
            "alpha/SKILL.md": "unchanged",
            ".usage.json": "old-telemetry",
            ".hub/lock.json": "old-cache",
        ])
        let current = SkillsManifest(files: [
            "alpha/SKILL.md": "unchanged",
        ])

        XCTAssertEqual(SkillsDrift.comparing(baseline: baseline, current: current), .clean)
    }

    func testTimestampOnlyChangeWithIdenticalBytesDoesNotProduceDrift() throws {
        let skills = try makeSkillsTree()
        let baseline = try loadManifest(skills)
        let file = skills.appendingPathComponent("alpha/SKILL.md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
            ofItemAtPath: file.path
        )

        let current = try loadManifest(skills)
        XCTAssertEqual(SkillsDrift.comparing(baseline: baseline, current: current), .clean)
    }

    func testAddedChangedAndRemovedFilesProduceCorrectDriftClassification() throws {
        let skills = try makeSkillsTree()
        let baseline = try loadManifest(skills)

        try Data("alpha-changed\n".utf8).write(to: skills.appendingPathComponent("alpha/SKILL.md"))
        try Data("new\n".utf8).write(to: skills.appendingPathComponent("gamma.md"))
        try FileManager.default.removeItem(at: skills.appendingPathComponent("beta/nested/notes.txt"))

        let current = try loadManifest(skills)
        let drift = SkillsDrift.comparing(baseline: baseline, current: current)

        XCTAssertEqual(drift.added, ["gamma.md"])
        XCTAssertEqual(drift.changed, ["alpha/SKILL.md"])
        XCTAssertEqual(drift.removed, ["beta/nested/notes.txt"])
        XCTAssertEqual(drift.totalCount, 3)
        XCTAssertFalse(drift.isClean)
    }

    func testNoBaselineIsNeutralRatherThanClean() throws {
        let skills = try makeSkillsTree()
        let current = try loadManifest(skills)
        let state = SkillsIntegrityState.make(baseline: nil, current: .success(current))

        XCTAssertEqual(state, .baselineNotRecorded)
        XCTAssertEqual(state.displayText, "Skills integrity — baseline not recorded")
        XCTAssertFalse(state.isClean)
        XCTAssertFalse(state.needsAttention)
    }

    func testRecordedBaselineIsStableAcrossReload() throws {
        let skills = try makeSkillsTree()
        let stateDirectory = temporaryDirectory.appendingPathComponent("state", isDirectory: true)
        let store = SkillsIntegrityStore(stateDirectory: stateDirectory)
        let manifest = try loadManifest(skills)
        let recordedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let recorded = try store.record(
            rootURL: skills,
            manifest: manifest,
            at: recordedAt
        )

        let reloaded = try XCTUnwrap(SkillsIntegrityStore(stateDirectory: stateDirectory).load())
        XCTAssertEqual(reloaded, recorded)
        XCTAssertEqual(reloaded.manifest, manifest)
        XCTAssertEqual(reloaded.recordedAt, recordedAt)

        let state = SkillsIntegrityState.make(baseline: reloaded, current: .success(manifest))
        XCTAssertEqual(state, .clean)
        XCTAssertTrue(state.isClean)
    }

    func testMissingSkillsDirectoryIsNotReportedClean() {
        let missing = temporaryDirectory.appendingPathComponent("missing-skills", isDirectory: true)
        let result = SkillsManifest.load(from: missing)

        guard case let .unavailable(message) = result else {
            return XCTFail("Expected unavailable skills directory, got \(result)")
        }
        XCTAssertFalse(message.isEmpty)
        let state = SkillsIntegrityState.make(baseline: nil, current: result)
        XCTAssertEqual(state, .unavailable(message))
        XCTAssertFalse(state.isClean)
        XCTAssertNotEqual(state.displayText, "Skills integrity — matches recorded baseline")
    }

    func testUnreadableSkillsPathIsNotReportedClean() throws {
        let file = temporaryDirectory.appendingPathComponent("not-a-directory")
        try Data("file\n".utf8).write(to: file)
        let result = SkillsManifest.load(from: file)

        guard case .unavailable = result else {
            return XCTFail("Expected unavailable skills path, got \(result)")
        }
        XCTAssertFalse(SkillsIntegrityState.make(baseline: nil, current: result).isClean)
    }

    func testSkillMonitorsDoNotWriteWatchedDirectories() throws {
        let pending = temporaryDirectory.appendingPathComponent("pending", isDirectory: true)
        let skills = try makeSkillsTree()
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        let pendingRecord = pending.appendingPathComponent("abc123.json")
        try Data("{\"id\":\"abc123\"}".utf8).write(to: pendingRecord)
        let beforePending = try directoryFingerprint(pending)
        let beforeSkills = try directoryFingerprint(skills)

        _ = PendingSkillsMonitor.evaluate(at: pending)
        let manifest = try loadManifest(skills)
        let store = SkillsIntegrityStore(
            stateDirectory: temporaryDirectory.appendingPathComponent("state", isDirectory: true)
        )
        _ = try store.record(rootURL: skills, manifest: manifest)
        _ = SkillsDrift.comparing(baseline: manifest, current: manifest)

        XCTAssertEqual(try directoryFingerprint(pending), beforePending)
        XCTAssertEqual(try directoryFingerprint(skills), beforeSkills)
        XCTAssertEqual(try Data(contentsOf: pendingRecord), Data("{\"id\":\"abc123\"}".utf8))
    }

    private func loadManifest(_ skills: URL) throws -> SkillsManifest {
        switch SkillsManifest.load(from: skills) {
        case let .success(manifest):
            return manifest
        case let .unavailable(message):
            throw NSError(domain: "SkillStateMonitorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func makeSkillsTree() throws -> URL {
        let skills = temporaryDirectory.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(
            at: skills.appendingPathComponent("alpha", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: skills.appendingPathComponent("beta/nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("alpha-body\n".utf8).write(to: skills.appendingPathComponent("alpha/SKILL.md"))
        try Data("nested-body\n".utf8).write(to: skills.appendingPathComponent("beta/nested/notes.txt"))
        return skills
    }

    private func directoryFingerprint(_ root: URL) throws -> [String: String] {
        var files: [String: String] = [:]
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            )
        )
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            let data = try Data(contentsOf: url)
            let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            files[relative] = "\(data.count):\(ApprovalStore.sha256(data)):\(mtime)"
        }
        return files
    }
}
