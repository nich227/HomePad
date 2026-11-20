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
        lines.append("context size in tokens: \(model.contextSize)")
        // How many characters of a recipe request one token holds, to compare with the
        // number the request budget assumes.
        let recipe = RecipeDraft.sample
        let texts = [
            ("step instructions", RecipePrompt.stepInstructions),
            ("step prompt", RecipePrompt.steps(recipe, indices: Array(recipe.steps.indices)).prompt),
            ("ingredient prompt", RecipePrompt.ingredients(recipe, indices: Array(recipe.ingredients.indices)).prompt),
        ]
        for (name, text) in texts {
            do {
                let tokens = try await model.tokenCount(for: text)
                lines.append("token count, \(name): \(tokens) tokens for \(text.count) characters")
            } catch {
                lines.append("token count, \(name): threw \(type(of: error)): \(error)")
            }
        }
        do {
            let response = try await LanguageModelSession(model: model, instructions: "Reply with one word.").respond(to: "Say hello.")
            lines.append("respond: succeeded with \(response.content.count) characters")
        } catch {
            lines.append("respond: threw \(type(of: error)): \(error)")
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Tidies the sample recipe through the system model, asked the way the app asks it: a
    /// session of its own for each request, no tools, greedy sampling.
    @MainActor
    @Test(.enabled(if: outputPath != nil))
    func probe_whenAFileIsNamed_thenWritesWhatTidyingARecipeComesTo() async throws {
        let path = try #require(Self.outputPath)
        let model = ProbeRecipeModel()
        let outcome = await RecipeFormatter(model: model).format(draft: .sample, pageText: "")
        let lines = [
            "requests sent to the system model: \(model.requests)",
            "tidied by the model: \(outcome.wasTidiedByModel)",
            "failure: \(String(describing: outcome.failure))",
            "plain recipe is the draft that was given: \(outcome.original == RecipeDraft.sample)",
        ]
        try lines.joined(separator: "\n").write(toFile: path + ".recipe", atomically: true, encoding: .utf8)
    }

    /// Kept apart from the probe above so that a failure here cannot hide its findings.
    @Test(.enabled(if: outputPath != nil))
    func probe_whenAFileIsNamed_thenWritesWhatPrivateCloudComputeReports() throws {
        let path = try #require(Self.outputPath)
        let line = "private cloud compute availability: \(PrivateCloudComputeLanguageModel().availability)"
        try line.write(toFile: path + ".pcc", atomically: true, encoding: .utf8)
    }
}

/// The system model behind the recipe formatter's protocol. It asks for plain text, so on a
/// machine whose model answers it shows only that requests go through.
@MainActor
private final class ProbeRecipeModel: RecipeModel {
    private let model = SystemLanguageModel.default
    private(set) var requests = 0

    var contextTokens: Int {
        model.contextSize
    }

    private func ask(_ request: RecipeModelRequest) async throws {
        requests += 1
        do {
            _ = try await LanguageModelSession(model: model, instructions: Instructions(request.instructions)).respond(
                to: request.prompt,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: request.maximumResponseTokens)
            )
        } catch {
            throw AssistantFailure.unknown
        }
    }

    func locate(_ request: RecipeModelRequest) async throws -> RecipeModelLocation {
        try await ask(request)
        return RecipeModelLocation()
    }

    func overview(_ request: RecipeModelRequest) async throws -> RecipeModelOverview {
        try await ask(request)
        return RecipeModelOverview()
    }

    func steps(_ request: RecipeModelRequest) async throws -> [RecipeModelStep] {
        try await ask(request)
        return []
    }
}
