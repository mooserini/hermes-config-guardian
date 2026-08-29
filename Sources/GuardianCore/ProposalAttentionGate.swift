public struct ProposalAttentionGate: Sendable {
    public private(set) var lastNotifiedProposalHash: String?

    public init(lastNotifiedProposalHash: String? = nil) {
        self.lastNotifiedProposalHash = lastNotifiedProposalHash
    }

    public mutating func shouldNotify(proposalHash: String) -> Bool {
        guard proposalHash != lastNotifiedProposalHash else { return false }
        lastNotifiedProposalHash = proposalHash
        return true
    }

    public mutating func reset() {
        lastNotifiedProposalHash = nil
    }
}
