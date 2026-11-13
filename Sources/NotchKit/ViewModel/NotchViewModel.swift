import AppKit
import Foundation
import Combine
import SwiftUI

@MainActor
public final class NotchViewModel: ObservableObject {
    @Published public var isHovered: Bool = false
    @Published public var isPinned: Bool = false
    @Published public var showLyrics: Bool {
        didSet {
            UserDefaults.standard.set(showLyrics, forKey: "notch_show_lyrics")
        }
    }
    @Published public var volume: Double = 0.8 {
        didSet {
            if volume != oldValue {
                mediaManager.setVolume(volume)
            }
        }
    }
    @Published public var isMuted: Bool = false {
        didSet {
            if isMuted != oldValue {
                mediaManager.setMuted(isMuted)
            }
        }
    }
    @Published public var isScrubbing: Bool = false
    @Published public var scrubPosition: TimeInterval = 0.0
    public var isShuffleActive: Bool {
        get { mediaManager.isShuffleActive }
        set { mediaManager.setShuffle(newValue) }
    }
    public var repeatMode: RepeatMode {
        get { mediaManager.repeatMode }
        set { mediaManager.setRepeatMode(newValue) }
    }
    @Published public var playPauseBounceTrigger: Int = 0
    @Published public var nextBounceTrigger: Int = 0
    @Published public var prevBounceTrigger: Int = 0

    public var isGoingForward: Bool {
        mediaManager.isGoingForward
    }

    public private(set) var isHoverSuppressed: Bool = false

    public let screenManager: ScreenNotchManager
    public let mediaManager: UnifiedMediaManager
    public let lyricsService: LyricsService

    private var exitDebounceTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    public var isExpanded: Bool {
        isPinned || isHovered
    }

    public var preferredPlayerName: String {
        mediaManager.effectiveService.source.rawValue
    }

    public var preferredPlayerIcon: String {
        mediaManager.effectiveService.source.systemIcon
    }

    public func openPreferredPlayer() {
        mediaManager.openPreferredPlayer()
    }

    public init(
        screenManager: ScreenNotchManager = .shared,
        mediaManager: UnifiedMediaManager = .shared,
        lyricsService: LyricsService = .shared
    ) {
        self.screenManager = screenManager
        self.mediaManager = mediaManager
        self.lyricsService = lyricsService
        self.volume = mediaManager.volume
        self.isMuted = mediaManager.isMuted
        self.showLyrics = (UserDefaults.standard.object(forKey: "notch_show_lyrics") as? Bool) ?? true

        // Forward objectWillChange so SwiftUI views update seamlessly
        screenManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        mediaManager.objectWillChange
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        lyricsService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Sync expansion state to mediaManager for adaptive refresh rates
        self.mediaManager.isExpanded = self.isExpanded
        $isHovered.combineLatest($isPinned)
            .map { $0 || $1 }
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.mediaManager.isExpanded = expanded
            }
            .store(in: &cancellables)

        // Automatically fetch lyrics when track changes
        mediaManager.$currentTrack
            .removeDuplicates()
            .sink { [weak self] track in
                self?.lyricsService.fetchLyrics(for: track)
            }
            .store(in: &cancellables)

        lyricsService.fetchLyrics(for: mediaManager.currentTrack)
    }

    public func onMouseEnter() {
        guard !isHoverSuppressed else { return }
        exitDebounceTimer?.invalidate()
        exitDebounceTimer = nil
        mediaManager.effectiveService.refreshState()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.80, blendDuration: 0.0)) {
            self.isHovered = true
        }
    }

    public func onMouseExit() {
        isHoverSuppressed = false
        exitDebounceTimer?.invalidate()
        let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 1.00, blendDuration: 0.0)) {
                    self.isHovered = false
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        exitDebounceTimer = timer
    }

    public func collapse() {
        exitDebounceTimer?.invalidate()
        exitDebounceTimer = nil
        isHoverSuppressed = true
        withAnimation(.spring(response: 0.45, dampingFraction: 1.00, blendDuration: 0.0)) {
            self.isPinned = false
            self.isHovered = false
        }
    }

    public func clearHoverSuppression() {
        exitDebounceTimer?.invalidate()
        exitDebounceTimer = nil
        isHoverSuppressed = false
    }

    public func toggleMute() {
        self.isMuted.toggle()
    }

    public func togglePin() {
        let spring: Animation = self.isPinned
            ? .spring(response: 0.45, dampingFraction: 1.00)
            : .spring(response: 0.42, dampingFraction: 0.80)
        withAnimation(spring) {
            self.isPinned.toggle()
        }
    }

    public func toggleLyrics() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            self.showLyrics.toggle()
        }
    }

    public func openPlayer(_ source: MediaSource) {
        mediaManager.openPlayer(for: source)
    }

    public func togglePlayPause() {
        playPauseBounceTrigger += 1
        mediaManager.playPause()
    }

    public func nextTrack() {
        nextBounceTrigger += 1
        mediaManager.nextTrack()
    }

    public func previousTrack() {
        prevBounceTrigger += 1
        mediaManager.previousTrack()
    }

    public func toggleShuffle() {
        withAnimation(.easeInOut(duration: 0.2)) {
            mediaManager.toggleShuffle()
        }
    }

    public func cycleRepeatMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            mediaManager.cycleRepeatMode()
        }
    }

    public func seek(to seconds: TimeInterval) {
        mediaManager.seek(to: seconds)
    }

    public func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    public func formatRemainingTime(current: TimeInterval, total: TimeInterval) -> String {
        let remaining = max(0, total - current)
        let totalSeconds = Int(remaining.rounded())
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "-%d:%02d", minutes, secs)
    }
}
