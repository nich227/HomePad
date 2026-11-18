import Foundation

/// The six colors of the classic rainbow stripes, in stripe order.
public enum RainbowTint: String, CaseIterable, Codable, Sendable {
    case green, yellow, orange, red, purple, blue

    /// sRGB components in 0...1.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .green: (0x61 / 255.0, 0xBB / 255.0, 0x46 / 255.0)
        case .yellow: (0xFD / 255.0, 0xB8 / 255.0, 0x27 / 255.0)
        case .orange: (0xF5 / 255.0, 0x82 / 255.0, 0x1F / 255.0)
        case .red: (0xE0 / 255.0, 0x3A / 255.0, 0x3E / 255.0)
        case .purple: (0x96 / 255.0, 0x3D / 255.0, 0x97 / 255.0)
        case .blue: (0x00 / 255.0, 0x9D / 255.0, 0xDC / 255.0)
        }
    }
}

/// One member of the household. The id is the join key for face templates, paired devices,
/// Home Screen layouts, and personal content.
public struct HouseholdProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var tint: RainbowTint
    /// SF Symbol name shown as the avatar.
    public var symbolName: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        tint: RainbowTint,
        symbolName: String = "person.crop.circle.fill",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tint = tint
        self.symbolName = symbolName
        self.createdAt = createdAt
    }
}

/// Which side of the experience this device plays.
public enum DeviceRole: String, Codable, Sendable {
    /// The shared screen (iPad).
    case hub
    /// A household member's personal device (iPhone).
    case companion
}
