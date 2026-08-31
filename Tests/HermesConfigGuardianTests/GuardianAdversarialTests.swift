import XCTest
@testable import HermesConfigGuardian

@MainActor
final class GuardianAdversarialTests: XCTestCase {
    func testClumsyWizardSemanticChangeIsDetectedAndRejectedExactly() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()

        try write("""
        model:
          default: terra
        compression:
          idle_compact_after_seconds: 0
        display:
          tool_progress: verbose
        voice:
          auto_tts: true
        """, to: fixture.source)
        model.checkForChange()

        XCTAssertEqual(model.status, .changed(1))
        XCTAssertEqual(model.pending?.changes.map(\.path), ["display.tool_progress"])
        model.reject()
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.baseline)
        XCTAssertEqual(model.status, .clean)
    }

    func testUnknownSettingIsReportedWithoutInventedMeaning() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()

        try write(String(decoding: fixture.baseline, as: UTF8.self) + "\nfavorite_position: whatever the config file wants\n", to: fixture.source)
        model.checkForChange()

        XCTAssertEqual(model.status, .changed(1))
        XCTAssertEqual(model.pending?.changes.map(\.path), ["favorite_position"])
        XCTAssertEqual(model.pending?.changes.first?.kind, .added)
        model.reject()
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.baseline)
    }

    func testInvalidHumanTextCannotBeAcceptedAndIsRejectedExactly() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()

        try write(String(decoding: fixture.baseline, as: UTF8.self) + "\nI SHIT MY PANTS HELP ME\n", to: fixture.source)
        model.checkForChange()

        XCTAssertEqual(model.status, .invalid)
        XCTAssertNotNil(model.pending?.validationError)
        model.accept()
        XCTAssertEqual(model.status, .invalid)
        model.reject()
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.baseline)
        XCTAssertEqual(model.status, .clean)
    }

    func testByteOnlyRewriteHasNoInventedPathsAndRejectRestoresBytes() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()

        try write("""
        voice:
          auto_tts: true
        display:
          tool_progress: all
        compression:
          idle_compact_after_seconds: 0
        model:
          default: terra
        """, to: fixture.source)
        model.checkForChange()

        XCTAssertEqual(model.status, .changed(0))
        XCTAssertEqual(model.pending?.changes, [])
        model.reject()
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.baseline)
    }

    func testRapidInvalidWritesStayInvalidAndEveryRejectKeepsOriginalSnapshot() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()

        for malformed in [
            "model: [\n",
            "display: { tool_progress:\n",
            "THIS IS A DINGLEBERRY: [\n",
        ] {
            try write(malformed, to: fixture.source)
            model.checkForChange()
            XCTAssertEqual(model.status, .invalid)
            XCTAssertNotNil(model.pending?.validationError)
            model.reject()
            XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.baseline)
            XCTAssertEqual(model.status, .clean)
        }
    }

    func testStaleApprovalIsRefusedWhenTheWriterMovesAgain() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = makeModel(source: fixture.source, state: fixture.state)
        model.enroll()

        try write(String(decoding: fixture.baseline, as: UTF8.self).replacingOccurrences(of: "all", with: "verbose"), to: fixture.source)
        model.checkForChange()
        try write(String(decoding: fixture.baseline, as: UTF8.self).replacingOccurrences(of: "all", with: "none"), to: fixture.source)
        model.accept()

        guard case let .error(message) = model.status else {
            return XCTFail("Expected Guardian to refuse stale approval")
        }
        XCTAssertEqual(message, "The file changed again before approval. Review the newest version.")
        XCTAssertEqual(model.pending?.changes.map(\.path), ["display.tool_progress"])
        model.reject()
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.baseline)
    }

    private func makeFixture() throws -> (root: URL, source: URL, state: URL, baseline: Data) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-adversarial-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("config.yaml")
        let state = root.appendingPathComponent("state", isDirectory: true)
        let baseline = Data("""
        model:
          default: terra
        compression:
          idle_compact_after_seconds: 0
        display:
          tool_progress: all
        voice:
          auto_tts: true
        """.utf8)
        try baseline.write(to: source)
        return (root, source, state, baseline)
    }

    private func makeModel(source: URL, state: URL) -> GuardianModel {
        GuardianModel(
            environment: [
                "HCG_TARGET_CONFIG": source.path,
                "HCG_STATE_DIR": state.path,
                "HCG_PENDING_SKILLS_DIR": source.deletingLastPathComponent().appendingPathComponent("pending-skills").path,
                "HCG_SKILLS_DIR": source.deletingLastPathComponent().appendingPathComponent("active-skills").path,
                "HCG_RECONCILE_INTERVAL": "3600",
            ],
            userDefaults: UserDefaults(suiteName: "GuardianAdversarialTests.\(UUID().uuidString)")!
        )
    }

    private func write(_ text: String, to source: URL) throws {
        try Data(text.utf8).write(to: source, options: .atomic)
    }
}
