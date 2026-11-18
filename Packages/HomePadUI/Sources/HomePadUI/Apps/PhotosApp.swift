import HomePadCore
import HomePadUICore
import PhotosUI
import SwiftUI

/// Chooses the photos the Photos face and the photo widget rotate through.
struct PhotosApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(HubEnvironment.self) private var environment
    @State private var selection: [PhotosPickerItem] = []
    @State private var isImporting = false

    var body: some View {
        let library = environment.photos
        let gap = metrics.pt(1.6)
        let cell = (metrics.side - metrics.pt(4) * 2 - gap * 2) / 3
        // The picker's label closure is not on the main actor, so it gets plain values.
        let adding = isImporting
        let labelSize = metrics.text(3.4)
        let labelHeight = metrics.pt(11.5)
        AppScreen(title: "Photos", onClose: onClose) {
            VStack(spacing: metrics.pt(2.4)) {
                if library.picked.isEmpty {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: metrics.pt(14)))
                        .foregroundStyle(Color.hubSecondaryText)
                    Text("Choose photos for the Photos face.")
                        .font(.system(size: metrics.text(3.6), weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 3), spacing: gap) {
                            ForEach(library.picked) { photo in
                                Image(uiImage: photo.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: cell, height: cell)
                                    .clipShape(RoundedRectangle(cornerRadius: metrics.pt(3), style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        GlassCircleButton(symbol: "trash.fill", label: "Remove Photo", size: 6.5) { library.remove(id: photo.id) }
                                            .padding(metrics.pt(1))
                                    }
                                    .accessibilityLabel("Photo")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                PhotosPicker(selection: $selection, maxSelectionCount: 12, matching: .images) {
                    Label(adding ? "Adding" : "Add Photos", systemImage: "plus")
                        .font(.system(size: labelSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: labelHeight)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hubGlass(in: Capsule(), interactive: true)
                .disabled(isImporting || library.picked.count >= FacePhotoLibrary.limit)
            }
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            isImporting = true
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await library.add(imageData: data)
                    }
                }
                selection = []
                isImporting = false
            }
        }
    }
}
