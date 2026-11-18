// Checks a compiled FaceEmbedder model against ONNX Runtime reference embeddings.
//
// Usage:
//   xcrun coremlcompiler compile HomePad/Models/FaceEmbedder.mlpackage <tmpdir>
//   swift Scripts/verify-face-model.swift <tmpdir>/FaceEmbedder.mlmodelc Scripts/face-model-fixtures
//
// Options:
//   --compute-units cpu|all   Core ML compute units. Default: all.
//   --minimum-cosine <value>  Pass mark for each fixture. Default: 0.999.
//   --swap-red-blue           Writes red into the blue slot and blue into the red slot of the pixel
//                             buffer. This must make the check fail. Use it to show the check can
//                             detect a wrong channel order.
//
// Each PNG is decoded, its RGB bytes are hashed and compared with the hash in reference.json, and
// the pixels are copied into a 32BGRA CVPixelBuffer, which is what the app passes to the model.
// Exit status is 0 when every fixture passes and 1 otherwise.

import CoreGraphics
import CoreML
import CoreVideo
import CryptoKit
import Foundation
import ImageIO

struct ReferenceDocument: Decodable {
    struct Input: Decodable {
        let width: Int
        let height: Int
    }

    struct Fixture: Decodable {
        let file: String
        let rgb_sha256: String
        let embedding: [Double]
    }

    let input: Input
    let embedding_dimension: Int
    let fixtures: [Fixture]
}

struct Options {
    var modelURL: URL
    var fixturesURL: URL
    var computeUnits: MLComputeUnits = .all
    var computeUnitsName = "all"
    var minimumCosine = 0.999
    var swapRedBlue = false
}

enum VerifyError: Error, CustomStringConvertible {
    case usage(String)
    case unreadableImage(String)
    case pixelHashMismatch(file: String, expected: String, actual: String)
    case pixelBuffer(String)
    case modelContract(String)

    var description: String {
        switch self {
        case .usage(let message): return "usage error: \(message)"
        case .unreadableImage(let file): return "cannot decode \(file)"
        case .pixelHashMismatch(let file, let expected, let actual):
            return "\(file): decoded RGB bytes hash to \(actual), reference.json says \(expected)"
        case .pixelBuffer(let message): return "pixel buffer: \(message)"
        case .modelContract(let message): return "model contract: \(message)"
        }
    }
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var positional: [String] = []
    var computeUnits: MLComputeUnits = .all
    var computeUnitsName = "all"
    var minimumCosine = 0.999
    var swapRedBlue = false
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--swap-red-blue":
            swapRedBlue = true
        case "--compute-units":
            index += 1
            guard index < arguments.count else { throw VerifyError.usage("--compute-units needs a value") }
            computeUnitsName = arguments[index]
            switch computeUnitsName {
            case "cpu": computeUnits = .cpuOnly
            case "all": computeUnits = .all
            default: throw VerifyError.usage("--compute-units takes cpu or all")
            }
        case "--minimum-cosine":
            index += 1
            guard index < arguments.count, let value = Double(arguments[index]) else {
                throw VerifyError.usage("--minimum-cosine needs a number")
            }
            minimumCosine = value
        default:
            positional.append(argument)
        }
        index += 1
    }
    guard positional.count == 2 else {
        throw VerifyError.usage("expected <compiled.mlmodelc> <fixtures-dir>")
    }
    return Options(
        modelURL: URL(fileURLWithPath: positional[0]),
        fixturesURL: URL(fileURLWithPath: positional[1]),
        computeUnits: computeUnits,
        computeUnitsName: computeUnitsName,
        minimumCosine: minimumCosine,
        swapRedBlue: swapRedBlue
    )
}

/// Returns the image as tightly packed RGB bytes, row by row from the top.
func decodeRGB(_ url: URL, width: Int, height: Int) throws -> [UInt8] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == width, image.height == height
    else {
        throw VerifyError.unreadableImage(url.lastPathComponent)
    }
    // Drawing into the image's own color space keeps Core Graphics from color matching the pixels.
    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return false
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { throw VerifyError.unreadableImage(url.lastPathComponent) }
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    for pixel in 0..<(width * height) {
        rgb[pixel * 3] = rgba[pixel * 4]
        rgb[pixel * 3 + 1] = rgba[pixel * 4 + 1]
        rgb[pixel * 3 + 2] = rgba[pixel * 4 + 2]
    }
    return rgb
}

