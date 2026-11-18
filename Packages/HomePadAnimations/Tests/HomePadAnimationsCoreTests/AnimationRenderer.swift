import CoreGraphics
import Foundation
import ImageIO
import Lottie
import QuartzCore
import UniformTypeIdentifiers
@testable import HomePadAnimationsCore

/// One rendered frame as premultiplied RGBA bytes, top row first.
struct Bitmap: Equatable {
    let side: Int
    let bytes: [UInt8]

    struct Pixel: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let offset = (y * side + x) * 4
        return Pixel(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
    }

    /// Pixels with any coverage.
    var inkedCount: Int {
        count { $0.alpha > 0 }
    }

    func count(where matches: (Pixel) -> Bool) -> Int {
        var total = 0
        for index in 0..<(side * side) {
            let offset = index * 4
            let pixel = Pixel(
                red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3]
            )
            if matches(pixel) { total += 1 }
        }
        return total
    }

    /// Lays frames out left to right on black, the way they look on the hub, and writes a PNG.
    static func writeSheet(_ frames: [Bitmap], to url: URL) throws {
        guard let side = frames.first?.side else { throw RenderError.cannotWrite }
        let width = side * frames.count
        var sheet = [UInt8](repeating: 0, count: width * side * 4)
        for (column, frame) in frames.enumerated() {
            for y in 0..<side {
                for x in 0..<side {
                    let source = (y * side + x) * 4
                    let target = (y * width + column * side + x) * 4
                    sheet[target] = frame.bytes[source]
                    sheet[target + 1] = frame.bytes[source + 1]
                    sheet[target + 2] = frame.bytes[source + 2]
                    sheet[target + 3] = 255
                }
            }
        }
        guard
            let provider = CGDataProvider(data: Data(sheet) as CFData),
            let image = CGImage(
                width: width, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw RenderError.cannotWrite }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.cannotWrite }
    }
}

enum RenderError: Error {
    case noContext
    case noContent
    case cannotWrite
}

/// Draws frames of a bundled animation into a bitmap on the host, with no window or screen.
/// It uses the main thread rendering engine, because that engine writes each frame into the
/// model layer tree, which is what `CALayer.render(in:)` draws.
@MainActor
struct AnimationRenderer {
    private let layer: LottieAnimationLayer
    private let side: Int

    init(_ animation: HomePadAnimation, tint: LottieColor? = nil) throws {
        let decoded = try LottieAnimation.from(data: animation.data())
        side = Int(decoded.bounds.width)
        layer = LottieAnimationLayer(
            animation: decoded,
            configuration: LottieConfiguration(renderingEngine: .mainThread),
            logger: LottieLogger(assert: { _, _, _, _ in }, assertionFailure: { _, _, _ in }, warn: { _, _, _ in })
        )
        if let tint {
            layer.setValueProvider(
                ColorValueProvider(tint),
                keypath: AnimationKeypath(keypath: HomePadAnimationKeypath.tintColor)
            )
        }
    }

    func frame(_ frame: Double) throws -> Bitmap {
        layer.currentFrame = frame
        layer.layoutIfNeeded()
        layer.forceDisplayUpdate()
        guard
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw RenderError.noContext }
        // Lottie lays content out with the origin at the top left, and a bare CALayer on the
        // host has it at the bottom left.
        context.translateBy(x: 0, y: CGFloat(side))
        context.scaleBy(x: 1, y: -1)
        // The animation's own layer draws in canvas coordinates. The wrapper layer does not
        // center it without a hosting view.
        guard let content = layer.sublayers?.first else { throw RenderError.noContent }
        content.render(in: context)
        guard let data = context.data else { throw RenderError.noContext }
        let buffer = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: side * side * 4)
        return Bitmap(side: side, bytes: Array(buffer))
    }
}
