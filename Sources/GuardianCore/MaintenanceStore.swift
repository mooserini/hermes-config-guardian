import Foundation

public struct MaintenanceManifest: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let sourcePath: String
    public let startedAt: Date
    public let approvedHash: String
    public let checkpointFileName: String
    public let reason: String
}

public struct MaintenanceObservation: Codable, Equatable, Sendable {
    public let observedAt: Date
    public let fingerprint: String
}

public struct MaintenanceWindow: Sendable {
    public let manifest: MaintenanceManifest
    public let checkpointData: Data
}

public enum MaintenanceStoreError: LocalizedError {
    case alreadyActive
    case missingCheckpoint
    case checkpointHashMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .alreadyActive:
            return "A maintenance window is already active."
        case .missingCheckpoint:
            return "The maintenance checkpoint is missing."
        case let .checkpointHashMismatch(expected, actual):
            return "The maintenance checkpoint failed verification (expected \(expected), found \(actual))."
        }
    }
}

public final class MaintenanceStore: @unchecked Sendable {
    public let stateDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(stateDirectory: URL, fileManager: FileManager = .default) {
        self.stateDirectory = stateDirectory
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    public func begin(
        sourceURL: URL,
        approvedSnapshot: ApprovedSnapshot,
        reason: String = "Hermes update",
        at date: Date = Date()
    ) throws -> MaintenanceWindow {
        try prepareDirectories()
        guard !fileManager.fileExists(atPath: manifestURL.path) else {
            throw MaintenanceStoreError.alreadyActive
        }

        let actualHash = ApprovalStore.sha256(approvedSnapshot.data)
        guard actualHash == approvedSnapshot.manifest.approvedHash else {
            throw MaintenanceStoreError.checkpointHashMismatch(
                expected: approvedSnapshot.manifest.approvedHash,
                actual: actualHash
            )
        }

        let stamp = Self.timestampFormatter.string(from: date)
        let checkpointName = "pre-update-\(stamp)-\(actualHash.prefix(12)).yaml"
        let checkpointURL = checkpointsDirectory.appendingPathComponent(checkpointName)
        if !fileManager.fileExists(atPath: checkpointURL.path) {
            try approvedSnapshot.data.write(to: checkpointURL, options: .atomic)
            try secure(checkpointURL, permissions: 0o600)
        }

        try? fileManager.removeItem(at: observationsURL)
        let manifest = MaintenanceManifest(
            formatVersion: 1,
            sourcePath: sourceURL.standardizedFileURL.path,
            startedAt: date,
            approvedHash: actualHash,
            checkpointFileName: checkpointName,
            reason: reason
        )
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try secure(manifestURL, permissions: 0o600)
        return MaintenanceWindow(manifest: manifest, checkpointData: approvedSnapshot.data)
    }

    public func loadActive() throws -> MaintenanceWindow? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let manifest = try decoder.decode(
            MaintenanceManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let checkpointURL = checkpointsDirectory
            .appendingPathComponent(manifest.checkpointFileName)
        guard fileManager.fileExists(atPath: checkpointURL.path) else {
            throw MaintenanceStoreError.missingCheckpoint
        }
        let data = try Data(contentsOf: checkpointURL)
        let actualHash = ApprovalStore.sha256(data)
        guard actualHash == manifest.approvedHash else {
            throw MaintenanceStoreError.checkpointHashMismatch(
                expected: manifest.approvedHash,
                actual: actualHash
            )
        }
        return MaintenanceWindow(manifest: manifest, checkpointData: data)
    }

    @discardableResult
    public func recordObservation(
        fingerprint: String,
        at date: Date = Date()
    ) throws -> Int {
        try prepareDirectories()
        _ = try loadActive().unwrap(or: MaintenanceStoreError.missingCheckpoint)
        var observations = try loadObservations()
        guard !observations.contains(where: { $0.fingerprint == fingerprint }) else {
            return observations.count
        }
        observations.append(MaintenanceObservation(observedAt: date, fingerprint: fingerprint))
        let lines = try observations.map { observation in
            String(decoding: try encoder.encode(observation), as: UTF8.self)
                .replacingOccurrences(of: "\n", with: "")
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8)
            .write(to: observationsURL, options: .atomic)
        try secure(observationsURL, permissions: 0o600)
        return observations.count
    }

    public func observationCount() throws -> Int {
        try loadObservations().count
    }

    public func restoreCheckpoint(_ window: MaintenanceWindow, to sourceURL: URL) throws {
        let actualHash = ApprovalStore.sha256(window.checkpointData)
        guard actualHash == window.manifest.approvedHash else {
            throw MaintenanceStoreError.checkpointHashMismatch(
                expected: window.manifest.approvedHash,
                actual: actualHash
            )
        }
        try window.checkpointData.write(to: sourceURL, options: .atomic)
        try secure(sourceURL, permissions: 0o600)
    }

    public func endActive() throws {
        if let active = try loadActive() {
            let stamp = Self.timestampFormatter.string(from: active.manifest.startedAt)
            let sessionHistoryDirectory = historyDirectory
                .appendingPathComponent("\(stamp)-\(active.manifest.approvedHash.prefix(12))", isDirectory: true)
            try fileManager.createDirectory(
                at: sessionHistoryDirectory,
                withIntermediateDirectories: true
            )
            try secure(sessionHistoryDirectory, permissions: 0o700)
            let archivedManifest = sessionHistoryDirectory.appendingPathComponent("manifest.json")
            try Data(contentsOf: manifestURL).write(to: archivedManifest, options: .atomic)
            try secure(archivedManifest, permissions: 0o600)
            if fileManager.fileExists(atPath: observationsURL.path) {
                let archivedObservations = sessionHistoryDirectory
                    .appendingPathComponent("observed-proposals.jsonl")
                try Data(contentsOf: observationsURL)
                    .write(to: archivedObservations, options: .atomic)
                try secure(archivedObservations, permissions: 0o600)
            }
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        if fileManager.fileExists(atPath: observationsURL.path) {
            try fileManager.removeItem(at: observationsURL)
        }
    }

    private func loadObservations() throws -> [MaintenanceObservation] {
        guard fileManager.fileExists(atPath: observationsURL.path) else { return [] }
        return try String(contentsOf: observationsURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(MaintenanceObservation.self, from: Data($0.utf8)) }
    }

    private var maintenanceDirectory: URL {
        stateDirectory.appendingPathComponent("maintenance", isDirectory: true)
    }

    private var checkpointsDirectory: URL {
        maintenanceDirectory.appendingPathComponent("checkpoints", isDirectory: true)
    }

    private var historyDirectory: URL {
        maintenanceDirectory.appendingPathComponent("history", isDirectory: true)
    }

    private var manifestURL: URL {
        maintenanceDirectory.appendingPathComponent("current.json")
    }

    private var observationsURL: URL {
        maintenanceDirectory.appendingPathComponent("observed-proposals.jsonl")
    }

    private func prepareDirectories() throws {
        for directory in [
            stateDirectory,
            maintenanceDirectory,
            checkpointsDirectory,
            historyDirectory,
        ] {
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

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let self else { throw error() }
        return self
    }
}
