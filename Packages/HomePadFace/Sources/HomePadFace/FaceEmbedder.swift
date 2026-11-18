import CoreVideo
import Foundation
import HomePadFaceCore

public enum FaceEmbedderError: Error, Equatable, Sendable {
    /// No compiled model with this name is in the bundle.
    case modelNotFound(String)
    case modelLoadFailed
    /// The model does not have one image or tensor input and one float vector output.
    case unsupportedModel(reason: String)
    case predictionFailed
    case invalidOutput(FaceEmbeddingError)
}

/// Turns an aligned face crop into an embedding.
public protocol FaceEmbedder: Sendable {
    /// Identifies the embedding space. Templates are only matched against embeddings with the
    /// same model ID.
    var modelID: String { get }
    /// Shown to the person setting up the hub.
    var displayName: String { get }
    /// Side of the square crop the model expects, in pixels.
    var inputSide: Int { get }
    /// Thresholds for this model.
    var matchPolicy: MatchPolicy { get }
    /// True for an embedder that is not a face identity model and must not ship.
    var isDevelopmentFallback: Bool { get }

    /// Blocks while the model runs, so call it off the main actor. `crop` is a 32BGRA buffer of
    /// `inputSide` by `inputSide` pixels.
    func embedding(forAlignedFace crop: CVPixelBuffer) throws(FaceEmbedderError) -> FaceEmbedding
}

/// The embedder the app ended up with, and why.
public struct ActiveFaceEmbedder: Sendable {
    public enum Kind: Equatable, Sendable {
        case coreML(modelName: String)
        case featurePrintFallback
    }

    public let embedder: any FaceEmbedder
    public let kind: Kind
    /// Why a bundled model could not be used, when there was one. `nil` when the model loaded or
    /// when no model is bundled at all.
    public let loadFailure: FaceEmbedderError?

    public init(embedder: any FaceEmbedder, kind: Kind, loadFailure: FaceEmbedderError? = nil) {
        self.embedder = embedder
        self.kind = kind
        self.loadFailure = loadFailure
    }
}

public enum FaceEmbedderFactory {
    /// The app bundles its Core ML model under this name.
    public static let bundledModelName = "FaceEmbedder"

    /// Loads the default embedder off the main actor. Loading compiles the model for the device
    /// and runs it once, which can take a moment at first launch.
    public static func loadDefault(configuration: CoreMLFaceEmbedder.Configuration = .automatic) async -> ActiveFaceEmbedder {
        await Task.detached(priority: .userInitiated) {
            makeDefault(configuration: configuration)
        }.value
    }

    /// Uses the bundled Core ML model when the bundle has one that loads, otherwise the
    /// development fallback. Blocks while the model loads.
    public static func makeDefault(
        bundle: Bundle = .main,
        configuration: CoreMLFaceEmbedder.Configuration = .automatic
    ) -> ActiveFaceEmbedder {
        do {
            let embedder = try CoreMLFaceEmbedder(named: bundledModelName, bundle: bundle, configuration: configuration)
            return ActiveFaceEmbedder(embedder: embedder, kind: .coreML(modelName: bundledModelName))
        } catch .modelNotFound {
            return ActiveFaceEmbedder(embedder: FeaturePrintFaceEmbedder(), kind: .featurePrintFallback)
        } catch {
            return ActiveFaceEmbedder(embedder: FeaturePrintFaceEmbedder(), kind: .featurePrintFallback, loadFailure: error)
        }
    }
}
