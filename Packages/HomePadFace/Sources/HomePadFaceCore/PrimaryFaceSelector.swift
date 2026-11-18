import Foundation

public struct PrimaryFaceSelection: Equatable, Sendable {
    /// Index of the primary face in the input array.
    public let index: Int
    /// Eligible faces that are close to the primary one in size, the primary included.
    public let prominentFaceCount: Int

    public init(index: Int, prominentFaceCount: Int) {
        self.index = index
        self.prominentFaceCount = prominentFaceCount
    }
}

/// Picks the face to recognize: the largest one that is reasonably centered. Boxes are
/// normalized to the frame (0...1 on both axes).
public struct PrimaryFaceSelector: Equatable, Sendable {
    /// How far a face center may sit from the frame center, per axis.
    public var maximumCenterOffset: Double
    /// A second face at least this fraction of the primary face's area counts as prominent.
    public var prominenceRatio: Double

    public init(maximumCenterOffset: Double = 0.4, prominenceRatio: Double = 0.5) {
        self.maximumCenterOffset = maximumCenterOffset
        self.prominenceRatio = prominenceRatio
    }

    public func select(from boxes: [CGRect]) -> PrimaryFaceSelection? {
        let eligible = boxes.enumerated().filter { _, box in
            let area = box.width * box.height
            return area.isFinite && area > 0
                && abs(box.midX - 0.5) <= maximumCenterOffset
                && abs(box.midY - 0.5) <= maximumCenterOffset
        }
        guard let primary = eligible.max(by: { $0.element.width * $0.element.height < $1.element.width * $1.element.height }) else {
            return nil
        }
        let primaryArea = primary.element.width * primary.element.height
        let prominent = eligible.count { $0.element.width * $0.element.height >= primaryArea * prominenceRatio }
        return PrimaryFaceSelection(index: primary.offset, prominentFaceCount: prominent)
    }
}
