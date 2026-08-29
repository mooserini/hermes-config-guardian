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

public struct HermesClarification: Sendable, Equatable {
    public let text: String
    public let provider: String
    public let model: String
    public let reasoningEffort: String
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
    public let provider: String?
    public let model: String?

    public init(
        pythonURL: URL,
        agentDirectory: URL,
        timeout: TimeInterval = 45,
        provider: String? = nil,
        model: String? = nil
    ) {
        self.pythonURL = pythonURL
        self.agentDirectory = agentDirectory
        self.timeout = max(timeout, 1)
        self.provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
            timeout: configuredTimeout,
            provider: environment["HCG_HERMES_CLARIFY_PROVIDER"],
            model: environment["HCG_HERMES_CLARIFY_MODEL"]
        )
    }

    public func explain(instructions: String, evidence: String) async throws -> HermesClarification {
        guard (provider == nil) == (model == nil) else {
            throw HermesStatelessClarifierError.invalidPayload
        }
        let request = Request(
            instructions: instructions,
            evidence: evidence,
            provider: provider,
            model: model,
            reasoningEffort: "low"
        )
        guard let input = try? JSONEncoder().encode(request) else {
            throw HermesStatelessClarifierError.invalidPayload
        }

        return try await Task.detached(priority: .userInitiated) {
            try run(input: input)
        }.value
    }

    private func run(input: Data) throws -> HermesClarification {
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
              let response = try? JSONDecoder().decode(Response.self, from: output),
              !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HermesStatelessClarifierError.emptyResponse
        }
        return HermesClarification(
            text: response.text.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: response.provider,
            model: response.model,
            reasoningEffort: response.reasoningEffort
        )
    }

    private struct Request: Codable {
        let instructions: String
        let evidence: String
        let provider: String?
        let model: String?
        let reasoningEffort: String
    }

    private struct Response: Codable {
        let text: String
        let provider: String
        let model: String
        let reasoningEffort: String
    }

    private static let adapter = #"""
import json
import logging
import sys

logging.disable(logging.CRITICAL)
payload = json.load(sys.stdin)

from agent.auxiliary_client import call_llm, extract_content_or_reasoning

route_provider = payload.get("provider")
route_model = payload.get("model")
if not route_provider and not route_model:
    from hermes_cli.models import get_nous_recommended_aux_model
    route_provider = "nous"
    route_model = get_nous_recommended_aux_model(free_tier=True)
    if not route_model:
        raise RuntimeError("Nous did not publish a free auxiliary model")

from hermes_cli.runtime_provider import resolve_runtime_provider
main_runtime = resolve_runtime_provider(
    requested=route_provider,
    target_model=route_model,
)
main_runtime["model"] = route_model

reasoning_config = None
reasoning_effort = "provider-default"
if route_provider == "nous":
    from hermes_cli.models import nous_model_reasoning_capabilities
    capabilities = nous_model_reasoning_capabilities(
        route_model,
        allow_fetch=True,
    )
    if capabilities and capabilities.get("supports_reasoning"):
        reasoning_effort = payload.get("reasoningEffort") or "low"
        reasoning_config = {
            "enabled": True,
            "effort": reasoning_effort,
        }
    elif capabilities and not capabilities.get("supports_reasoning"):
        reasoning_effort = "not-supported"

response = call_llm(
    task="guardian_clarify",
    messages=[
        {"role": "system", "content": payload["instructions"]},
        {"role": "user", "content": payload["evidence"]},
    ],
    max_tokens=700,
    temperature=0.1,
    timeout=40.0,
    main_runtime=main_runtime,
    reasoning_config=reasoning_config,
)
result = (extract_content_or_reasoning(response) or "").strip()
sys.stdout.write(json.dumps({
    "text": result,
    "provider": route_provider,
    "model": route_model,
    "reasoningEffort": reasoning_effort,
}))
"""#
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
