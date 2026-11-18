import CoreML
import CoreVideo
import Foundation
import HomePadFaceCore

/// Runs any Core ML model that takes one image (or one image-shaped tensor) and returns one
/// float vector.
public final class CoreMLFaceEmbedder: FaceEmbedder {
    public struct Configuration: Equatable, Sendable {
        /// How to feed and judge the model. `nil` picks the SFace profile when the model has the
        /// SFace contract and the generic profile otherwise.
        public var profile: EmbedderModelProfile?
        /// Overrides the thresholds of the profile, for a model calibrated on its own data.
        public var matchPolicy: MatchPolicy?
        /// Names the input and output to use when the model has several.
        public var inputName: String?
        public var outputName: String?
        public var computeUnits: MLComputeUnits

        public init(
            profile: EmbedderModelProfile? = nil,
            matchPolicy: MatchPolicy? = nil,
            inputName: String? = nil,
            outputName: String? = nil,
            computeUnits: MLComputeUnits = .all
        ) {
            self.profile = profile
            self.matchPolicy = matchPolicy
            self.inputName = inputName
            self.outputName = outputName
            self.computeUnits = computeUnits
        }

        /// Inspect the model and choose.
        public static let automatic = Configuration()
        /// SFace from the OpenCV Model Zoo with its preprocessing baked in.
        public static let sFace = Configuration(profile: .sFace, outputName: EmbedderModelProfile.sFaceShape.outputName)
    }

    private enum Input: Sendable {
        case image
        case tensor(shape: [Int], layout: TensorLayout)
    }

    public let modelID: String
    public let displayName: String
    public let inputSide: Int
    public let matchPolicy: MatchPolicy
    public let isDevelopmentFallback = false

    private let inputName: String
    private let outputName: String
    private let input: Input
    private let preprocessing: EmbedderPreprocessing
    private let model: LockedModel

    /// Loads `<name>.mlmodelc` from `bundle`.
    public convenience init(
        named name: String = FaceEmbedderFactory.bundledModelName,
        bundle: Bundle = .main,
        configuration: Configuration = .automatic
    ) throws(FaceEmbedderError) {
        guard let url = bundle.url(forResource: name, withExtension: "mlmodelc") else {
            throw .modelNotFound(name)
        }
        try self.init(compiledModelURL: url, configuration: configuration)
    }

    /// Loads a compiled model (`.mlmodelc`). The model name is the file name without extension.
    public init(compiledModelURL url: URL, configuration: Configuration = .automatic) throws(FaceEmbedderError) {
        let modelConfiguration = MLModelConfiguration()
        modelConfiguration.computeUnits = configuration.computeUnits
        guard let model = try? MLModel(contentsOf: url, configuration: modelConfiguration) else {
            throw .modelLoadFailed
        }
        let description = model.modelDescription
        let name = url.deletingPathExtension().lastPathComponent

        let inputs = description.inputDescriptionsByName
        guard let inputFeature = configuration.inputName.flatMap({ inputs[$0] })
            ?? inputs.values.first(where: { $0.type == .image })
            ?? inputs.values.first(where: { $0.type == .multiArray })
        else {
            throw .unsupportedModel(reason: "no image or tensor input")
        }
        let outputs = description.outputDescriptionsByName
        guard let outputFeature = configuration.outputName.flatMap({ outputs[$0] })
            ?? outputs.values.first(where: { $0.type == .multiArray })
        else {
            throw .unsupportedModel(reason: "no multi-array output")
        }

        let side: Int
        let input: Input
        if let constraint = inputFeature.imageConstraint {
            guard constraint.pixelsWide == constraint.pixelsHigh, constraint.pixelsWide > 0 else {
                throw .unsupportedModel(reason: "image input is not square")
            }
            guard constraint.pixelFormatType != kCVPixelFormatType_OneComponent8 else {
                throw .unsupportedModel(reason: "grayscale image input")
            }
            side = constraint.pixelsWide
            input = .image
        } else if let constraint = inputFeature.multiArrayConstraint {
            let shape = constraint.shape.map(\.intValue)
            let dimensions = Array(shape.suffix(3))
            guard dimensions.count == 3 else {
                throw .unsupportedModel(reason: "tensor input is not image shaped")
            }
            let layout: TensorLayout
            if dimensions[0] == 3, dimensions[1] == dimensions[2] {
                layout = .channelsFirst
                side = dimensions[1]
            } else if dimensions[2] == 3, dimensions[0] == dimensions[1] {
                layout = .channelsLast
                side = dimensions[0]
            } else {
                throw .unsupportedModel(reason: "tensor input is not a square three-channel image")
            }
            guard side > 0 else {
                throw .unsupportedModel(reason: "tensor input has no fixed size")
            }
            input = .tensor(shape: shape, layout: layout)
        } else {
            throw .unsupportedModel(reason: "input is neither an image nor a tensor")
        }

        self.inputName = inputFeature.name
        self.outputName = outputFeature.name
        self.input = input
        self.inputSide = side
        self.model = LockedModel(model)

        // The declared output shape can be empty or flexible, so the vector size is taken from a
        // real prediction. This also pays the model's first-run cost before the first face.
        guard let blank = PixelBufferFactory.makeBGRA(side: side) else {
            throw .predictionFailed
        }
        // Only a tensor input is preprocessed here, and automatic selection never picks a
        // tensor profile, so the preprocessing is known before the profile is resolved.
        let preprocessing = (configuration.profile ?? .generic).preprocessing
        self.preprocessing = preprocessing
        let dimension = try Self.run(
            model: self.model,
            crop: blank,
            input: input,
            inputName: inputFeature.name,
            outputName: outputFeature.name,
            preprocessing: preprocessing
        ).count
        guard dimension > 0 else {
            throw .unsupportedModel(reason: "output vector is empty")
        }

        let shape = EmbedderModelShape(
            inputIsImage: inputFeature.type == .image,
            inputWidth: side,
            inputHeight: side,
            outputName: outputFeature.name,
            outputDimension: dimension
        )
        let profile = configuration.profile ?? EmbedderModelProfile.resolve(for: shape)
        self.modelID = profile.modelID(modelName: name, dimension: dimension)
        self.matchPolicy = configuration.matchPolicy ?? profile.matchPolicy
        self.displayName = profile == .sFace ? "SFace (Core ML)" : "\(name) (Core ML, \(dimension) values)"
    }

