import HomePadCore
import HomePadUICore
import SwiftUI

/// A photo with the time in very tall translucent digits. With the depth layout the digits sit
/// behind the photo's subject, which is cut out and drawn again on top.
struct PhotosFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.hubPreferences) private var preferences
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(HubEnvironment.self) private var environment
    @Environment(HouseholdSession.self) private var session

    private var options: FaceOptions { preferences.faces }

    private var photo: FacePhoto? {
        let photos = environment.photos.photos(for: options.photosSource)
        guard let index = PhotoRotation.index(count: photos.count, at: date, shuffleMinutes: options.photosShuffleMinutes) else { return nil }
        return photos[index]
    }

    var body: some View {
        let current = photo
        ZStack {
            background(current)
            if options.photosLayout != .corner {
                tallDigits
            }
            if options.photosLayout == .depth {
                subject(current)
            }
            if options.photosLayout == .corner {
                cornerTime
            }
            if density == .detailed {
                caption
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(Color.black)
        .task(id: current?.id) {
            if let current {
                environment.photos.prepareSubject(for: current)
            }
        }
        .task(id: "\(options.photosSource.rawValue)|\(options.photosAlbumName)") {
            if options.photosSource == .sharedAlbum {
                await environment.photos.loadSharedAlbum(named: options.photosAlbumName)
            }
        }
    }

    @ViewBuilder
    private func background(_ photo: FacePhoto?) -> some View {
        if let photo {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: metrics.side, height: metrics.side)
                .accessibilityLabel("Photo")
        } else {
            let tint = session.activeProfile?.tint ?? .red
            LinearGradient(colors: [Color(tint).opacity(0.85), Color(tint).opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func subject(_ photo: FacePhoto?) -> some View {
        if let photo, let cutout = environment.photos.subjects[photo.id] {
            Image(uiImage: cutout)
                .resizable()
                .scaledToFill()
                .frame(width: metrics.side, height: metrics.side)
                .accessibilityHidden(true)
        } else if photo == nil {
            // With no photo chosen, a plain silhouette stands in for the subject.
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: metrics.pt(52))
                .offset(y: metrics.pt(24))
                .accessibilityHidden(true)
        }
    }

    private var tallDigits: some View {
        let columns = TimeTextPolicy.digitColumns(for: ClockReading(date: date, calendar: calendar), hourCycle: units.hourCycle)
        let hidesLeadingZero = units.hourCycle == .twelve && columns[0] == 0
        return HStack(spacing: 0) {
            digit(columns[0]).opacity(hidesLeadingZero ? 0 : 1)
            digit(columns[1])
            Spacer(minLength: metrics.pt(4))
            digit(columns[2])
            digit(columns[3])
        }
        .padding(.horizontal, metrics.pt(4))
        .accessibilityElement()
        .accessibilityLabel(Text(date, style: .time))
    }

    private func digit(_ value: Int) -> some View {
        Text(verbatim: "\(value)")
            .font(.system(size: metrics.pt(54), weight: .semibold).width(.compressed))
            .foregroundStyle(.white.opacity(0.34))
            .shadow(color: .white.opacity(0.45), radius: metrics.pt(0.25))
            .fixedSize()
            .frame(width: metrics.pt(21))
            .scaleEffect(x: 1, y: 2.25)
            .contentTransition(.numericText())
    }

    private var cornerTime: some View {
        Text(FaceText.clock(date, calendar: calendar, density: density, units: units).digits)
            .font(.clockDigits(size: metrics.pt(density == .detailed ? 8 : 16), weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: metrics.pt(0.6))
            .padding(metrics.pt(7))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var caption: some View {
        Text(FaceText.dateLine(date, calendar: calendar, density: density, locale: locale))
            .font(.system(size: metrics.text(3.2), weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: metrics.pt(0.6))
            .padding(metrics.pt(7))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
