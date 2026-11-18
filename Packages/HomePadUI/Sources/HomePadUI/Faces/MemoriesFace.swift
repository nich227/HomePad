import HomePadCore
import HomePadUICore
import SwiftUI

/// The chosen photos one after another, each drifting slowly while it shows and fading into the
/// next, with the day they were added underneath. With no photos it rests on the wallpaper.
struct MemoriesFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.hubPreferences) private var preferences
    @Environment(\.hubMayPrompt) private var mayPrompt
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        let options = preferences.faces
        let photos = environment.photos.photos(for: options.photosSource)
        let frame = MemoriesSlideshow.frame(count: photos.count, at: date, reduceMotion: reduceMotion)
        ZStack {
            if let frame {
                // The next photo lies underneath, so the fade reveals it.
                picture(photos[(frame.index + 1) % photos.count], scale: 1.06, offsetX: 0, offsetY: 0)
                picture(photos[frame.index], scale: frame.scale, offsetX: frame.offsetX, offsetY: frame.offsetY)
                    .opacity(frame.opacity)
            } else {
                HubWallpaper()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: metrics.token(2)) {
                Spacer()
                Text(FaceText.clock(date, calendar: calendar, density: density, units: units).digits)
                    .font(.clockDigits(size: metrics.token(DesignTokens.hero(for: density)), weight: .semibold))
                    .contentTransition(.numericText())
                Text(caption(photos: photos, index: frame?.index))
                    .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
                    .opacity(density.showsLabels ? 0.9 : 0)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: metrics.token(6))
            .padding(.horizontal, metrics.token(36))
            .padding(.bottom, metrics.bottomBar + metrics.token(20))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(Color.black)
        .accessibilityElement()
        .accessibilityLabel(Text(date, style: .time))
        .task(id: "\(options.photosSource.rawValue)|\(options.photosAlbumName)|\(mayPrompt)") {
            if options.photosSource == .sharedAlbum, mayPrompt {
                await environment.photos.loadSharedAlbum(named: options.photosAlbumName)
            }
        }
    }

    private func picture(_ photo: FacePhoto, scale: Double, offsetX: Double, offsetY: Double) -> some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(width: metrics.width, height: metrics.height)
            .scaleEffect(scale)
            .offset(x: metrics.width * offsetX, y: metrics.height * offsetY)
            .accessibilityHidden(true)
    }

    private func caption(photos: [FacePhoto], index: Int?) -> String {
        guard let index else {
            return String(localized: "Choose photos in the Photos app")
        }
        return TimeTextPolicy.dateLine(for: photos[index].addedAt ?? date, style: .full, calendar: calendar, locale: locale)
    }
}
