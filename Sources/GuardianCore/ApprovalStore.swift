import CryptoKit
import Foundation

public struct ApprovalManifest: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let sourcePath: String
    public let approvedHash: String
    public let snapshotFileName: String
    public let approvedAt: Date
}

public struct ApprovedSnapshot: Sendable {
    public let manifest: ApprovalManifest
    public let data: Data
}

public struct RejectionReceipt: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let sourcePath: String
    public let rejectedHash: String
    public let restoredHash: String
    public let changedPaths: [String]
    public let rejectedAt: Date
}

public enum ApprovalStoreError: LocalizedError {
    case missingSnapshot
    case hashMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingSnapshot:
            return "The approved snapshot is missing."
        case let .hashMismatch(expected, actual):
            return "The approved snapshot failed verification (expected \(expected), found \(actual))."
        }
    }
}

public final class ApprovalStore: @unchecked Sendable {
    public let stateDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(stateDirectory: URL, fileManager: FileManager = .default) {
        self.stateDirectory = stateDirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func loadApproved() throws -> ApprovedSnapshot? {
        let manifestURL = stateDirectory.appendingPathComponent("current.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }

        let manifest = try decoder.decode(ApprovalManifest.self, from: Data(contentsOf: manifestURL))
        let snapshotURL = stateDirectory
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(manifest.snapshotFileName)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            throw ApprovalStoreError.missingSnapshot
        }

        let data = try Data(contentsOf: snapshotURL)
        let actualHash = Self.sha256(data)
        guard actualHash == manifest.approvedHash else {
            throw ApprovalStoreError.hashMismatch(expected: manifest.approvedHash, actual: actualHash)
        }
        return ApprovedSnapshot(manifest: manifest, data: data)
    }

    @discardableResult
    public func approve(sourceURL: URL, data: Data, at date: Date = Date()) throws -> ApprovedSnapshot {
        try prepareDirectories()

        let hash = Self.sha256(data)
        let stamp = Self.timestampFormatter.string(from: date)
        let snapshotName = "approved-\(stamp)-\(hash.prefix(12)).yaml"
        let snapshotURL = stateDirectory
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(snapshotName)

        if !fileManager.fileExists(atPath: snapshotURL.path) {
            try data.write(to: snapshotURL, options: [.atomic])
            try secure(snapshotURL, permissions: 0o600)
        }

        let manifest = ApprovalManifest(
            formatVersion: 1,
            sourcePath: sourceURL.standardizedFileURL.path,
            approvedHash: hash,
            snapshotFileName: snapshotName,
            approvedAt: date
        )
        let manifestData = try encoder.encode(manifest)
        let manifestURL = stateDirectory.appendingPathComponent("current.json")
        try manifestData.write(to: manifestURL, options: [.atomic])
        try secure(manifestURL, permissions: 0o600)

        let receiptURL = stateDirectory
            .appendingPathComponent("receipts", isDirectory: true)
            .appendingPathComponent("approval-\(stamp)-\(hash.prefix(12)).json")
        if !fileManager.fileExists(atPath: receiptURL.path) {
            try manifestData.write(to: receiptURL, options: [.atomic])
            try secure(receiptURL, permissions: 0o600)
        }

        return ApprovedSnapshot(manifest: manifest, data: data)
    }

    public func restore(_ snapshot: ApprovedSnapshot, to sourceURL: URL) throws {
        let currentHash = Self.sha256(snapshot.data)
        guard currentHash == snapshot.manifest.approvedHash else {
            throw ApprovalStoreError.hashMismatch(
                expected: snapshot.manifest.approvedHash,
                actual: currentHash
            )
        }
        try snapshot.data.write(to: sourceURL, options: [.atomic])
        try secure(sourceURL, permissions: 0o600)
    }

    @discardableResult
    public func recordRejection(
        sourceURL: URL,
        rejectedData: Data,
        approvedSnapshot: ApprovedSnapshot,
        changedPaths: [String],
        at date: Date = Date()
    ) throws -> RejectionReceipt {
        try prepareDirectories()
        let receipt = RejectionReceipt(
            formatVersion: 1,
            sourcePath: sourceURL.standardizedFileURL.path,
            rejectedHash: Self.sha256(rejectedData),
            restoredHash: approvedSnapshot.manifest.approvedHash,
            changedPaths: changedPaths.sorted(),
            rejectedAt: date
        )
        let receiptData = try encoder.encode(receipt)
        let stamp = Self.timestampFormatter.string(from: date)
        let receiptURL = stateDirectory
            .appendingPathComponent("receipts", isDirectory: true)
            .appendingPathComponent("rejection-\(stamp)-\(receipt.rejectedHash.prefix(12)).json")
        try receiptData.write(to: receiptURL, options: [.atomic])
        try secure(receiptURL, permissions: 0o600)
        return receipt
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try secure(stateDirectory, permissions: 0o700)
        for name in ["snapshots", "receipts"] {
            let directory = stateDirectory.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try secure(directory, permissions: 0o700)
        }
    }

    private func secure(_ url: URL, permissions: Int) throws {
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()
}
