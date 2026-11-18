import Foundation
import FoundationModels
import Testing
@testable import HomePadAssistantCore

/// Records what this simulator or device reports for the system language model. It asserts
/// nothing about the model, because that depends on the machine. It runs only when
/// `HOMEPAD_ASSISTANT_PROBE_FILE` names a file to write the findings to.
@Suite struct SimulatorProbeTests {
    static let outputPath = ProcessInfo.processInfo.environment["HOMEPAD_ASSISTANT_PROBE_FILE"]

    @Test(.enabled(if: outputPath != nil))
    func probe_whenAFileIsNamed_thenWritesWhatTheSystemModelReports() async throws {
        let path = try #require(Self.outputPath)
        let model = SystemLanguageModel.default
        let status: SystemModelStatus = switch model.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled): .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady): .unavailable(.modelNotReady)
        case .unavailable: .unavailable(.other)
        }
        var lines = [
            "system status: \(status)",
            "assistant availability: \(AssistantAvailability(status))",
            "isAvailable: \(model.isAvailable)",
        ]
        do {
            let response = try await LanguageModelSession(model: model, instructions: "Reply with one word.").respond(to: "Say hello.")
            lines.append("respond: succeeded with \(response.content.count) characters")
        } catch {
            lines.append("respond: threw \(type(of: error)): \(error)")
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Kept apart from the probe above so that a failure here cannot hide its findings.
    @Test(.enabled(if: outputPath != nil))
    func probe_whenAFileIsNamed_thenWritesWhatPrivateCloudComputeReports() throws {
        let path = try #require(Self.outputPath)
        let line = "private cloud compute availability: \(PrivateCloudComputeLanguageModel().availability)"
        try line.write(toFile: path + ".pcc", atomically: true, encoding: .utf8)
    }
}
