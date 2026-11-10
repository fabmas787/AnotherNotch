import AppKit
import Foundation
import QuartzCore

@MainActor
public final class SpotifyService: MediaServiceProtocol {
    public let source: MediaSource = .spotify
    nonisolated public static let bundleId = "com.spotify.client"

    public var isAvailable: Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleId) != nil
    }

    nonisolated public var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleId).contains { !$0.isTerminated }
    }

    public private(set) var currentTrack: TrackInfo?
    public private(set) var isPlaying: Bool = false
    public private(set) var playbackPosition: TimeInterval = 0.0
    public private(set) var volume: Double = 0.75
    public private(set) var isMuted: Bool = false
    public private(set) var isShuffleActive: Bool = false
    public private(set) var repeatMode: RepeatMode = .off

    private var pollTimer: Timer?
    private var observerToken: NSObjectProtocol?
    private var isRefreshing: Bool = false
    private var preMuteVolume: Double = 0.75
    private var lastUserInteractionTime: CFTimeInterval = 0.0

    public init() {
        setupDistributedNotifications()
        refreshState()
        startPolling()
    }

    isolated deinit {
        stopTimers()
        if let observerToken {
            DistributedNotificationCenter.default().removeObserver(observerToken)
        }
    }

    public func stopTimers() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func setupDistributedNotifications() {
        observerToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let state = notification.userInfo?["Player State"] as? String
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let state = state, state.lowercased() == "stopped" {
                    self.isPlaying = false
                    self.currentTrack = nil
                    self.playbackPosition = 0.0
                    return
                }
                guard self.isRunning else {
                    self.isPlaying = false
                    self.currentTrack = nil
                    self.playbackPosition = 0.0
                    return
                }
                self.refreshState()
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        // Poll every 3.0 seconds as a watchdog; primary updates are event-driven via DistributedNotificationCenter
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                self.refreshState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    public func refreshState() {
        guard isRunning else {
            self.isPlaying = false
            self.currentTrack = nil
            self.playbackPosition = 0.0
            return
        }

        guard !isRefreshing else { return }
        isRefreshing = true

        let scriptText = """
        tell application "System Events"
            set isAppRunning to (name of processes) contains "Spotify"
        end tell
        if isAppRunning then
            tell application "Spotify"
                set isShuf to "false"
                set isRep to "false"
                try
                    set isShuf to (shuffling as string)
                end try
                try
                    set isRep to (repeating as string)
                end try
                set pState to player state as string
                if pState is "playing" or pState is "paused" then
                    set tName to ""
                    set tArtist to ""
                    set tAlbum to ""
                    set tDuration to 0
                    set tPos to 0
                    set sVol to 75
                    set artUrl to ""
                    try
                        set tName to name of current track
                    end try
                    try
                        set tArtist to artist of current track
                    end try
                    try
                        set tAlbum to album of current track
                    end try
                    try
                        set tDuration to (duration of current track) / 1000
                    end try
                    try
                        set tPos to player position
                    end try
                    try
                        set sVol to sound volume
                    end try
                    try
                        set artUrl to artwork url of current track
                    end try
                    return pState & "|||" & tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (tDuration as string) & "|||" & (tPos as string) & "|||" & (sVol as string) & "|||" & artUrl & "|||" & isShuf & "|||" & isRep
                else
                    return "stopped|||" & isShuf & "|||" & isRep
                end if
            end tell
        else
            return "not_running"
        end if
        """

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.isRunning else {
                DispatchQueue.main.async { [weak self] in
                    self?.isRefreshing = false
                    self?.isPlaying = false
                    self?.currentTrack = nil
                }
                return
            }
            let output = AppleScriptRunner.runSync(scriptText)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isRefreshing = false
                guard let output = output, !output.isEmpty else { return }

                if output == "not_running" {
                    self.isPlaying = false
                    self.currentTrack = nil
                    return
                }

                let components = output.components(separatedBy: "|||")
                let isStopped = components.first == "stopped"

                var isShufStr: String?
                var isRepStr: String?

                if isStopped {
                    self.isPlaying = false
                    self.currentTrack = nil
                    if components.count >= 3 {
                        isShufStr = components[1]
                        isRepStr = components[2]
                    }
                } else {
                    guard components.count >= 6 else { return }

                    let stateStr = components[0]
                    let name = components[1]
                    let artist = components[2]
                    let album = components[3]
                    let duration = Double(components[4].replacingOccurrences(of: ",", with: ".")) ?? 0.0
                    let pos = Double(components[5].replacingOccurrences(of: ",", with: ".")) ?? 0.0
                    if components.count >= 7, let volInt = Double(components[6].replacingOccurrences(of: ",", with: ".")) {
                        self.volume = max(0.0, min(1.0, volInt / 100.0))
                    }
                    var parsedArtURL: URL? = nil
                    if components.count >= 8 {
                        let rawUrl = components[7].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !rawUrl.isEmpty {
                            parsedArtURL = URL(string: rawUrl)
                        }
                    }
                    if components.count >= 10 {
                        isShufStr = components[8]
                        isRepStr = components[9]
                    }

                    self.isPlaying = (stateStr.lowercased() == "playing")
                    self.playbackPosition = pos

                    let trackId = "spotify_\(name)_\(artist)"
                    self.currentTrack = TrackInfo(
                        id: trackId,
                        title: name.isEmpty ? "Unknown Track" : name,
                        artist: artist.isEmpty ? "Unknown Artist" : artist,
                        album: album.isEmpty ? "Spotify" : album,
                        duration: duration,
                        artworkGradientStartHex: "#1DB954",
                        artworkGradientEndHex: "#191414",
                        artworkData: nil,
                        decodedImage: nil,
                        artworkURL: parsedArtURL,
                        source: .spotify
                    )
                }

                if (CACurrentMediaTime() - self.lastUserInteractionTime) > 1.0 {
                    if let isShufStr = isShufStr {
                        self.isShuffleActive = (isShufStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true")
                    }
                    if let isRepStr = isRepStr {
                        let isRepeating = (isRepStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true")
                        if !isRepeating {
                            self.repeatMode = .off
                        } else if self.repeatMode == .off {
                            self.repeatMode = .all
                        }
                    }
                }
            }
        }
    }

    public func launchPlayer() {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleId) {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    public func playPause() {
        if !isRunning {
            launchPlayer()
            return
        }
        AppleScriptRunner.runAsync("tell application \"Spotify\" to playpause")
        isPlaying.toggle()
    }

    public func nextTrack() {
        guard isRunning else { return }
        AppleScriptRunner.runAsync("tell application \"Spotify\" to next track")
        refreshState()
    }

    public func previousTrack() {
        guard isRunning else { return }
        AppleScriptRunner.runAsync("tell application \"Spotify\" to previous track")
        refreshState()
    }

    public func seek(to seconds: TimeInterval) {
        guard isRunning else { return }
        let rounded = Int(seconds)
        AppleScriptRunner.runAsync("tell application \"Spotify\" to set player position to \(rounded)")
        self.playbackPosition = seconds
    }

    public func setVolume(_ volume: Double) {
        self.volume = max(0.0, min(1.0, volume))
        self.isMuted = (self.volume == 0)
        guard isRunning else { return }
        let intVol = Int(self.volume * 100.0)
        AppleScriptRunner.runAsync("tell application \"Spotify\" to set sound volume to \(intVol)")
    }

    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        if muted {
            self.preMuteVolume = self.volume > 0 ? self.volume : (self.preMuteVolume > 0 ? self.preMuteVolume : 0.75)
            self.volume = 0
            guard isRunning else { return }
            AppleScriptRunner.runAsync("tell application \"Spotify\" to set sound volume to 0")
        } else {
            let restore = self.preMuteVolume > 0 ? self.preMuteVolume : 0.75
            self.volume = restore
            guard isRunning else { return }
            let intVol = Int(restore * 100.0)
            AppleScriptRunner.runAsync("tell application \"Spotify\" to set sound volume to \(intVol)")
        }
    }

    public func setShuffle(_ active: Bool) {
        self.isShuffleActive = active
        self.lastUserInteractionTime = CACurrentMediaTime()
        guard isRunning else { return }
        let script = "tell application \"Spotify\" to set shuffling to \(active ? "true" : "false")"
        AppleScriptRunner.runAsync(script)
    }

    public func setRepeatMode(_ mode: RepeatMode) {
        self.repeatMode = mode
        self.lastUserInteractionTime = CACurrentMediaTime()
        guard isRunning else { return }
        let repBool = (mode != .off)
        let script = "tell application \"Spotify\" to set repeating to \(repBool ? "true" : "false")"
        AppleScriptRunner.runAsync(script)
    }
}