func makePixelBuffer(rgb: [UInt8], width: Int, height: Int, swapRedBlue: Bool) throws -> CVPixelBuffer {
    var created: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &created
    )
    guard status == kCVReturnSuccess, let buffer = created else {
        throw VerifyError.pixelBuffer("CVPixelBufferCreate returned \(status)")
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
        throw VerifyError.pixelBuffer("no base address")
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    for row in 0..<height {
        for column in 0..<width {
            let source = (row * width + column) * 3
            let destination = row * bytesPerRow + column * 4
            let red = rgb[source]
            let green = rgb[source + 1]
            let blue = rgb[source + 2]
            bytes[destination] = swapRedBlue ? red : blue
            bytes[destination + 1] = green
            bytes[destination + 2] = swapRedBlue ? blue : red
            bytes[destination + 3] = 255
        }
    }
    return buffer
}

func checkContract(_ model: MLModel, reference: ReferenceDocument) throws {
    let description = model.modelDescription
    guard let input = description.inputDescriptionsByName["image"],
          input.type == .image,
          let constraint = input.imageConstraint,
          constraint.pixelsWide == reference.input.width,
          constraint.pixelsHigh == reference.input.height
    else {
        throw VerifyError.modelContract(
            "expected an image input named image of \(reference.input.width)x\(reference.input.height)"
        )
    }
    guard let output = description.outputDescriptionsByName["embedding"],
          output.type == .multiArray,
          let arrayConstraint = output.multiArrayConstraint
    else {
        throw VerifyError.modelContract("expected a multi-array output named embedding")
    }
    let elementCount = arrayConstraint.shape.reduce(1) { $0 * $1.intValue }
    guard elementCount == reference.embedding_dimension, arrayConstraint.dataType == .float32 else {
        throw VerifyError.modelContract(
            "embedding has \(elementCount) elements of type \(arrayConstraint.dataType.rawValue), "
                + "expected \(reference.embedding_dimension) float32"
        )
    }
    print("contract: input image \(constraint.pixelsWide)x\(constraint.pixelsHigh), "
        + "output embedding shape \(arrayConstraint.shape) float32")
}

func run() throws -> Bool {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let referenceData = try Data(contentsOf: options.fixturesURL.appendingPathComponent("reference.json"))
    let reference = try JSONDecoder().decode(ReferenceDocument.self, from: referenceData)

    let configuration = MLModelConfiguration()
    configuration.computeUnits = options.computeUnits
    let model = try MLModel(contentsOf: options.modelURL, configuration: configuration)
    try checkContract(model, reference: reference)
    print("compute units: \(options.computeUnitsName), swap red and blue: \(options.swapRedBlue), "
        + "pass mark: cosine > \(options.minimumCosine)")

    var allPassed = true
    var worstCosine = 1.0
    for fixture in reference.fixtures {
        let rgb = try decodeRGB(
            options.fixturesURL.appendingPathComponent(fixture.file),
            width: reference.input.width,
            height: reference.input.height
        )
        let actualHash = SHA256.hash(data: Data(rgb)).map { String(format: "%02x", $0) }.joined()
        guard actualHash == fixture.rgb_sha256 else {
            throw VerifyError.pixelHashMismatch(
                file: fixture.file, expected: fixture.rgb_sha256, actual: actualHash
            )
        }
        let pixelBuffer = try makePixelBuffer(
            rgb: rgb,
            width: reference.input.width,
            height: reference.input.height,
            swapRedBlue: options.swapRedBlue
        )
        let features = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let prediction = try model.prediction(from: features)
        guard let array = prediction.featureValue(for: "embedding")?.multiArrayValue,
              array.count == fixture.embedding.count
        else {
            throw VerifyError.modelContract("prediction has no embedding of the reference length")
        }
        var dot = 0.0
        var candidateSquares = 0.0
        var referenceSquares = 0.0
        var differenceSquares = 0.0
        for index in 0..<array.count {
            let candidate = array[index].doubleValue
            let expected = fixture.embedding[index]
            dot += candidate * expected
            candidateSquares += candidate * candidate
            referenceSquares += expected * expected
            differenceSquares += (candidate - expected) * (candidate - expected)
        }
        let cosine = dot / (candidateSquares.squareRoot() * referenceSquares.squareRoot())
        let relativeError = differenceSquares.squareRoot() / referenceSquares.squareRoot()
        let passed = cosine > options.minimumCosine
        allPassed = allPassed && passed
        worstCosine = min(worstCosine, cosine)
        let name = fixture.file.padding(toLength: 14, withPad: " ", startingAt: 0)
        print(String(
            format: "%@ cosine %.6f  relative L2 error %.2e  %@",
            name, cosine, relativeError, passed ? "PASS" : "FAIL"
        ))
    }
    print(String(format: "worst cosine %.6f, %@", worstCosine, allPassed ? "all fixtures pass" : "FAILED"))
    return allPassed
}

do {
    exit(try run() ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("verify-face-model: \(error)\n".utf8))
    exit(1)
}
