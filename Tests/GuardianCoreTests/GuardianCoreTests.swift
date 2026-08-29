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

    func testSemanticDiffKeepsNumericTokenBudgetsVisible() throws {
        let old = try YAMLInspector.inspect(data: Data("compression:\n  proactive_prune_tokens: 0\nmodel:\n  max_tokens: 700\n".utf8))
        let new = try YAMLInspector.inspect(data: Data("compression:\n  proactive_prune_tokens: 8192\nmodel:\n  max_tokens: 512\n".utf8))
        let changes = SemanticDiffer.changes(from: old, to: new)

        XCTAssertEqual(changes.first { $0.path == "compression.proactive_prune_tokens" }?.before, "0")
        XCTAssertEqual(changes.first { $0.path == "compression.proactive_prune_tokens" }?.after, "8192")
        XCTAssertEqual(changes.first { $0.path == "model.max_tokens" }?.after, "512")
    }

    func testSensitivePathClassificationKeepsCredentialsRedacted() {
        XCTAssertTrue(SemanticDiffer.isSensitive("providers.nous.api_key"))
        XCTAssertTrue(SemanticDiffer.isSensitive("auth.refresh_token"))
        XCTAssertTrue(SemanticDiffer.isSensitive("hooks.webhook_url"))
        XCTAssertTrue(SemanticDiffer.isSensitive("secrets.unfamiliar_name"))
        XCTAssertFalse(SemanticDiffer.isSensitive("compression.proactive_prune_tokens"))
        XCTAssertFalse(SemanticDiffer.isSensitive("model.max_tokens"))
    }

    func testNumericValuesAreNotWrappedAsOptionals() throws {
        let document = try YAMLInspector.inspect(data: Data("compression:\n  idle_compact_after_seconds: 300\n".utf8))
        XCTAssertEqual(document.flattenedValues["compression.idle_compact_after_seconds"], "300")
    }

    func testRejectsInvalidYAMLAndNonMappingRoot() {
        XCTAssertThrowsError(try YAMLInspector.inspect(data: Data("model: [\n".utf8)))
        XCTAssertThrowsError(try YAMLInspector.inspect(data: Data("- one\n- two\n".utf8)))
    }

    func testRejectsTrailingGarbageAfterValidMapping() {
        let data = Data(
            """
            model:
              default: terra
            compression:
              idle_compact_after_seconds: 0
            display:
              tool_progress: all
            I SHIT MY PANTS HELP ME
            """.utf8
        )

        XCTAssertThrowsError(try YAMLInspector.inspect(data: data))
    }

    func testInvalidYAMLExcerptKeepsOnlyTheOffendingLine() throws {
        let data = Data(
            "model:\n  default: terra\nI SHIT MY PANTS HELP ME".utf8
        )

        do {
            _ = try YAMLInspector.inspect(data: data)
            XCTFail("Expected malformed YAML")
        } catch {
            let summary = InvalidYAMLExcerpt.summary(error: error)
            XCTAssertTrue(summary.hasPrefix("YAML syntax error at line "), summary)
            XCTAssertFalse(summary.contains("I SHIT MY PANTS"))
            XCTAssertEqual(
                InvalidYAMLExcerpt.extract(from: data, error: error),
                "I SHIT MY PANTS HELP ME"
            )
        }
    }

    func testInvalidYAMLExcerptRedactsLikelySecrets() throws {
        let data = Data(
            "model:\n  default: terra\napi_key sk-proj-123456789012345678901234567890".utf8
        )

        do {
            _ = try YAMLInspector.inspect(data: data)
            XCTFail("Expected malformed YAML")
        } catch {
            XCTAssertEqual(
                InvalidYAMLExcerpt.extract(from: data, error: error),
                "[redacted invalid line]"
            )
        }
    }

    func testInvalidYAMLExcerptCapsNaturalLanguageAndRedactsBareKeyPrefixes() throws {
        let longText = String(repeating: "ordinary words ", count: 30)
        let longData = Data("model:\n  default: terra\n\(longText)".utf8)
        let secretData = Data("model:\n  default: terra\nsk-proj-123456789012345678901234567890".utf8)

        do {
            _ = try YAMLInspector.inspect(data: longData)
            XCTFail("Expected malformed YAML")
        } catch {
            XCTAssertEqual(
                InvalidYAMLExcerpt.extract(from: longData, error: error)?.count,
                240
            )
        }

        do {
            _ = try YAMLInspector.inspect(data: secretData)
            XCTFail("Expected malformed YAML")
        } catch {
            XCTAssertEqual(
                InvalidYAMLExcerpt.extract(from: secretData, error: error),
                "[redacted invalid line]"
            )
        }
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

    func testProposalAttentionGateNotifiesOncePerDistinctProposal() {
        var gate = ProposalAttentionGate()

        XCTAssertTrue(gate.shouldNotify(proposalHash: "proposal-a"))
        XCTAssertFalse(gate.shouldNotify(proposalHash: "proposal-a"))
        XCTAssertTrue(gate.shouldNotify(proposalHash: "proposal-b"))

        var rehydratedGate = ProposalAttentionGate(lastNotifiedProposalHash: "proposal-b")
        XCTAssertFalse(rehydratedGate.shouldNotify(proposalHash: "proposal-b"))

        gate.reset()
        XCTAssertTrue(gate.shouldNotify(proposalHash: "proposal-b"))
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

    func testHermesStatelessClarifierDiscoveryUsesIsolatedHermesRuntime() throws {
        let home = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        let agent = home.appendingPathComponent(".hermes/hermes-agent", isDirectory: true)
        let python = agent.appendingPathComponent(".venv/bin/python")
        let helper = agent.appendingPathComponent("agent/oneshot.py")
        try FileManager.default.createDirectory(
            at: python.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: python)
        try Data("# test helper\n".utf8).write(to: helper)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: python.path
        )

        let clarifier = try XCTUnwrap(
            HermesStatelessClarifier.discover(environment: [:], homeDirectory: home)
        )
        XCTAssertEqual(clarifier.pythonURL.standardizedFileURL, python.standardizedFileURL)
        XCTAssertEqual(clarifier.agentDirectory.standardizedFileURL, agent.standardizedFileURL)
    }

    func testHermesStatelessClarifierSendsEvidenceOverStandardInput() async throws {
        let fakePython = try makeExecutable(
            named: "fake-python",
            contents: """
            #!/bin/sh
            case "$*" in
              *guardian-secret*|*laguna-xs*) exit 91 ;;
            esac
            payload=$(cat)
            case "$payload" in
              *guardian-secret*) ;;
              *) exit 92 ;;
            esac
            case "$payload" in
              *laguna-xs-2.1:free*) ;;
              *) exit 93 ;;
            esac
            case "$payload" in
              *reasoningEffort*low*) ;;
              *) exit 94 ;;
            esac
            printf '%s' '{"text":"Human explanation from Hermes.","provider":"nous","model":"poolside/laguna-xs-2.1:free","reasoningEffort":"low"}'
            """
        )
        let clarifier = HermesStatelessClarifier(
            pythonURL: fakePython,
            agentDirectory: temporaryDirectory,
            timeout: 2,
            provider: "nous",
            model: "poolside/laguna-xs-2.1:free"
        )

        let response = try await clarifier.explain(
            instructions: "Use only the supplied documentation.",
            evidence: "guardian-secret"
        )
        XCTAssertEqual(response.text, "Human explanation from Hermes.")
        XCTAssertEqual(response.provider, "nous")
        XCTAssertEqual(response.model, "poolside/laguna-xs-2.1:free")
        XCTAssertEqual(response.reasoningEffort, "low")
    }

    func testHermesStatelessClarifierRejectsHalfConfiguredRoutePin() async throws {
        let fakePython = try makeExecutable(
            named: "unused-python",
            contents: "#!/bin/sh\nexit 93\n"
        )
        let clarifier = HermesStatelessClarifier(
            pythonURL: fakePython,
            agentDirectory: temporaryDirectory,
            provider: "nous"
        )

        do {
            _ = try await clarifier.explain(instructions: "Explain.", evidence: "Evidence.")
            XCTFail("Expected an incomplete route pin to be rejected")
        } catch let error as HermesStatelessClarifierError {
            XCTAssertEqual(error, .invalidPayload)
        }
    }

    func testHermesStatelessClarifierTimesOut() async throws {
        let fakePython = try makeExecutable(
            named: "slow-python",
            contents: """
            #!/bin/sh
            cat >/dev/null
            sleep 3
            printf 'too late'
            """
        )
        let clarifier = HermesStatelessClarifier(
            pythonURL: fakePython,
            agentDirectory: temporaryDirectory,
            timeout: 1
        )

        do {
            _ = try await clarifier.explain(instructions: "Explain.", evidence: "Evidence.")
            XCTFail("Expected the stateless helper to time out")
        } catch let error as HermesStatelessClarifierError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testLiveHermesStatelessClarificationWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["HCG_LIVE_HERMES_TEST"] == "1" else {
            throw XCTSkip("Set HCG_LIVE_HERMES_TEST=1 to exercise authenticated Hermes inference.")
        }
        let clarifier = try XCTUnwrap(HermesStatelessClarifier.discover())
        let response = try await clarifier.explain(
            instructions: """
            Translate the Hermes configuration change into plain human language. Use only the supplied documentation. Preserve qualifiers exactly: never turn may or eligible behavior into will or unconditional behavior. Say what the person will notice, cite [1], and return only the explanation.
            """,
            evidence: """
            [1] Installed Hermes documentation
            idle_compact_after_seconds is an opt-in, time-based compaction trigger. A value of 0 disables idle-triggered compaction. A value above 0 means that when an eligible session resumes after at least that many seconds of inactivity, Hermes may compact accumulated history before the first reply.

            Proposed change:
            compression.idle_compact_after_seconds: 0 -> 300
            """
        )
        print("LIVE_HERMES_ROUTE: \(response.provider)/\(response.model) reasoning=\(response.reasoningEffort)")
        print("LIVE_HERMES_CLARIFICATION:\n\(response.text)")
        XCTAssertTrue(response.text.contains("[1]"))
        XCTAssertTrue(response.text.lowercased().contains("may"))
        XCTAssertFalse(response.text.isEmpty)
    }

    private func makeExecutable(named name: String, contents: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }
}
