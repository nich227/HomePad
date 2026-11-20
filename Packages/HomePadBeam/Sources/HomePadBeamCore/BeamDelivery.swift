import Foundation

public enum BeamSendError: Error, Equatable, Sendable {
    case invalidURL(BeamURLRejection)
    case noPairedHub
    /// The hub was not found or the connection failed after every allowed try.
    case hubUnreachable
    /// The page was written to the link but the hub did not confirm it in time.
    case noReceipt
}

/// What the companion shows for the page it last sent.
public enum BeamDeliveryState: Equatable, Sendable {
    case idle
    case sending
    case delivered(BeamOutcome)
    case failed(BeamSendError)

    public static let receiptTimeout: TimeInterval = 6

    /// A later receipt for the same beam replaces an answer that says the page is still waiting
    /// at the hub with what became of it.
    public func applying(_ receipt: BeamReceipt, to beamID: UUID) -> BeamDeliveryState {
        guard receipt.beamID == beamID else { return self }
        switch self {
        case .sending, .delivered(.awaitingApproval), .delivered(.waitingForOwner), .failed(.noReceipt):
            return .delivered(receipt.outcome)
        default:
            return self
        }
    }

    public var isSuccess: Bool {
        switch self {
        case .delivered(.opened), .delivered(.awaitingApproval), .delivered(.waitingForOwner): true
        default: false
        }
    }
}
