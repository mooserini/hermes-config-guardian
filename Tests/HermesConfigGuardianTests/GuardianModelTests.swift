import XCTest
@testable import HermesConfigGuardian

@MainActor
final class GuardianModelTests: XCTestCase {
    func testAppleFallbackTitlePreservesHermesFailure() {
        let source = GuardianModel.ClarificationSource.apple(
            hermesFailure: "The Hermes stateless clarification timed out."
        )

        XCTAssertEqual(
            source.title,
            "Apple on-device fallback · The Hermes stateless clarification timed out."
        )
    }

    func testDeterministicFallbackTitlePreservesPriorFailures() {
        let reason = "Hermes timed out. Apple inference was unavailable."
        let source = GuardianModel.ClarificationSource.deterministicAfterFailure(
            reason: reason
        )

        XCTAssertEqual(source.title, "Deterministic fallback · \(reason)")
    }

    func testByteOnlyRewriteHasDistinctStatusTitle() {
        XCTAssertEqual(
            GuardianModel.Status.changed(0).title,
            "File rewrite needs attention"
        )
    }

    func testCleanStatusDescribesTheMonitoredFilesOverview() {
        XCTAssertEqual(
            GuardianModel.Status.clean.title,
            "All monitored files are approved"
        )
    }

    func testMaintenanceWindowRehydratesAfterModelRestart() throws {
        let fixture = try makeFixture(data: Data("value: approved\n".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()
        model.beginHermesUpdate()

        let reloaded = makeModel(source: fixture.source, state: fixture.state)

        XCTAssertNotNil(reloaded.maintenance)
        XCTAssertEqual(reloaded.status, .maintenance)
        XCTAssertEqual(reloaded.maintenance?.checkpointData, Data("value: approved\n".utf8))
    }

    func testMaintenanceRecordsRapidChangesWithoutAttentionAndAcceptsOnlyFinalVersion() throws {
        let fixture = try makeFixture(data: Data("value: approved\n".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var soundCount = 0
        let model = makeModel(source: fixture.source, state: fixture.state) {
            soundCount += 1
        }
        model.enroll()
        model.beginHermesUpdate()

        try Data("value: intermediate\n".utf8).write(to: fixture.source, options: .atomic)
        model.checkForChange()
        try Data("value: final\n".utf8).write(to: fixture.source, options: .atomic)
        model.checkForChange()

        XCTAssertEqual(model.maintenanceObservedCount, 2)
        XCTAssertEqual(soundCount, 0)
        XCTAssertEqual(model.status, .maintenance)

        model.endHermesUpdateAndReview()
        XCTAssertTrue(model.maintenanceReviewReady)
        XCTAssertEqual(model.status, .changed(1))
        XCTAssertEqual(model.approved?.data, Data("value: approved\n".utf8))

        model.accept()
        XCTAssertNil(model.maintenance)
        XCTAssertEqual(model.status, .clean)
        XCTAssertEqual(model.approved?.data, Data("value: final\n".utf8))
        XCTAssertEqual(
            model.maintenanceMessage,
            "The final Hermes update result is now the approved configuration."
        )
    }

    func testOrdinaryAcceptDoesNotClaimAHermesUpdateFinished() throws {
        let fixture = try makeFixture(data: Data("value: approved\n".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()
        try Data("value: proposed\n".utf8).write(to: fixture.source, options: .atomic)
        model.checkForChange()

        model.accept()

        XCTAssertEqual(model.status, .clean)
        XCTAssertNil(model.maintenance)
        XCTAssertNil(model.maintenanceMessage)
        XCTAssertEqual(model.approved?.data, Data("value: proposed\n".utf8))
    }

    func testMaintenanceRejectRestoresExactCheckpointAfterInvalidFinalWrite() throws {
        let approvedData = Data("model:\n  default: terra\n".utf8)
        let fixture = try makeFixture(data: approvedData)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()
        model.beginHermesUpdate()

        try Data("model: [\n".utf8).write(to: fixture.source, options: .atomic)
        model.checkForChange()
        XCTAssertEqual(model.status, .invalid)
        XCTAssertNotNil(model.maintenance)
        XCTAssertFalse(model.maintenanceReviewReady)

        model.endHermesUpdateAndReview()
        XCTAssertTrue(model.maintenanceReviewReady)
        XCTAssertNotNil(model.pending?.validationError)
        model.reject()

        XCTAssertNil(model.maintenance)
        XCTAssertEqual(model.status, .clean)
        XCTAssertEqual(try Data(contentsOf: fixture.source), approvedData)
    }

    func testMaintenanceEndsCleanlyWhenUpdateMakesNoByteChange() throws {
        let fixture = try makeFixture(data: Data("value: approved\n".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()
        model.beginHermesUpdate()
        model.endHermesUpdateAndReview()

        XCTAssertNil(model.maintenance)
        XCTAssertEqual(model.status, .clean)
        XCTAssertEqual(
            model.maintenanceMessage,
            "Hermes update finished without changing the guarded file."
        )
    }

    func testMaintenanceSurfacesByteOnlyFinalRewriteWithoutInventingPaths() throws {
        let fixture = try makeFixture(data: Data("first: 1\nsecond: 2\n".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()
        model.beginHermesUpdate()
        try Data("second: 2\nfirst: 1\n".utf8).write(to: fixture.source, options: .atomic)

        model.endHermesUpdateAndReview()

        XCTAssertEqual(model.status, .changed(0))
        XCTAssertEqual(model.pending?.changes, [])
        XCTAssertTrue(model.maintenanceReviewReady)
    }

    func testMaintenanceRefusesToBeginWhileProposalIsPending() throws {
        let fixture = try makeFixture(data: Data("value: approved\n".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()
        try Data("value: proposed\n".utf8).write(to: fixture.source, options: .atomic)
        model.checkForChange()

        model.beginHermesUpdate()

        XCTAssertNil(model.maintenance)
        guard case .error = model.status else {
            return XCTFail("Expected maintenance precondition error")
        }
    }

    private func makeFixture(data: Data) throws -> (root: URL, source: URL, state: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("config.yaml")
        let state = root.appendingPathComponent("state", isDirectory: true)
        try data.write(to: source)
        return (root, source, state)
    }

    private func makeModel(
        source: URL,
        state: URL,
        playAttentionSound: @escaping @MainActor () -> Void = {}
    ) -> GuardianModel {
        let defaults = UserDefaults(suiteName: "GuardianModelTests.\(UUID().uuidString)")!
        return GuardianModel(
            environment: [
                "HCG_TARGET_CONFIG": source.path,
                "HCG_STATE_DIR": state.path,
                "HCG_PENDING_SKILLS_DIR": source.deletingLastPathComponent().appendingPathComponent("pending-skills").path,
                "HCG_SKILLS_DIR": source.deletingLastPathComponent().appendingPathComponent("active-skills").path,
                "HCG_RECONCILE_INTERVAL": "3600",
            ],
            userDefaults: defaults,
            playAttentionSound: playAttentionSound
        )
    }
}
