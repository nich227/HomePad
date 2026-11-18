import AVKit
import HomePadCore
import HomePadUICore
import SwiftUI

/// The system's audio route button, so music can be sent to a speaker.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Now playing: the artwork large in the middle, the title over its lower edge, a thin progress
/// bar, and transport controls, on a dark blur of the artwork.
struct MusicApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        let music = environment.music
        let playing = music.nowPlaying
        ZStack {
            backdrop(music.artwork)
            VStack(spacing: 0) {
                HStack {
                    GlassCircleButton(symbol: "xmark", label: "Close", action: onClose)
                    Spacer()
                    RoutePicker()
                        .frame(width: metrics.pt(9), height: metrics.pt(9))
                        .hubGlass(in: Circle())
                        .accessibilityLabel("Choose Speaker")
                }
                ZStack(alignment: .bottomLeading) {
                    ArtworkView(image: music.artwork, cornerRadius: metrics.pt(2))
                        .frame(width: metrics.pt(60), height: metrics.pt(60))
                        .shadow(color: .black.opacity(0.45), radius: metrics.pt(4), y: metrics.pt(2))
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: metrics.pt(0.2)) {
                        Text(playing?.title ?? String(localized: "Not Playing"))
                            .font(.system(size: metrics.text(5.2), weight: .semibold))
                            .foregroundStyle(.white)
                        Text(playing?.artist ?? (music.isAuthorized ? String(localized: "Play something in Music") : String(localized: "Allow Media & Apple Music access in Settings")))
                            .font(.system(size: metrics.text(3.8)))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.55), radius: metrics.pt(1.2))
                    .padding(.horizontal, metrics.pt(4))
                    .offset(y: metrics.pt(3))
                    .accessibilityElement(children: .combine)
                }
                .padding(.top, metrics.pt(-1))
                progress(playing)
                    .padding(.horizontal, metrics.pt(4))
                    .padding(.top, metrics.pt(6))
                transport(playing)
                    .padding(.top, metrics.pt(2.5))
                Spacer(minLength: 0)
            }
            .padding(metrics.pt(4))
        }
        .onAppear { music.start() }
    }

    private func backdrop(_ artwork: UIImage?) -> some View {
        ZStack {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: metrics.side, height: metrics.side)
                    .blur(radius: metrics.pt(12))
            } else {
                LinearGradient(colors: [Color(red: 0.12, green: 0.18, blue: 0.26), Color(red: 0.04, green: 0.07, blue: 0.12)], startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(0.45)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func progress(_ playing: NowPlaying?) -> some View {
        VStack(spacing: metrics.pt(1.2)) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28))
                    Capsule().fill(.white).frame(width: proxy.size.width * CGFloat(playing?.progress ?? 0))
                }
            }
            .frame(height: metrics.pt(0.9))
            HStack {
                Text(DurationText.elapsed(playing?.elapsed ?? 0))
                Spacer()
                Text(verbatim: "-\(DurationText.elapsed(playing?.remaining ?? 0))")
            }
            .font(.system(size: metrics.text(2.7), weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Text(DurationText.elapsed(playing?.elapsed ?? 0)))
    }

    private func transport(_ playing: NowPlaying?) -> some View {
        let music = environment.music
        return HStack(spacing: metrics.pt(13)) {
            control("backward.fill", label: "Previous", size: 6.5) { music.skipToPrevious() }
            control(playing?.isPlaying == true ? "pause.fill" : "play.fill", label: playing?.isPlaying == true ? "Pause" : "Play", size: 10) { music.togglePlayPause() }
            control("forward.fill", label: "Next", size: 6.5) { music.skipToNext() }
        }
    }

    private func control(_ symbol: String, label: LocalizedStringKey, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.pt(size)))
                .foregroundStyle(.white)
                .frame(width: metrics.pt(13), height: metrics.pt(12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}

/// The front camera as a mirror, full canvas or zoomed in.
struct MirrorApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(HubEnvironment.self) private var environment
    @State private var isZoomed = false

    var body: some View {
        let camera = environment.camera
        ZStack {
            Color.black
            switch camera.state {
            case .running, .idle:
                camera.makePreview()
                    .scaleEffect(isZoomed ? 1.8 : 1)
                    .frame(width: metrics.side, height: metrics.side)
                    .clipped()
                    .accessibilityLabel("Mirror")
            case .denied:
                notice("HomePad needs the camera to be a mirror. Allow Camera access in Settings.", showsSettings: true)
            case .unavailable:
                notice("The front camera is not available.", showsSettings: false)
            }
            VStack {
                HStack {
                    GlassCircleButton(symbol: "xmark", label: "Close", action: onClose)
                    Spacer()
                }
                Spacer()
                if camera.state == .running {
                    GlassCapsuleButton(
                        title: isZoomed ? "Full View" : "Zoom In",
                        symbol: isZoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass"
                    ) {
                        withAnimation(reduceMotion ? nil : .smooth) { isZoomed.toggle() }
                    }
                    .frame(width: metrics.pt(40))
                }
            }
            .padding(metrics.pt(4))
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private func notice(_ text: LocalizedStringKey, showsSettings: Bool) -> some View {
        VStack(spacing: metrics.pt(3)) {
            Image(systemName: "camera.fill")
                .font(.system(size: metrics.pt(12)))
                .foregroundStyle(Color.hubSecondaryText)
            Text(text)
                .font(.system(size: metrics.text(3.6), weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if showsSettings {
                OpenSettingsButton()
                    .font(.system(size: metrics.text(3.2), weight: .semibold))
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(metrics.pt(10))
    }
}
