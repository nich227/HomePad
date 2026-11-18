import HomePadCore
import SwiftUI

extension RainbowTint {
    /// The stripe color in sRGB.
    public var color: Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

extension Color {
    public init(_ tint: RainbowTint) {
        self = tint.color
    }
}
