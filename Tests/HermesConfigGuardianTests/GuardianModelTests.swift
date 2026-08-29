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
}
