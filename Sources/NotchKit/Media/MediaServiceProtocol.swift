import Foundation

public enum RepeatMode: String, CaseIterable, Sendable {
    case off
    case all
    case one
}

@MainActor
public protocol MediaServiceProtocol: AnyObject {
    var source: MediaSource { get }
    var isAvailable: Bool { get }
    var isRunning: Bool { get }
    var currentTrack: TrackInfo? { get }
    var isPlaying: Bool { get }
    var playbackPosition: TimeInterval { get }
    var volume: Double { get }
    var isMuted: Bool { get }
    var isShuffleActive: Bool { get }
    var repeatMode: RepeatMode { get }

    func playPause()
    func nextTrack()
    func previousTrack()
    func seek(to seconds: TimeInterval)
    func setVolume(_ volume: Double)
    func setMuted(_ muted: Bool)
    func refreshState()
    func setShuffle(_ active: Bool)
    func setRepeatMode(_ mode: RepeatMode)
    func toggleShuffle()
    func cycleRepeatMode()
}

extension MediaServiceProtocol {
    public func toggleShuffle() {
        setShuffle(!isShuffleActive)
    }

    public func cycleRepeatMode() {
        let next: RepeatMode
        switch repeatMode {
        case .off: next = .all
        case .all: next = .one
        case .one: next = .off
        }
        setRepeatMode(next)
    }
}
