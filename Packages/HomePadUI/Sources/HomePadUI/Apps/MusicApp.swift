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

/// Now playing: the cover, the title and artist, a scrubber to drag, the transport, and the
/// system's speaker picker, over a dark blur of the artwork. Side by side on a wide screen and
/// stacked on a tall one.
struct MusicApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMotion) private var motion
    @Environment(\.hubIsNight) private var isNight
    @Environment(HubEnvironment.self) private var environment
    /// Where the thumb is while a finger is on the scrubber, 0...1.
    @State private var scrubbing: Double?

    var body: some View {
        let music = environment.music
        let playing = music.nowPlaying
        let layout = metrics.isLandscape ? AnyLayout(HStackLayout(spacing: metrics.token(40))) : AnyLayout(VStackLayout(spacing: metrics.token(24)))
        let available = metrics.height - metrics.topEdge - metrics.chromeHeight - metrics.bottomBar - metrics.token(40)
        let cover = metrics.isLandscape ? min(available, metrics.width * 0.4) : min(metrics.width - metrics.token(120), available - metrics.token(230))
        ZStack {
            backdrop(music.artwork)
            VStack(spacing: metrics.token(16)) {
                HStack {
                    GlassCircleButton(symbol: "xmark", label: "Close", identifier: "hub.close", action: onClose)
                    Spacer()
                    RoutePicker()
                        .frame(width: metrics.chromeHeight, height: metrics.chromeHeight)
                        .hubGlass(in: Circle())
                        .accessibilityLabel("Choose Speaker")
                        .accessibilityIdentifier("music.route")
                }
                Spacer(minLength: 0)
                layout {
                    ArtworkView(image: music.artwork, cornerRadius: metrics.token(22))
                        .frame(width: max(cover, 0), height: max(cover, 0))
                        .shadow(color: .black.opacity(0.45), radius: metrics.token(24), y: metrics.token(10))
                        .scaleEffect(playing?.isPlaying == true ? 1 : 0.9)
                        .animation(motion.spring, value: playing?.isPlaying)
                    VStack(alignment: .leading, spacing: metrics.token(18)) {
                        VStack(alignment: .leading, spacing: metrics.token(2)) {
                            Text(playing?.title ?? String(localized: "Not Playing"))
                                .font(.system(size: metrics.textToken(30), weight: .bold))
                                .foregroundStyle(.white)
                            Text(playing?.artist ?? (music.isAuthorized ? String(localized: "Play something in Music") : String(localized: "Allow Media & Apple Music access in Settings")))
                                .font(.system(size: metrics.textToken(21)))
                                .foregroundStyle(Color.hubSecondaryText)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityElement(children: .combine)
                        scrubber(playing)
                        transport(playing)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: metrics.isLandscape ? .infinity : max(cover, metrics.token(300)))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.token(36))
            .padding(.top, metrics.topEdge)
            .padding(.bottom, metrics.bottomBar + metrics.token(8))
        }
        .startsOnFirstUse { music.start() }
    }

    private func backdrop(_ artwork: UIImage?) -> some View {
        ZStack {
            if isNight {
                Color.black
            } else if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: metrics.width, height: metrics.height)
                    .blur(radius: metrics.token(70))
                    .saturation(1.4)
            } else {
                HubWallpaper(tint: .purple)
                    .blur(radius: metrics.token(30))
            }
            Color.black.opacity(isNight ? 0 : 0.42)
        }
        .frame(width: metrics.width, height: metrics.height)
        .clipped()
        .accessibilityHidden(true)
    }

    /// A track that thickens under a finger. Dragging moves through the song.
    private func scrubber(_ playing: NowPlaying?) -> some View {
        let fraction = scrubbing ?? playing?.progress ?? 0
        let duration = playing?.duration ?? 0
        let elapsed = scrubbing.map { $0 * duration } ?? playing?.elapsed ?? 0
        return VStack(spacing: metrics.token(6)) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28))
                    Capsule().fill(.white).frame(width: max(proxy.size.height, proxy.size.width * CGFloat(fraction)))
                }
                .frame(height: metrics.token(scrubbing == nil ? 7 : 12))
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        scrubbing = min(max(Double(value.location.x / max(proxy.size.width, 1)), 0), 1)
                    }
                    .onEnded { _ in
                        if let scrubbing {
                            environment.music.seek(to: scrubbing * duration)
                        }
                        scrubbing = nil
                    })
            }
            .frame(height: HubMetrics.minimumTouchSide)
            .animation(motion.snappy, value: scrubbing == nil)
            HStack {
                Text(DurationText.elapsed(elapsed))
                Spacer()
                Text(verbatim: "-\(DurationText.elapsed(max(0, duration - elapsed)))")
            }
            .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.hubSecondaryText)
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Text(DurationText.elapsed(elapsed)))
        .accessibilityAdjustableAction { direction in
            environment.music.seek(to: (playing?.elapsed ?? 0) + (direction == .increment ? 15 : -15))
        }
        .accessibilityIdentifier("music.scrubber")
    }

    private func transport(_ playing: NowPlaying?) -> some View {
        let music = environment.music
        return HStack(spacing: metrics.token(44)) {
            control("backward.fill", label: "Previous", points: 30) { music.skipToPrevious() }
            control(playing?.isPlaying == true ? "pause.fill" : "play.fill", label: playing?.isPlaying == true ? "Pause" : "Play", points: 48) { music.togglePlayPause() }
                .accessibilityIdentifier("music.playPause")
            control("forward.fill", label: "Next", points: 30) { music.skipToNext() }
        }
    }

    private func control(_ symbol: String, label: LocalizedStringKey, points: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.token(points)))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: max(metrics.token(64), HubMetrics.minimumTouchSide), height: max(metrics.token(60), HubMetrics.minimumTouchSide))
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
                    .frame(width: metrics.width, height: metrics.height)
                    .clipped()
                    .accessibilityLabel("Mirror")
            case .denied:
                HubEmptyState(
                    symbol: "camera.fill",
                    title: "Camera Access Is Off",
                    message: "The Mirror shows the front camera. Allow Camera access in Settings to use it."
                ) {
                    HubSettingsButton()
                }
            case .unavailable:
                HubEmptyState(
                    symbol: "person.crop.square",
                    title: "Mirror Is Not Available",
                    message: "The front camera cannot be used right now."
                )
            }
            VStack {
                HStack {
                    GlassCircleButton(symbol: "xmark", label: "Close", identifier: "hub.close", action: onClose)
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
}
