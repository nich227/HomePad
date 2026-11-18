import Foundation

/// The Lottie animations bundled with the app. The raw value is the resource file name.
public enum HomePadAnimation: String, CaseIterable, Sendable {
    case success
    case faceScan = "face-scan"
    case beamIncoming = "beam-incoming"
    case beamSending = "beam-sending"
    case presencePulse = "presence-pulse"
    case timerDone = "timer-done"
    case pairing
    case hello
    case listening
    case locked
    case guest

    /// Frames per second of every bundled animation.
    public static let frameRate = 60

    /// Width and height of the square canvas, in Lottie units.
    public static let canvasSize = 400

    /// Whether the animation is authored to repeat. A looping animation ends on the picture it
    /// starts on. The others play once and hold their last frame.
    public var loops: Bool {
        switch self {
        case .success, .beamIncoming, .hello, .locked: false
        case .faceScan, .beamSending, .presencePulse, .timerDone, .pairing, .listening, .guest: true
        }
    }

    /// Whether the animation has parts that take an accent color through
    /// `HomePadAnimationKeypath.tintColor`.
    public var supportsTint: Bool {
        self != .hello
    }

    /// Length of one pass, in frames.
    public var frameCount: Int {
        switch self {
        case .success, .locked: 90
        case .faceScan, .listening: 120
        case .beamIncoming, .timerDone: 150
        case .beamSending, .presencePulse, .pairing, .guest: 180
        case .hello: 210
        }
    }

    /// Length of one pass, in seconds.
    public var duration: TimeInterval {
        TimeInterval(frameCount) / TimeInterval(Self.frameRate)
    }

    public var resourceURL: URL? {
        Self.resourceURL(named: rawValue)
    }

    public func data() throws -> Data {
        try Self.data(at: resourceURL, named: rawValue)
    }

    static func resourceURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "json")
    }

    static func data(at url: URL?, named name: String) throws(HomePadAnimationError) -> Data {
        guard let url else { throw .missingResource(name) }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .unreadableResource(name)
        }
    }
}

public enum HomePadAnimationError: Error, Equatable, Sendable {
    case missingResource(String)
    case unreadableResource(String)
}
