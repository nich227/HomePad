import Foundation
import HomePadMessagingCore
import MediaPlayer
import UIKit

/// The system music player on the companion: what is playing, and transport controls. It covers
/// the Music app's player only; other apps' playback is not readable.
@MainActor
public final class NowPlayingAppProvider: ProjectedAppProvider {
    public let app = ProjectedApp(
        id: BuiltInProjectedApp.nowPlayingID,
        name: String(localized: "Now Playing"),
        symbolName: "music.note",
        tint: .purple,
        category: .audio,
        requiresPersonalContent: false
    )
    public let rootTemplateID = NowPlayingProjection.rootTemplateID

    private var observers: [any NSObjectProtocol] = []
    private var onChange: (@MainActor () -> Void)?
    private var isGeneratingNotifications = false
    private let artworkSide: CGFloat

    public init(artworkSide: CGFloat = 320) {
        self.artworkSide = artworkSide
    }

    private var isAuthorized: Bool { MPMediaLibrary.authorizationStatus() == .authorized }

    public func activate(onChange: @escaping @MainActor () -> Void) async {
        self.onChange = onChange
        await requestAccessIfUndetermined()
        startObserving()
    }

    public func deactivate() {
        onChange = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if isGeneratingNotifications {
            MPMusicPlayerController.systemMusicPlayer.endGeneratingPlaybackNotifications()
            isGeneratingNotifications = false
        }
    }

    public func launched() async {
        await requestAccessIfUndetermined()
        startObserving()
    }

    /// Asks for media library access. Call from the companion's own UI while it is on screen.
    public func requestAccess() async {
        await requestAccessIfUndetermined()
        startObserving()
        onChange?()
    }

    public func template(id: String) async -> ProjectionTemplate? {
        guard id == rootTemplateID else { return nil }
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            return NowPlayingProjection.template(snapshot: snapshot(), idleTitle: String(localized: "Not Playing"))
        case .notDetermined:
            return placeholderTemplate(id: rootTemplateID, title: app.name, message: String(localized: "Open HomePad on your iPhone to allow access to Media & Apple Music."))
        default:
            return placeholderTemplate(id: rootTemplateID, title: app.name, message: String(localized: "Access is off. Allow Media & Apple Music for HomePad in Settings on your iPhone."))
        }
    }

    public func handle(actionID: String, payload: [String: String]) async -> ProjectionNavigation {
        .none
    }

    public func handle(mediaCommand: MediaCommand) {
        guard isAuthorized else { return }
        let player = MPMusicPlayerController.systemMusicPlayer
        switch mediaCommand {
        case .play: player.play()
        case .pause: player.pause()
        case .nextTrack: player.skipToNextItem()
        case .previousTrack: player.skipToPreviousItem()
        case .restartTrack: player.skipToBeginning()
        }
    }

    private func requestAccessIfUndetermined() async {
        guard MPMediaLibrary.authorizationStatus() == .notDetermined,
              UIApplication.shared.applicationState == .active
        else { return }
        _ = await MPMediaLibrary.requestAuthorization()
    }

    private func startObserving() {
        guard isAuthorized, !isGeneratingNotifications else { return }
        let player = MPMusicPlayerController.systemMusicPlayer
        let names: [Notification.Name] = [.MPMusicPlayerControllerNowPlayingItemDidChange, .MPMusicPlayerControllerPlaybackStateDidChange]
        for name in names {
            let observer = NotificationCenter.default.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?() }
            }
            observers.append(observer)
        }
        player.beginGeneratingPlaybackNotifications()
        isGeneratingNotifications = true
    }

    private func snapshot() -> NowPlayingSnapshot {
        let player = MPMusicPlayerController.systemMusicPlayer
        guard let item = player.nowPlayingItem else { return NowPlayingSnapshot() }
        return NowPlayingSnapshot(
            title: item.title,
            artist: item.artist,
            album: item.albumTitle,
            artwork: artworkData(for: item),
            elapsed: player.currentPlaybackTime,
            duration: item.playbackDuration,
            isPlaying: player.playbackState == .playing
        )
    }

    /// JPEG artwork that fits the projection cap, trying a smaller size before giving up.
    private func artworkData(for item: MPMediaItem) -> Data? {
        let limit = ProjectionLimits.standard.maxArtworkBytes
        for side in [artworkSide, artworkSide / 2] {
            if let data = item.artwork?.image(at: CGSize(width: side, height: side))?.jpegData(compressionQuality: 0.6),
               data.count <= limit {
                return data
            }
        }
        return nil
    }
}
