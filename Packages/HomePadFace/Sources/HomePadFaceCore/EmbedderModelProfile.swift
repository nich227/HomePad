import Foundation

/// What a loaded embedding model looks like from the outside.
public struct EmbedderModelShape: Equatable, Sendable {
    public let inputIsImage: Bool
    public let inputWidth: Int
    public let inputHeight: Int
    public let outputName: String
    public let outputDimension: Int

    public init(inputIsImage: Bool, inputWidth: Int, inputHeight: Int, outputName: String, outputDimension: Int) {
        self.inputIsImage = inputIsImage
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputName = outputName
        self.outputDimension = outputDimension
    }
}

/// How to feed and judge one family of embedding models.
public struct EmbedderModelProfile: Equatable, Sendable {
    /// First component of the model ID, so templates from different families never compare.
    public var family: String
    public var matchPolicy: MatchPolicy
    /// Used only when the model takes a tensor. An image input gets the pixel buffer as is.
    public var preprocessing: EmbedderPreprocessing

    public init(family: String, matchPolicy: MatchPolicy, preprocessing: EmbedderPreprocessing) {
        self.family = family
        self.matchPolicy = matchPolicy
        self.preprocessing = preprocessing
    }

    /// SFace from the OpenCV Model Zoo, converted with its preprocessing baked in: a 112 by 112
    /// RGB image with raw 0...255 values in, 128 floats named `embedding` out.
    public static let sFace = EmbedderModelProfile(family: "sface", matchPolicy: .sFace, preprocessing: .raw)

    /// Any other model with one image or tensor input and one float vector output. Uses the
    /// strict uncalibrated thresholds.
    public static let generic = EmbedderModelProfile(
        family: "coreml",
        matchPolicy: .conservativeDefault,
        preprocessing: .signedUnit
    )

    public static let sFaceShape = EmbedderModelShape(
        inputIsImage: true,
        inputWidth: 112,
        inputHeight: 112,
        outputName: "embedding",
        outputDimension: 128
    )

    /// The SFace profile when the model has exactly the SFace contract, otherwise the generic one.
    public static func resolve(for shape: EmbedderModelShape) -> EmbedderModelProfile {
        shape == sFaceShape ? .sFace : .generic
    }

    /// Identifies the embedding space: family, model name, and vector size.
    public func modelID(modelName: String, dimension: Int) -> String {
        "\(family).\(modelName).\(dimension)"
    }
}
