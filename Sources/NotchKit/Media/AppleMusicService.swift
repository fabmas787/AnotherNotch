import AppKit
import Foundation
import QuartzCore

@MainActor
public final class AppleMusicService: MediaServiceProtocol {
    public let source: MediaSource = .appleMusic
    public static let bundleId = "com.apple.Music"

    public var isAvailable: Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleId) != nil
    }

    public var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleId).isEmpty
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
    private var lastArtworkTrackId: String = ""
    private var lastUserInteractionTime: CFTimeInterval = 0.0
    private let artworkQueue = DispatchQueue(label: "com.notch.applemusic.artwork", qos: .utility)

    public init() {
        setupDistributedNotifications()
        refreshState()
        startPolling()
    }

    isolated deinit {
        pollTimer?.invalidate()
        if let observerToken {
            DistributedNotificationCenter.default().removeObserver(observerToken)
        }
    }

    private func setupDistributedNotifications() {
        observerToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
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
        tell application "Music"
            if it is running then
                set isShuf to "false"
                set sRep to "off"
                try
                    set isShuf to (shuffle enabled as string)
                end try
                try
                    set sRep to (song repeat as string)
                end try
                set pState to player state as string
                if pState is "playing" or pState is "paused" then
                    set tName to ""
                    set tArtist to ""
                    set tAlbum to ""
                    set tDuration to 0
                    set tPos to 0
                    set sVol to 75
                    set isMuted to "false"
                    set hasArt to "false"
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
                        set tDuration to duration of current track
                    end try
                    try
                        set tPos to player position
                    end try
                    try
                        set sVol to sound volume
                    end try
                    try
                        if mute is true then
                            set isMuted to "true"
                        end if
                    end try
                    try
                        if (count of artworks of current track) > 0 then
                            set hasArt to "true"
                        end if
                    end try
                    return pState & "|||" & tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (tDuration as string) & "|||" & (tPos as string) & "|||" & (sVol as string) & "|||" & hasArt & "|||" & isMuted & "|||" & isShuf & "|||" & sRep
                else
                    return "stopped|||" & isShuf & "|||" & sRep
                end if
            else
                return "not_running"
            end if
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = AppleScriptRunner.runSync(scriptText)
            DispatchQueue.main.async {
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
                var sRepStr: String?

                if isStopped {
                    self.isPlaying = false
                    self.currentTrack = nil
                    if components.count >= 3 {
                        isShufStr = components[1]
                        sRepStr = components[2]
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
                    let hasArt = components.count >= 8 && components[7].trimmingCharacters(in: .whitespacesAndNewlines) == "true"
                    if components.count >= 9 {
                        self.isMuted = components[8].trimmingCharacters(in: .whitespacesAndNewlines) == "true"
                    }
                    if components.count >= 11 {
                        isShufStr = components[9]
                        sRepStr = components[10]
                    }

                    self.isPlaying = (stateStr.lowercased() == "playing")
                    self.playbackPosition = pos

                    let trackKey = "\(name)_\(artist)"
                    let isNewTrack = (trackKey != self.lastArtworkTrackId)
                    let cachedData = isNewTrack ? nil : self.currentTrack?.artworkData
                    let cachedImage = isNewTrack ? nil : self.currentTrack?.decodedImage

                    if hasArt && isNewTrack {
                        self.lastArtworkTrackId = trackKey
                        self.fetchArtworkAsync(expectedTrackKey: trackKey)
                    } else if !hasArt && isNewTrack {
                        self.lastArtworkTrackId = trackKey
                    }

                    let trackId = "applemusic_\(name)_\(artist)"
                    self.currentTrack = TrackInfo(
                        id: trackId,
                        title: name.isEmpty ? "Unknown Track" : name,
                        artist: artist.isEmpty ? "Unknown Artist" : artist,
                        album: album.isEmpty ? "Apple Music" : album,
                        duration: duration,
                        artworkGradientStartHex: "#35383F",
                        artworkGradientEndHex: "#1C1D21",
                        artworkData: cachedData,
                        decodedImage: cachedImage,
                        artworkURL: nil,
                        source: .appleMusic
                    )
                }

                if (CACurrentMediaTime() - self.lastUserInteractionTime) > 1.0 {
                    if let isShufStr = isShufStr {
                        self.isShuffleActive = (isShufStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true")
                    }
                    if let sRepStr = sRepStr {
                        let cleaned = sRepStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if let mode = RepeatMode(rawValue: cleaned) {
                            self.repeatMode = mode
                        }
                    }
                }
            }
        }
    }

    nonisolated public static let artworkCacheURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notch_artwork_cache.jpg")

    nonisolated public static let artworkExportScript = """
    tell application "Music"
        set f to 0
        try
            if (count of artworks of current track) > 0 then
                set art to artwork 1 of current track
                set rawData to raw data of art
                set artPath to "\(AppleMusicService.artworkCacheURL.path)"
                set f to open for access (POSIX file artPath) with write permission
                set eof f to 0
                write rawData to f
                close access f
                set f to 0
                return artPath
            end if
        on error
            if f is not 0 then
                try
                    close access f
                end try
            end if
        end try
        return ""
    end tell
    """

    nonisolated public static func makeThumbnailTrack(from track: TrackInfo, artworkData: Data, thumbImage: NSImage? = nil) -> TrackInfo {
        let thumb = thumbImage ?? TrackInfo.downsampledImage(from: artworkData, maxDimension: 160)
        return TrackInfo(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            artworkGradientStartHex: track.artworkGradientStartHex,
            artworkGradientEndHex: track.artworkGradientEndHex,
            artworkData: nil,
            decodedImage: thumb,
            artworkURL: nil,
            source: track.source
        )
    }

    private func fetchArtworkAsync(expectedTrackKey: String) {
        let tempURL = Self.artworkCacheURL
        let exportScript = Self.artworkExportScript

        artworkQueue.async { [weak self] in
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }
            let path = AppleScriptRunner.runSync(exportScript)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = path, !path.isEmpty, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                let thumb = TrackInfo.downsampledImage(from: data, maxDimension: 160)
                DispatchQueue.main.async {
                    guard let self = self, self.lastArtworkTrackId == expectedTrackKey, let track = self.currentTrack else { return }
                    self.currentTrack = Self.makeThumbnailTrack(from: track, artworkData: data, thumbImage: thumb)
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
        AppleScriptRunner.runAsync("tell application \"Music\" to playpause")
        isPlaying.toggle()
    }

    public func nextTrack() {
        guard isRunning else { return }
        AppleScriptRunner.runAsync("tell application \"Music\" to next track")
        refreshState()
    }

    public func previousTrack() {
        guard isRunning else { return }
        AppleScriptRunner.runAsync("tell application \"Music\" to previous track")
        refreshState()
    }

    public func seek(to seconds: TimeInterval) {
        guard isRunning else { return }
        let rounded = Int(seconds)
        AppleScriptRunner.runAsync("tell application \"Music\" to set player position to \(rounded)")
        self.playbackPosition = seconds
    }

    public func setVolume(_ volume: Double) {
        self.volume = max(0.0, min(1.0, volume))
        self.isMuted = (self.volume == 0)
        guard isRunning else { return }
        let intVol = Int(self.volume * 100.0)
        AppleScriptRunner.runAsync("tell application \"Music\" to set sound volume to \(intVol)")
    }

    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        guard isRunning else { return }
        if muted {
            AppleScriptRunner.runAsync("tell application \"Music\" to set mute to true")
        } else {
            AppleScriptRunner.runAsync("tell application \"Music\" to set mute to false")
        }
    }

    public func setShuffle(_ active: Bool) {
        self.isShuffleActive = active
        self.lastUserInteractionTime = CACurrentMediaTime()
        guard isRunning else { return }
        let script = "tell application \"Music\" to set shuffle enabled to \(active ? "true" : "false")"
        AppleScriptRunner.runAsync(script)
    }

    public func setRepeatMode(_ mode: RepeatMode) {
        self.repeatMode = mode
        self.lastUserInteractionTime = CACurrentMediaTime()
        guard isRunning else { return }
        let script = "tell application \"Music\" to set song repeat to \(mode.rawValue)"
        AppleScriptRunner.runAsync(script)
    }
}
