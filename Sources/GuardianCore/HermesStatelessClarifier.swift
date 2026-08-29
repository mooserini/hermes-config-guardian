import Foundation

public enum HermesStatelessClarifierError: Error, LocalizedError, Equatable {
    case unavailable
    case invalidPayload
    case timedOut
    case failed(Int32)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The Hermes stateless runtime is unavailable."
        case .invalidPayload:
            return "Guardian could not prepare the clarification request."
        case .timedOut:
            return "The Hermes stateless clarification timed out."
        case let .failed(status):
            return "The Hermes stateless clarification failed with status \(status)."
        case .emptyResponse:
            return "Hermes returned an empty clarification."
        }
    }
}

/// A deliberately narrow bridge to Hermes' internal stateless LLM helper.
///
/// Unlike `hermes -z`, this helper does not construct an agent, load tools,
/// create a session, or write conversation history. The bounded request is
/// supplied over standard input so configuration fragments never appear in
/// the process argument list.
public struct HermesStatelessClarifier: Sendable {
    public let pythonURL: URL
    public let agentDirectory: URL
    public let timeout: TimeInterval

    public init(pythonURL: URL, agentDirectory: URL, timeout: TimeInterval = 45) {
        self.pythonURL = pythonURL
        self.agentDirectory = agentDirectory
        self.timeout = max(timeout, 1)
    }

    public static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HermesStatelessClarifier? {
        let hermesHome = URL(
            fileURLWithPath: environment["HCG_HERMES_HOME"]
                ?? homeDirectory.appendingPathComponent(".hermes", isDirectory: true).path,
            isDirectory: true
        )
        let agentDirectory = URL(
            fileURLWithPath: environment["HCG_HERMES_AGENT_DIR"]
                ?? hermesHome.appendingPathComponent("hermes-agent", isDirectory: true).path,
            isDirectory: true
        )
        let pythonURL = URL(
            fileURLWithPath: environment["HCG_HERMES_PYTHON"]
                ?? agentDirectory.appendingPathComponent(".venv/bin/python").path
        )

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: agentDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: pythonURL.path),
              FileManager.default.fileExists(
                atPath: agentDirectory.appendingPathComponent("agent/oneshot.py").path
              ) else {
            return nil
        }

        let configuredTimeout = environment["HCG_HERMES_CLARIFY_TIMEOUT"]
            .flatMap(TimeInterval.init) ?? 45
        return HermesStatelessClarifier(
            pythonURL: pythonURL,
            agentDirectory: agentDirectory,
            timeout: configuredTimeout
        )
    }

    public func explain(instructions: String, evidence: String) async throws -> String {
        let request = Request(instructions: instructions, evidence: evidence)
        guard let input = try? JSONEncoder().encode(request) else {
            throw HermesStatelessClarifierError.invalidPayload
        }

        return try await Task.detached(priority: .userInitiated) {
            try run(input: input)
        }.value
    }

    private func run(input: Data) throws -> String {
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = pythonURL
        process.currentDirectoryURL = agentDirectory
        process.arguments = ["-c", Self.adapter]
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw HermesStatelessClarifierError.unavailable
        }

        standardInput.fileHandleForWriting.write(input)
        try? standardInput.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            throw HermesStatelessClarifierError.timedOut
        }

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        _ = standardError.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw HermesStatelessClarifierError.failed(process.terminationStatus)
        }
        guard output.count <= 64 * 1024,
              let response = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !response.isEmpty else {
            throw HermesStatelessClarifierError.emptyResponse
        }
        return response
    }

    private struct Request: Codable {
        let instructions: String
        let evidence: String
    }

    private static let adapter = #"""
import json
import logging
import sys

logging.disable(logging.CRITICAL)
payload = json.load(sys.stdin)

from agent.oneshot import run_oneshot

result = run_oneshot(
    instructions=payload["instructions"],
    user_input=payload["evidence"],
    task="guardian_clarify",
    max_tokens=700,
    temperature=0.1,
    timeout=40.0,
)
sys.stdout.write(result)
"""#
}
