import Foundation
import XCTest
@testable import GuardianCore

final class GuardianCoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testApprovalRoundTripAndAppendOnlyReceipt() throws {
        let source = temporaryDirectory.appendingPathComponent("config.yaml")
        let state = temporaryDirectory.appendingPathComponent("state", isDirectory: true)
        let data = Data("model:\n  default: terra\n".utf8)
        try data.write(to: source)

        let store = ApprovalStore(stateDirectory: state)
        let approved = try store.approve(sourceURL: source, data: data, at: Date(timeIntervalSince1970: 1_700_000_000))
        let loaded = try XCTUnwrap(store.loadApproved())

        XCTAssertEqual(loaded.data, data)
        XCTAssertEqual(loaded.manifest, approved.manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.appendingPathComponent("receipts").path))
    }

    func testSemanticDiffRedactsSensitiveValues() throws {
        let old = try YAMLInspector.inspect(data: Data("model:\n  default: terra\nsecrets:\n  token: old-value\n".utf8))
        let new = try YAMLInspector.inspect(data: Data("model:\n  default: sol\nsecrets:\n  token: new-value\n".utf8))
        let changes = SemanticDiffer.changes(from: old, to: new)

        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.first { $0.path == "model.default" }?.after, "sol")
        XCTAssertEqual(changes.first { $0.path == "secrets.token" }?.before, "<redacted>")
        XCTAssertEqual(changes.first { $0.path == "secrets.token" }?.after, "<redacted>")
    }

    func testNumericValuesAreNotWrappedAsOptionals() throws {
        let document = try YAMLInspector.inspect(data: Data("compression:\n  idle_compact_after_seconds: 300\n".utf8))
        XCTAssertEqual(document.flattenedValues["compression.idle_compact_after_seconds"], "300")
    }

    func testRejectsInvalidYAMLAndNonMappingRoot() {
        XCTAssertThrowsError(try YAMLInspector.inspect(data: Data("model: [\n".utf8)))
        XCTAssertThrowsError(try YAMLInspector.inspect(data: Data("- one\n- two\n".utf8)))
    }

    func testRestoreUsesVerifiedApprovedBytes() throws {
        let source = temporaryDirectory.appendingPathComponent("config.yaml")
        let state = temporaryDirectory.appendingPathComponent("state", isDirectory: true)
        let approvedData = Data("compression:\n  idle_compact_after_seconds: 0\n".utf8)
        try approvedData.write(to: source)

        let store = ApprovalStore(stateDirectory: state)
        let approved = try store.approve(sourceURL: source, data: approvedData)
        try Data("compression:\n  idle_compact_after_seconds: 300\n".utf8).write(to: source)
        try store.restore(approved, to: source)

        XCTAssertEqual(try Data(contentsOf: source), approvedData)
    }

    func testRejectionReceiptRecordsHashesAndPathsWithoutRejectedContents() throws {
        let source = temporaryDirectory.appendingPathComponent("config.yaml")
        let state = temporaryDirectory.appendingPathComponent("state", isDirectory: true)
        let approvedData = Data("compression:\n  idle_compact_after_seconds: 0\n".utf8)
        let rejectedData = Data("compression:\n  idle_compact_after_seconds: 300\n".utf8)
        try rejectedData.write(to: source)

        let store = ApprovalStore(stateDirectory: state)
        let approved = try store.approve(sourceURL: source, data: approvedData)
        let receipt = try store.recordRejection(
            sourceURL: source,
            rejectedData: rejectedData,
            approvedSnapshot: approved,
            changedPaths: ["compression.idle_compact_after_seconds"],
            at: Date(timeIntervalSince1970: 1_700_000_001)
        )
        try store.restore(approved, to: source)

        XCTAssertEqual(receipt.rejectedHash, ApprovalStore.sha256(rejectedData))
        XCTAssertEqual(receipt.restoredHash, ApprovalStore.sha256(approvedData))
        XCTAssertEqual(receipt.changedPaths, ["compression.idle_compact_after_seconds"])
        XCTAssertEqual(try Data(contentsOf: source), approvedData)

        let receiptDirectory = state.appendingPathComponent("receipts", isDirectory: true)
        let rejectionURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: receiptDirectory, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("rejection-") }
        )
        let receiptText = try String(contentsOf: rejectionURL, encoding: .utf8)
        XCTAssertFalse(receiptText.contains("300"))
    }

    func testWatcherReportsAtomicReplacement() throws {
        let source = temporaryDirectory.appendingPathComponent("config.yaml")
        try Data("value: one\n".utf8).write(to: source)
        let changed = expectation(description: "directory watcher noticed replacement")
        let watcher = DirectoryWatcher(targetURL: source, debounceInterval: 0.05) {
            changed.fulfill()
        }
        try watcher.start()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            try? Data("value: two\n".utf8).write(to: source, options: [.atomic])
        }
        wait(for: [changed], timeout: 2)
        watcher.stop()
    }

    func testIdleCompactionKnowledgeDefinesZeroAsDisabled() throws {
        let fact = try XCTUnwrap(
            HermesSettingKnowledge.verifiedFact(for: "compression.idle_compact_after_seconds")
        )
        XCTAssertTrue(fact.contains("0 disables idle-triggered compaction"))
        XCTAssertFalse(fact.contains("immediately"))
    }

    func testDocumentationExtractorPrefersDefinitionParagraph() throws {
        let document = """
        idle_compact_after_seconds: 0

        Some unrelated prose mentioning idle_compact_after_seconds.

        `idle_compact_after_seconds` is an opt-in trigger. Default `0` disables it.
        Values above zero represent elapsed idle seconds.
        """
        let excerpt = try XCTUnwrap(
            DocumentationExcerptExtractor.bestExcerpt(
                for: "compression.idle_compact_after_seconds",
                in: document
            )
        )
        XCTAssertTrue(excerpt.text.contains("Default `0` disables it"))
        XCTAssertFalse(excerpt.text.contains("unrelated prose"))
    }

    func testHostedDocumentationExtractorPreservesCanonicalSource() throws {
        let corpus = """
        <!-- source: website/docs/user-guide/configuration.md -->
        # Configuration

        `idle_compact_after_seconds` is an opt-in trigger. Default `0` disables it.
        """
        let excerpts = DocumentationExcerptExtractor.hostedExcerpts(
            for: ["compression.idle_compact_after_seconds"],
            corpus: corpus,
            canonicalBaseURL: URL(string: "https://hermes-agent.nousresearch.com/docs/")!
        )
        let excerpt = try XCTUnwrap(excerpts.first)
        XCTAssertEqual(
            excerpt.sourceURL.absoluteString,
            "https://hermes-agent.nousresearch.com/docs/user-guide/configuration"
        )
        XCTAssertEqual(excerpt.origin, .hosted)
    }
}