    public func embedding(forAlignedFace crop: CVPixelBuffer) throws(FaceEmbedderError) -> FaceEmbedding {
        let values = try Self.run(
            model: model,
            crop: crop,
            input: input,
            inputName: inputName,
            outputName: outputName,
            preprocessing: preprocessing
        )
        do {
            return try FaceEmbedding(modelID: modelID, values: values)
        } catch {
            throw .invalidOutput(error)
        }
    }

    private static func run(
        model: LockedModel,
        crop: CVPixelBuffer,
        input: Input,
        inputName: String,
        outputName: String,
        preprocessing: EmbedderPreprocessing
    ) throws(FaceEmbedderError) -> [Float] {
        let value: MLFeatureValue
        switch input {
        case .image:
            value = MLFeatureValue(pixelBuffer: crop)
        case .tensor(let shape, let layout):
            guard let tensor = PixelBufferFactory.tensor(from: crop, preprocessing: preprocessing, layout: layout) else {
                throw .predictionFailed
            }
            value = MLFeatureValue(shapedArray: MLShapedArray<Float>(scalars: tensor, shape: shape))
        }
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: value]) else {
            throw .predictionFailed
        }
        guard let scalars = model.vector(named: outputName, from: provider) else { throw .predictionFailed }
        return scalars
    }
}

/// MLModel is not marked Sendable and must be used from one thread at a time. This box is the
/// only holder of the model and takes its lock around every prediction, which is what makes
/// sharing it across threads safe.
private final class LockedModel: @unchecked Sendable {
    private let model: MLModel
    private let lock = NSLock()

    init(_ model: MLModel) {
        self.model = model
    }

    func vector(named outputName: String, from provider: any MLFeatureProvider) -> [Float]? {
        lock.withLock {
            guard
                let result = try? model.prediction(from: provider),
                let array = result.featureValue(for: outputName)?.multiArrayValue
            else { return nil }
            return MLShapedArray<Float>(converting: array).scalars
        }
    }
}

enum PixelBufferFactory {
    /// A zero-filled 32BGRA buffer that Core ML, Core Image, and Vision can all use.
    static func makeBGRA(side: Int) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
            kCVPixelBufferCGImageCompatibilityKey: true,
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    static func tensor(from buffer: CVPixelBuffer, preprocessing: EmbedderPreprocessing, layout: TensorLayout) -> [Float]? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        return PixelTensorEncoder.encode(
            bgra: UnsafeRawBufferPointer(start: base, count: bytesPerRow * height),
            width: CVPixelBufferGetWidth(buffer),
            height: height,
            bytesPerRow: bytesPerRow,
            preprocessing: preprocessing,
            layout: layout
        )
    }
}
