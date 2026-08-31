import XCTest
@testable import GuardianCore
@testable import HermesConfigGuardian

@MainActor
final class GuardianSkillStateTests: XCTestCase {
    func testPendingSkillsEmptyVersusNonemptyRecordCount() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(fixture: fixture)
        model.enroll()
        await model.waitForSkillReconciliationForTesting()

        XCTAssertEqual(model.pendingSkills, .none)
        XCTAssertEqual(model.pendingSkills.displayText, "Pending skills — none")
        XCTAssertEqual(model.status, .clean)

        try Data("{\"id\":\"one\"}".utf8).write(to: fixture.pending.appendingPathComponent("one.json"))
        try Data("{\"id\":\"two\"}".utf8).write(to: fixture.pending.appendingPathComponent("two.json"))
        model.checkForChange()
        await model.waitForSkillReconciliationForTesting()

        XCTAssertEqual(model.pendingSkills, .awaitingReview(2))
        XCTAssertEqual(model.pendingSkills.displayText, "Pending skills — 2 awaiting review")
        XCTAssertEqual(model.pendingSkillProposals.map(\.id), ["one", "two"])
        XCTAssertEqual(model.status, .clean)
        XCTAssertEqual(model.headline, "Pending skills await review")
    }

    func testNoSkillsBaselineIsNeutralRatherThanClean() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("body\n".utf8).write(to: fixture.skills.appendingPathComponent("SKILL.md"))
        let model = makeModel(fixture: fixture)
        model.enroll()
        await model.waitForSkillReconciliationForTesting()

        XCTAssertEqual(model.skillsIntegrity, .baselineNotRecorded)
        XCTAssertFalse(model.skillsIntegrity.isClean)
        XCTAssertEqual(model.status, .clean)
        XCTAssertEqual(model.headline, "All monitored files are approved")
        XCTAssertTrue(model.canRecordSkillsBaseline)
    }

    func testRecordedSkillsBaselineIsStableAcrossReload() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("body\n".utf8).write(to: fixture.skills.appendingPathComponent("SKILL.md"))
        let model = makeModel(fixture: fixture)
        model.enroll()
        await model.waitForSkillReconciliationForTesting()
        await model.recordCurrentSkillStateNow()

        XCTAssertEqual(model.skillsIntegrity, .clean)

        let reloaded = makeModel(fixture: fixture)
        await reloaded.waitForSkillReconciliationForTesting()
        XCTAssertEqual(reloaded.skillsIntegrity, .clean)
        XCTAssertEqual(reloaded.status, .clean)
    }

    func testMissingSkillsDirectoryIsNotClean() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.skills)
        let model = makeModel(fixture: fixture)
        model.enroll()
        await model.waitForSkillReconciliationForTesting()

        guard case .unavailable = model.skillsIntegrity else {
            return XCTFail("Expected unavailable skills integrity, got \(model.skillsIntegrity)")
        }
        XCTAssertFalse(model.skillsIntegrity.isClean)
        XCTAssertEqual(model.status, .clean)
    }

    func testSkillMonitorsDoNotWriteWatchedDirectories() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let pendingRecord = fixture.pending.appendingPathComponent("abc.json")
        let skillFile = fixture.skills.appendingPathComponent("SKILL.md")
        try Data("{\"id\":\"abc\"}".utf8).write(to: pendingRecord)
        try Data("skill-body\n".utf8).write(to: skillFile)
        let pendingBefore = try Data(contentsOf: pendingRecord)
        let skillBefore = try Data(contentsOf: skillFile)

        let model = makeModel(fixture: fixture)
        model.enroll()
        await model.waitForSkillReconciliationForTesting()
        await model.recordCurrentSkillStateNow()
        try Data("skill-body-changed\n".utf8).write(to: skillFile)
        model.checkForChange()
        await model.waitForSkillReconciliationForTesting()

        XCTAssertEqual(try Data(contentsOf: pendingRecord), pendingBefore)
        XCTAssertEqual(try Data(contentsOf: skillFile), Data("skill-body-changed\n".utf8))
        XCTAssertNotEqual(try Data(contentsOf: skillFile), skillBefore)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.pending.appendingPathComponent("skills-baseline.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.state.appendingPathComponent("skills-baseline.json").path
            )
        )
    }

    func testUnchangedPendingCountDoesNotRepeatAttention() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("{\"id\":\"one\"}".utf8).write(to: fixture.pending.appendingPathComponent("one.json"))
        var soundCount = 0
        let model = makeModel(fixture: fixture) {
            soundCount += 1
        }
        model.enroll()
        await model.waitForSkillReconciliationForTesting()
        XCTAssertEqual(soundCount, 1)

        model.checkForChange()
        await model.waitForSkillReconciliationForTesting()
        XCTAssertEqual(soundCount, 1)
        XCTAssertEqual(model.status, .clean)
        XCTAssertNotEqual(model.headline, "File rewrite needs attention")
    }

    func testLoginWithExistingPendingSkillsOpensReviewWithoutReplayingSound() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("{\"id\":\"one\"}".utf8).write(to: fixture.pending.appendingPathComponent("one.json"))

        let firstRun = makeModel(fixture: fixture)
        firstRun.enroll()
        await firstRun.waitForSkillReconciliationForTesting()

        var soundCount = 0
        var windowCount = 0
        let reloaded = makeModel(fixture: fixture) {
            soundCount += 1
        }
        reloaded.attentionWindowEnabled = true
        reloaded.setAttentionWindowHandler {
            windowCount += 1
        }
        await reloaded.waitForSkillReconciliationForTesting()

        XCTAssertEqual(soundCount, 0)
        XCTAssertEqual(windowCount, 1)

        reloaded.checkForChange()
        await reloaded.waitForSkillReconciliationForTesting()
        XCTAssertEqual(windowCount, 1)
    }

    private func makeFixture() throws -> (root: URL, source: URL, state: URL, pending: URL, skills: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-skill-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("config.yaml")
        let state = root.appendingPathComponent("state", isDirectory: true)
        let pending = root.appendingPathComponent("pending-skills", isDirectory: true)
        let skills = root.appendingPathComponent("active-skills", isDirectory: true)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
        try Data("value: approved\n".utf8).write(to: source)
        return (root, source, state, pending, skills)
    }

    private func makeModel(
        fixture: (root: URL, source: URL, state: URL, pending: URL, skills: URL),
        playAttentionSound: @escaping @MainActor () -> Void = {}
    ) -> GuardianModel {
        let defaults = UserDefaults(suiteName: "GuardianSkillStateTests.\(UUID().uuidString)")!
        return GuardianModel(
            environment: [
                "HCG_TARGET_CONFIG": fixture.source.path,
                "HCG_STATE_DIR": fixture.state.path,
                "HCG_PENDING_SKILLS_DIR": fixture.pending.path,
                "HCG_SKILLS_DIR": fixture.skills.path,
                "HCG_RECONCILE_INTERVAL": "3600",
            ],
            userDefaults: defaults,
            playAttentionSound: playAttentionSound
        )
    }
}
