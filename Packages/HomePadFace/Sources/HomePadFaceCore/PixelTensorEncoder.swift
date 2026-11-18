import Foundation

/// How pixel values are turned into the numbers a model expects when the model takes a tensor
/// instead of an image. Each channel value `v` in 0...255 becomes `(v * scale - mean) / deviation`.
public struct EmbedderPreprocessing: Equatable, Sendable {
    public enum ChannelOrder: String, Equatable, Sendable {
        case rgb, bgr
    }

    public var channelOrder: ChannelOrder
    public var scale: Float
    /// Per channel, in red, green, blue order.
    public var mean: [Float]
    /// Per channel, in red, green, blue order.
    public var deviation: [Float]

    public init(channelOrder: ChannelOrder = .rgb, scale: Float, mean: [Float], deviation: [Float]) {
        self.channelOrder = channelOrder
        self.scale = scale
        self.mean = mean
        self.deviation = deviation
    }

    /// Values in -1...1, the usual input of ArcFace, MobileFaceNet, and FaceNet exports.
    public static let signedUnit = EmbedderPreprocessing(scale: 1 / 127.5, mean: [1, 1, 1], deviation: [1, 1, 1])
    /// Values in 0...1.
    public static let unitRange = EmbedderPreprocessing(scale: 1 / 255, mean: [0, 0, 0], deviation: [1, 1, 1])
    /// Values in 0...255, for models that normalize internally.
    public static let raw = EmbedderPreprocessing(scale: 1, mean: [0, 0, 0], deviation: [1, 1, 1])
    /// ImageNet statistics, used by some torchvision-based exports.
    public static let imageNet = EmbedderPreprocessing(
        scale: 1 / 255,
        mean: [0.485, 0.456, 0.406],
        deviation: [0.229, 0.224, 0.225]
    )
}

public enum TensorLayout: String, Equatable, Sendable {
    /// Channel, row, column. Shape 3 x H x W.
    case channelsFirst
    /// Row, column, channel. Shape H x W x 3.
    case channelsLast
}

public enum PixelTensorEncoder {
    /// Converts BGRA bytes (the layout of a 32BGRA pixel buffer) to a flat float tensor.
    /// Returns `nil` when the buffer is too small for the stated geometry or the preprocessing
    /// does not describe three channels.
    public static func encode(
        bgra: UnsafeRawBufferPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        preprocessing: EmbedderPreprocessing,
        layout: TensorLayout
    ) -> [Float]? {
        guard
            width > 0, height > 0, bytesPerRow >= width * 4,
            bgra.count >= bytesPerRow * (height - 1) + width * 4,
            preprocessing.mean.count == 3, preprocessing.deviation.count == 3,
            preprocessing.deviation.allSatisfy({ $0 != 0 })
        else { return nil }
        // Byte offset of red, green, blue inside a BGRA pixel, in the order the model wants.
        let offsets = preprocessing.channelOrder == .rgb ? [2, 1, 0] : [0, 1, 2]
        let statistics = preprocessing.channelOrder == .rgb ? [0, 1, 2] : [2, 1, 0]
        let plane = width * height
        var tensor = [Float](repeating: 0, count: plane * 3)
        for row in 0..<height {
            for column in 0..<width {
                let pixel = row * bytesPerRow + column * 4
                for channel in 0..<3 {
                    let statistic = statistics[channel]
                    let value = (Float(bgra[pixel + offsets[channel]]) * preprocessing.scale - preprocessing.mean[statistic])
                        / preprocessing.deviation[statistic]
                    let index = layout == .channelsFirst
                        ? channel * plane + row * width + column
                        : (row * width + column) * 3 + channel
                    tensor[index] = value
                }
            }
        }
        return tensor
    }
}
