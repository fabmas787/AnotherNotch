import Foundation

@MainActor
public final class SimulatedMediaService: MediaServiceProtocol {
    public let source: MediaSource = .demo
    public var isAvailable: Bool { true }
    public var isRunning: Bool { true }

    public private(set) var currentTrack: TrackInfo?
    public private(set) var isPlaying: Bool = true
    public private(set) var playbackPosition: TimeInterval = 42.0
    public private(set) var volume: Double = 0.8
    public private(set) var isMuted: Bool = false
    public private(set) var isShuffleActive: Bool = false
    public private(set) var repeatMode: RepeatMode = .off

    private var currentIndex: Int = 0
    private var progressTimer: Timer?
    private var preMuteVolume: Double = 0.8

    public static let demoTracks: [TrackInfo] = [
        TrackInfo(
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            duration: 243.0,
            artworkGradientStartHex: "#FF4E50",
            artworkGradientEndHex: "#F9D423",
            source: .demo
        ),
        TrackInfo(
            title: "Starboy",
            artist: "The Weeknd ft. Daft Punk",
            album: "Starboy",
            duration: 230.0,
            artworkGradientStartHex: "#8A2387",
            artworkGradientEndHex: "#E94057",
            source: .demo
        ),
        TrackInfo(
            title: "Solar Power",
            artist: "Lorde",
            album: "Solar Power",
            duration: 192.0,
            artworkGradientStartHex: "#00C9FF",
            artworkGradientEndHex: "#92FE9D",
            source: .demo
        ),
        TrackInfo(
            title: "Get Lucky",
            artist: "Daft Punk ft. Pharrell Williams",
            album: "Random Access Memories",
            duration: 248.0,
            artworkGradientStartHex: "#F12711",
            artworkGradientEndHex: "#F5AF19",
            source: .demo
        ),
        TrackInfo(
            title: "Resonance",
            artist: "HOME",
            album: "Odyssey",
            duration: 212.0,
            artworkGradientStartHex: "#4776E6",
            artworkGradientEndHex: "#8E54E9",
            source: .demo
        )
    ]

    public init(startPlaying: Bool = true) {
        self.isPlaying = startPlaying
        if !Self.demoTracks.isEmpty {
            self.currentTrack = Self.demoTracks[0]
        }
        startTimer()
    }

    isolated deinit {
        progressTimer?.invalidate()
    }

    private func startTimer() {
        progressTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func tick() {
        guard isPlaying, let track = currentTrack, track.duration > 0 else { return }
        playbackPosition += 0.1
        if playbackPosition >= track.duration {
            if repeatMode == .one {
                playbackPosition = 0.0
            } else {
                nextTrack()
            }
        }
    }

    public func playPause() {
        isPlaying.toggle()
    }

    public func nextTrack() {
        guard !Self.demoTracks.isEmpty else { return }
        currentIndex = (currentIndex + 1) % Self.demoTracks.count
        currentTrack = Self.demoTracks[currentIndex]
        playbackPosition = 0.0
        isPlaying = true
    }

    public func previousTrack() {
        guard !Self.demoTracks.isEmpty else { return }
        if playbackPosition > 3.0 {
            playbackPosition = 0.0
            return
        }
        currentIndex = (currentIndex - 1 + Self.demoTracks.count) % Self.demoTracks.count
        currentTrack = Self.demoTracks[currentIndex]
        playbackPosition = 0.0
        isPlaying = true
    }

    public func seek(to seconds: TimeInterval) {
        guard let track = currentTrack else { return }
        playbackPosition = max(0.0, min(seconds, track.duration))
    }

    public func setVolume(_ volume: Double) {
        self.volume = max(0.0, min(1.0, volume))
        self.isMuted = (self.volume == 0)
    }

    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        if muted {
            self.preMuteVolume = self.volume
            self.volume = 0
        } else {
            self.volume = self.preMuteVolume > 0 ? self.preMuteVolume : 0.8
        }
    }

    public func refreshState() {
        // Simulated state is internally managed
    }

    public func setShuffle(_ active: Bool) {
        self.isShuffleActive = active
    }

    public func setRepeatMode(_ mode: RepeatMode) {
        self.repeatMode = mode
    }
}
