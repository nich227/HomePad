import Foundation
import HomePadUICore
import MediaPlayer
import Observation
import UIKit

/// What is playing in the Music app, and its transport controls.
@MainActor
public protocol MusicService: AnyObject {
    var nowPlaying: NowPlaying? { get }
    var artwork: UIImage? { get }
    /// False when the person declined access to the media library.
    var isAuthorized: Bool { get }
    func start()
    func togglePlayPause()
    func skipToNext()
    func skipToPrevious()
    /// Moves to a point in the track, in seconds from its start.
    func seek(to seconds: TimeInterval)
}

@MainActor
@Observable
public final class SystemMusicService: MusicService {
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: UIImage?
    public private(set) var isAuthorized = true

    @ObservationIgnored private let player = MPMusicPlayerController.systemMusicPlayer
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var progressLoop: Task<Void, Never>?
    @ObservationIgnored private var artworkItemID: MPMediaEntityPersistentID?

    public init() {}

    public func start() {
        guard observers.isEmpty else { return }
        guard UsageDescriptions.has("NSAppleMusicUsageDescription") else {
            isAuthorized = false
            return
        }
        let center = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange, .MPMusicPlayerControllerPlaybackStateDidChange] {
            observers.append(center.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        player.beginGeneratingPlaybackNotifications()
        Task { [weak self] in
            let status = await MPMediaLibrary.requestAuthorization()
            self?.isAuthorized = status == .authorized
            self?.refresh()
        }
        progressLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.nowPlaying?.isPlaying == true {
                    self.refresh()
                }
            }
        }
    }

    public func togglePlayPause() {
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        refresh()
    }

    public func skipToNext() {
        player.skipToNextItem()
    }

    public func skipToPrevious() {
        player.skipToPreviousItem()
    }

    public func seek(to seconds: TimeInterval) {
        guard let duration = player.nowPlayingItem?.playbackDuration, duration > 0 else { return }
        player.currentPlaybackTime = min(max(seconds, 0), duration)
        refresh()
    }

    private func refresh() {
        guard let item = player.nowPlayingItem else {
            nowPlaying = nil
            artwork = nil
            artworkItemID = nil
            return
        }
        let elapsed = player.currentPlaybackTime
        nowPlaying = NowPlaying(
            title: item.title ?? "",
            artist: item.artist ?? "",
            album: item.albumTitle ?? "",
            isPlaying: player.playbackState == .playing,
            duration: item.playbackDuration,
            elapsed: elapsed.isFinite ? elapsed : 0
        )
        if artworkItemID != item.persistentID {
            artworkItemID = item.persistentID
            artwork = item.artwork?.image(at: CGSize(width: 600, height: 600))
        }
    }
}

/// A fixed track for previews.
@MainActor
@Observable
public final class PreviewMusicService: MusicService {
    public private(set) var nowPlaying: NowPlaying?
    public let artwork: UIImage? = nil
    public let isAuthorized = true

    public init(nowPlaying: NowPlaying? = NowPlaying(title: "Morning Light", artist: "The Placeholders", album: "Samples", isPlaying: true, duration: 207, elapsed: 104)) {
        self.nowPlaying = nowPlaying
    }

    public func start() {}

    public func togglePlayPause() {
        nowPlaying?.isPlaying.toggle()
    }

    public func skipToNext() {
        nowPlaying?.elapsed = 0
    }

    public func skipToPrevious() {
        nowPlaying?.elapsed = 0
    }

    public func seek(to seconds: TimeInterval) {
        guard let duration = nowPlaying?.duration else { return }
        nowPlaying?.elapsed = min(max(seconds, 0), duration)
    }
}
