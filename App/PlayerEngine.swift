import AVFoundation
import AVFAudio
import Combine
import MediaPlayer
import UIKit

final class PlayerEngine: ObservableObject {
    let player = AVPlayer()

    @Published var isPlaying = false
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var rate: Float
    @Published var gravity: AVLayerVideoGravity = .resizeAspect
    @Published var showControls = true

    static let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    private let itemID: UUID
    private let store: MediaStore
    private let pip = AVPictureInPictureController()
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var lastSave = Date.distantPast

    init(item: MediaItem, store: MediaStore) {
        self.itemID = item.id
        self.store = store
        self.rate = Defaults.defaultRate()

        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = 1.0

        addTimeObserver()
        statusObservation = player.observe(\.timeControlStatus, options: [.initial]) { [weak self] p, _ in
            DispatchQueue.main.async {
                self?.isPlaying = (p.timeControlStatus == .playing)
            }
        }
        setupRemote()
        NotificationCenter.default.addObserver(
            forName: .AVPictureInPictureDidStop,
            object: pip,
            queue: .main
        ) { [weak self] _ in
            self?.showControls = true
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveProgress()
        }
    }

    deinit {
        if let t = timeObserver {
            player.removeTimeObserver(t)
        }
    }

    // MARK: - 载入

    func load(_ media: MediaItem) {
        guard let url = media.resolvedURL else { return }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 60

        itemObservation = item.observe(\.status, options: [.initial]) { [weak self] it, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if it.status == .readyToPlay, it.duration.seconds.isFinite, it.duration.seconds > 0 {
                    self.duration = it.duration.seconds
                }
            }
        }

        player.replaceCurrentItem(with: item)
        currentTime = media.lastPosition

        let resume = Defaults.bool(SettingsKeys.resumePlayback, fallback: true)
        if resume, media.lastPosition > 2 {
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.player.seek(
                    to: CMTime(seconds: media.lastPosition, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                self.player.setRate(self.rate, atHostTime: 0)
            }
        } else {
            player.setRate(rate, atHostTime: 0)
        }
    }

    // MARK: - 控制

    func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.setRate(rate, atHostTime: 0)
        }
    }

    func setRate(_ r: Float) {
        rate = r
        if player.timeControlStatus == .playing {
            player.setRate(r, atHostTime: 0)
        }
        UserDefaults.standard.set(r, forKey: SettingsKeys.defaultRate)
    }

    func seekBy(_ delta: Double) {
        guard duration > 0 else { return }
        let target = max(0, min(currentTime + delta, max(duration - 0.5, 0)))
        seek(to: target)
    }

    func seek(to t: Double) {
        player.seek(
            to: CMTime(seconds: max(0, t), preferredTimescale: 600),
            toleranceBefore: .positiveInfinity,
            toleranceAfter: .positiveInfinity
        )
    }

    func togglePiP() {
        if pip.isInPictureInPicturePlayback {
            pip.stopPictureInPicturePlayback()
        } else {
            pip.startPictureInPicturePlayback()
        }
    }

    func setBrightness(_ v: Double) {
        UIScreen.main.brightness = min(1, max(0, v))
    }

    func setVolume(_ v: Double) {
        player.volume = Float(min(1, max(0, v)))
    }

    var currentVolume: Double { Double(player.volume) }

    // MARK: - 进度持久化

    func saveProgress() {
        guard let media = store.items.first(where: { $0.id == itemID }) else { return }
        var m = media
        m.lastPosition = currentTime
        store.update(m)
    }

    // MARK: - 基建

    private func addTimeObserver() {
        let interval = CMTime(value: 1, timescale: 2)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            self.currentTime = t.seconds
            if self.isPlaying, Date().timeIntervalSince(self.lastSave) > 10 {
                self.lastSave = Date()
                self.saveProgress()
            }
        }
    }

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            self?.player.setRate(self?.rate ?? 1.0, atHostTime: 0)
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            return .success
        }
    }
}
