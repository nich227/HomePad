import SwiftUI
import VisionKit

/// A live camera view that reports the first QR code it sees.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    @MainActor
    static var isUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            context.coordinator.unavailable = true
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        private var hasReported = false
        var unavailable = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasReported else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let text = barcode.payloadStringValue else { continue }
                hasReported = true
                dataScanner.stopScanning()
                onCode(text)
                return
            }
        }
    }
}
