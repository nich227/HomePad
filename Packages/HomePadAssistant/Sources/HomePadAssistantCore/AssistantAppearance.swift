import Foundation

/// An sRGB color with components in 0...1.
public struct AssistantColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public func opacity(_ value: Double) -> AssistantColor {
        AssistantColor(red: red, green: green, blue: blue, opacity: value)
    }

    public static let black = AssistantColor(red: 0, green: 0, blue: 0)
    public static let white = AssistantColor(red: 1, green: 1, blue: 1)
    /// The one tint Night Mode allows.
    public static let nightRed = AssistantColor(red: 1, green: 0x2D / 255.0, blue: 0x20 / 255.0)
}

/// Every color the overlay draws with. Night Mode allows pure black and one red, so the night
/// palette has no glass and no second hue.
public struct AssistantPalette: Equatable, Sendable {
    /// Stops of the edge light, around the border. The first and last match so the loop has no seam.
    public let glow: [AssistantColor]
    /// Drawn over the hub behind the card.
    public let scrim: AssistantColor
    /// Nil means the card is Liquid Glass.
    public let cardFill: AssistantColor?
    public let cardStroke: AssistantColor
    public let text: AssistantColor
    public let secondaryText: AssistantColor
    public let accent: AssistantColor
    public let chipFill: AssistantColor

    public static func resolve(isNight: Bool) -> AssistantPalette {
        isNight ? night : day
    }

    static let day = AssistantPalette(
        glow: [
            AssistantColor(red: 0.26, green: 0.56, blue: 1.00),
            AssistantColor(red: 0.62, green: 0.38, blue: 1.00),
            AssistantColor(red: 1.00, green: 0.36, blue: 0.62),
            AssistantColor(red: 1.00, green: 0.62, blue: 0.26),
            AssistantColor(red: 0.30, green: 0.86, blue: 0.80),
            AssistantColor(red: 0.26, green: 0.56, blue: 1.00),
        ],
        scrim: AssistantColor.black.opacity(0.28),
        cardFill: nil,
        cardStroke: AssistantColor.white.opacity(0.22),
        text: .white,
        secondaryText: AssistantColor.white.opacity(0.66),
        accent: AssistantColor(red: 0.45, green: 0.62, blue: 1.00),
        chipFill: AssistantColor.white.opacity(0.14)
    )

    static let night = AssistantPalette(
        glow: [
            .nightRed,
            AssistantColor.nightRed.opacity(0.35),
            .nightRed,
            AssistantColor.nightRed.opacity(0.35),
            .nightRed,
        ],
        scrim: AssistantColor.black.opacity(0.6),
        cardFill: .black,
        cardStroke: AssistantColor.nightRed.opacity(0.7),
        text: .nightRed,
        secondaryText: AssistantColor.nightRed.opacity(0.7),
        accent: .nightRed,
        chipFill: .black
    )

    var allColors: [AssistantColor] {
        glow + [scrim, cardStroke, text, secondaryText, accent, chipFill] + [cardFill].compactMap { $0 }
    }
}

/// One frame of the light that traces the screen border.
public struct EdgeGlowFrame: Equatable, Sendable {
    /// Where the gradient starts, clockwise from the top.
    public let rotationDegrees: Double
    public let lineWidth: Double
    public let blurRadius: Double
    public let opacity: Double
}

public enum EdgeGlow {
    public enum Activity: Equatable, Sendable, CaseIterable {
        case idle, listening, thinking, answering

        /// Seconds for one swell of the light.
        var breathDuration: TimeInterval {
            switch self {
            case .idle: 5
            case .listening: 1.6
            case .thinking: 2.4
            case .answering: 3.2
            }
        }
    }

    /// Seconds for the colors to travel once around the border. The same for every activity,
    /// so the colors never jump when the activity changes.
    public static let lapDuration: TimeInterval = 8
    public static let baseLineWidth = 6.0
    public static let baseBlurRadius = 14.0

    /// With Reduce Motion the edge holds one frame: lit, and still.
    public static func frame(elapsed: TimeInterval, activity: Activity, reduceMotion: Bool) -> EdgeGlowFrame {
        guard !reduceMotion else {
            return EdgeGlowFrame(rotationDegrees: 0, lineWidth: baseLineWidth, blurRadius: baseBlurRadius, opacity: 0.85)
        }
        let time = max(0, elapsed)
        let lap = time.truncatingRemainder(dividingBy: lapDuration) / lapDuration
        let breath = 0.5 - 0.5 * cos(2 * .pi * time / activity.breathDuration)
        return EdgeGlowFrame(
            rotationDegrees: lap * 360,
            lineWidth: baseLineWidth + 4 * breath,
            blurRadius: baseBlurRadius + 10 * breath,
            opacity: 0.7 + 0.3 * breath
        )
    }
}

public enum AssistantLayout {
    public static let cardMaximumWidth = 720.0
    public static let cardMargin = 16.0

    /// The card fills a narrow display up to its margins and stops widening on a wide one.
    public static func cardWidth(containerWidth: Double) -> Double {
        max(0, min(containerWidth - 2 * cardMargin, cardMaximumWidth))
    }

    /// A drag on the card closes the overlay when it went down far enough or was thrown down.
    public static func dismissesOnDrag(translation: Double, predictedEndTranslation: Double) -> Bool {
        translation > 90 || predictedEndTranslation > 240
    }
}
