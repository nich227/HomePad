import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Renders text as a QR code that stays sharp at any size.
struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(16)
                .background(.white, in: .rect(cornerRadius: 16))
                .accessibilityLabel(Text("Pairing code"))
                .accessibilityHint(Text("Scan with the HomePad app or the Camera on your iPhone"))
        } else {
            ContentUnavailableView("Could not draw the pairing code", systemImage: "qrcode")
        }
    }

    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let rendered = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: rendered)
    }
}
