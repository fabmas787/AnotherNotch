import AppKit
import Foundation
import SwiftUI

@MainActor
public final class UnifiedMediaManager: ObservableObject {
    public static let shared = UnifiedMediaManager()

    @Published public var selectedSource: MediaSource = .auto {
        didSet {
            updateActiveService()
        }
    }

    @Published public private(set) var currentTrack: TrackInfo?
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var playbackPosition: TimeInterval = 0.0
    @Published public private(set) var volume: Double = 0.8
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var isShuffleActive: Bool = false
    @Published public private(set) var repeatMode: RepeatMode = .off
    @Published public private(set) var visualizerAmplitudes: [CGFloat] = Array(repeating: 0.05, count: 12)
    @Published public private(set) var isGoingForward: Bool = true

    public let appleMusicService = AppleMusicService()
    public let spotifyService = SpotifyService()
    public let simulatedService = SimulatedMediaService()

    private var pollTimer: Timer?
    private var visualizerTimer: Timer?
    private var directionResetTask: Task<Void, Never>?
    private var wavePhase: Double = 0.0
    private var smoothedAmplitudes: [CGFloat] = Array(repeating: 0.05, count: 12)
    private var lastSeekTime: CFTimeInterval = 0.0
    private var lastVisualizerTick: CFTimeInterval = 0.0

    public var isExpanded: Bool = false {
        didSet {
            guard isExpanded != oldValue else { return }
            if !isExpanded {
                let restingFloor = Array(repeating: CGFloat(0.05), count: 12)
                if visualizerAmplitudes != restingFloor {
                    smoothedAmplitudes = restingFloor
                    visualizerAmplitudes = restingFloor
                }
            }
            restartVisualizerTimer()
        }
    }

    public var isVisualizerActive: Bool {
        visualizerTimer != nil
    }

    public init() {
        updateActiveService()
        startTimers()
    }

    public func stopTimers() {
        pollTimer?.invalidate()
        pollTimer = nil
        visualizerTimer?.invalidate()
        visualizerTimer = nil
        directionResetTask?.cancel()
        directionResetTask = nil
    }

    isolated deinit {
        pollTimer?.invalidate()
        visualizerTimer?.invalidate()
        directionResetTask?.cancel()
    }

    public var effectiveService: MediaServiceProtocol {
        switch selectedSource {
        case .appleMusic:
            return appleMusicService
        case .spotify:
            return spotifyService
        case .demo:
            return simulatedService
        case .auto:
            if spotifyService.isRunning && spotifyService.isPlaying {
                return spotifyService
            } else if appleMusicService.isRunning && appleMusicService.isPlaying {
                return appleMusicService
            } else if spotifyService.isRunning && spotifyService.currentTrack != nil {
                return spotifyService
            } else if appleMusicService.isRunning && appleMusicService.currentTrack != nil {
                return appleMusicService
            } else if spotifyService.isRunning {
                return spotifyService
            } else if appleMusicService.isRunning {
                return appleMusicService
            } else if spotifyService.isAvailable {
                return spotifyService
            } else if appleMusicService.isAvailable {
                return appleMusicService
            } else {
                return simulatedService
            }
        }
    }

    private func startTimers() {
        startPollTimer()
        startVisualizerTimer()
    }

    private func startPollTimer() {
        pollTimer?.invalidate()
        // Poll active service state every 0.35s on common run loop mode
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncFromActiveService()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    public func startVisualizerTimer() {
        guard visualizerTimer == nil else { return }
        lastVisualizerTick = CACurrentMediaTime()
        // Adaptive rate: 60 fps when expanded for silky visualizer & scrubber, 1.0s when collapsed to save CPU/battery
        let interval = isExpanded ? (1.0 / 60.0) : 1.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateVisualizerAndSmoothProgress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        visualizerTimer = timer
    }

    private func restartVisualizerTimer() {
        if visualizerTimer != nil {
            visualizerTimer?.invalidate()
            visualizerTimer = nil
            if isPlaying {
                startVisualizerTimer()
                updateVisualizerAndSmoothProgress()
            }
        }
    }

    public func updateActiveService() {
        syncFromActiveService()
    }

    private func syncFromActiveService() {
        let service = effectiveService
        let newTrack: TrackInfo?
        if selectedSource == .demo {
            newTrack = simulatedService.currentTrack
        } else {
            newTrack = service.currentTrack ?? TrackInfo.idle
        }

        let trackChanged = (self.currentTrack?.id != newTrack?.id || self.currentTrack?.title != newTrack?.title)
        if trackChanged {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                self.currentTrack = newTrack
            }
        }
        if self.isPlaying != service.isPlaying { self.isPlaying = service.isPlaying }
        if self.volume != service.volume { self.volume = service.volume }
        if self.isMuted != service.isMuted { self.isMuted = service.isMuted }
        if self.isShuffleActive != service.isShuffleActive { self.isShuffleActive = service.isShuffleActive }
        if self.repeatMode != service.repeatMode { self.repeatMode = service.repeatMode }

        let servicePos = service.playbackPosition
        let now = CACurrentMediaTime()

        if trackChanged || !self.isPlaying {
            if self.playbackPosition != servicePos {
                self.playbackPosition = servicePos
            }
        } else if (now - lastSeekTime) > 1.0 {
            let delta = servicePos - self.playbackPosition
            // If delta is larger than 2 seconds, the user jumped/sought in the external player
            if abs(delta) > 2.0 {
                self.playbackPosition = servicePos
            } else if delta > 0.1 && delta <= 2.0 {
                // External player is slightly ahead; gently catch up without sudden jerks
                self.playbackPosition += delta * 0.2
            }
            // If delta <= 0.1 (service is behind or equal due to poll latency),
            // do not snap backwards; let smooth progression continue.
        }

        if self.isPlaying && visualizerTimer == nil {
            startVisualizerTimer()
        }
    }

    /// Derives deterministic, stable tempo and groove signature for any track.
    private func stableTempo(for track: TrackInfo?) -> Double {
        guard let track = track else { return 120.0 }
        let titleLower = track.title.lowercased()
        if titleLower.contains("midnight city") { return 105.0 }
        if titleLower.contains("starboy") { return 93.0 }
        if titleLower.contains("solar power") { return 90.0 }
        if titleLower.contains("get lucky") { return 116.0 }
        if titleLower.contains("resonance") { return 85.0 }

        var hash: UInt64 = 5381
        for byte in (track.title + track.artist).utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let offset = Double(hash % 45) // 0..44
        return 90.0 + offset // 90..134 BPM
    }

    /// Accurate multi-band acoustic spectrum simulation with dynamic attack/decay ballistics,
    /// 4/4 musical groove transients, vocal/lead phrasing, and volume-scaled dynamic range.
    public func updateVisualizerAndSmoothProgress(
        now: CFTimeInterval = CACurrentMediaTime(),
        computeVisualizer: Bool? = nil
    ) {
        let dt: TimeInterval
        if lastVisualizerTick > 0 {
            let elapsed = now - lastVisualizerTick
            dt = (elapsed > 0.0001 && elapsed <= 2.5) ? elapsed : (isExpanded ? 0.016 : 1.0)
        } else {
            dt = isExpanded ? 0.016 : 1.0
        }
        lastVisualizerTick = now

        let shouldComputeVisualizer = computeVisualizer ?? isExpanded

        if isPlaying {
            // Smoothly advance playback position in real time
            if let track = currentTrack, track.duration > 0 {
                playbackPosition = min(track.duration, playbackPosition + dt)
                if selectedSource == .demo {
                    simulatedService.seek(to: playbackPosition)
                }
                if playbackPosition >= track.duration {
                    if selectedSource == .demo {
                        if repeatMode == .one {
                            seek(to: 0.0)
                        } else {
                            nextTrack()
                        }
                    }
                    return
                }
            }
        }

        if shouldComputeVisualizer {
            if isPlaying {
                // Derive deterministic tempo and 4/4 musical structure from track properties
                let bpm = stableTempo(for: currentTrack)
                let beatDuration = 60.0 / bpm
                let barDuration = beatDuration * 4.0
                let pos = max(0.0, playbackPosition)

                let barPosition = fmod(pos, barDuration)
                let beatIndex = Int(barPosition / beatDuration) % 4
                let beatPhase = (barPosition - Double(beatIndex) * beatDuration) / beatDuration // 0.0..<1.0

                // Transient models:
                // Kick on Beat 1 (downbeat) and Beat 3 (syncopation)
                let kickWeight: Double
                switch beatIndex {
                case 0: kickWeight = 1.0
                case 2: kickWeight = 0.78
                default: kickWeight = 0.15
                }
                let kickTransient = max(0.0, 1.0 - (beatPhase / 0.18))
                let kickEnergy = kickWeight * pow(kickTransient, 2.2)

                // Snare / Backbeat on Beat 2 and Beat 4
                let snareWeight: Double
                switch beatIndex {
                case 1: snareWeight = 0.88
                case 3: snareWeight = 0.96
                default: snareWeight = 0.0
                }
                let snareTransient = max(0.0, 1.0 - (beatPhase / 0.16))
                let snareEnergy = snareWeight * pow(snareTransient, 2.0)

                // Hi-hats on 8th notes and 16th subdivisions
                let subBeatDuration = beatDuration / 2.0
                let subBeatPhase = fmod(pos, subBeatDuration) / subBeatDuration
                let isOffBeat = fmod(pos, beatDuration) >= subBeatDuration
                let hihatTransient = max(0.0, 1.0 - (subBeatPhase / 0.24))
                let hihatEnergy = pow(hihatTransient, 1.8)
                let openHatTransient = isOffBeat ? max(0.0, 1.0 - (subBeatPhase / 0.42)) : 0.0
                let openHatEnergy = pow(openHatTransient, 1.6)

                // Melodic and vocal phrasing (harmonic movement across phrases)
                let phraseCycle = fmod(pos, barDuration * 4.0) / (barDuration * 4.0)
                let phraseEnvelope = 0.75 + 0.25 * sin(phraseCycle * .pi * 2.0)
                let vocalFlow = (sin(pos * 2.6) * 0.32 + cos(pos * 1.3) * 0.22 + 0.44) * phraseEnvelope
                let leadFlow = (sin(pos * 3.4 + 1.2) * 0.28 + cos(pos * 1.8) * 0.20 + 0.48) * phraseEnvelope
                let bassFlow = (sin(pos * (2.0 * .pi / (beatDuration * 2.0))) * 0.22 + 0.38)

                // Cymbal and air resonance (deterministic harmonic shimmer, no random white noise)
                let cymbalShimmer = sin(pos * 11.3) * 0.06 + cos(pos * 17.1) * 0.05 + 0.12
                let airShimmer = sin(pos * 13.7) * 0.05 + cos(pos * 23.4) * 0.04 + 0.10

                // Dynamic gain scaling with volume and mute
                let gain: CGFloat
                if isMuted || volume <= 0.001 {
                    gain = 0.0
                } else {
                    gain = CGFloat(max(0.0, min(1.0, volume)))
                }

                // Target amplitudes across 12 distinct frequency bands:
                // 0: Sub-bass (40-60Hz)
                // 1: Bass (80-120Hz)
                // 2: Upper Bass / Punch (200Hz)
                // 3: Low Mids / Snare Body (350Hz)
                // 4: Vocals / Mids (700Hz)
                // 5: Vocal Presence (1.5kHz)
                // 6: Snare Bite / Presence (3kHz)
                // 7: Percussion / Crunch (5kHz)
                // 8: Closed Hi-hats (8kHz)
                // 9: Open Hi-hats / Cymbals (12kHz)
                // 10: Shimmer / Ride (15kHz)
                // 11: Top Air / Ambience (18kHz)
                var rawTargets: [CGFloat] = []
                rawTargets.append(CGFloat(min(1.0, 0.10 + 0.85 * kickEnergy + 0.08 * bassFlow)))
                rawTargets.append(CGFloat(min(1.0, 0.12 + 0.76 * kickEnergy + 0.20 * bassFlow)))
                rawTargets.append(CGFloat(min(1.0, 0.12 + 0.58 * kickEnergy + 0.25 * vocalFlow)))
                rawTargets.append(CGFloat(min(1.0, 0.10 + 0.32 * kickEnergy + 0.42 * vocalFlow + 0.20 * snareEnergy)))
                rawTargets.append(CGFloat(min(1.0, 0.12 + 0.54 * vocalFlow + 0.26 * snareEnergy)))
                rawTargets.append(CGFloat(min(1.0, 0.12 + 0.48 * leadFlow + 0.34 * snareEnergy)))
                rawTargets.append(CGFloat(min(1.0, 0.10 + 0.40 * leadFlow + 0.48 * snareEnergy)))
                rawTargets.append(CGFloat(min(1.0, 0.08 + 0.32 * snareEnergy + 0.54 * hihatEnergy)))
                rawTargets.append(CGFloat(min(1.0, 0.08 + 0.65 * hihatEnergy + 0.18 * openHatEnergy)))
                rawTargets.append(CGFloat(min(1.0, 0.07 + 0.42 * hihatEnergy + 0.50 * openHatEnergy + cymbalShimmer)))
                rawTargets.append(CGFloat(min(1.0, 0.06 + 0.25 * hihatEnergy + 0.42 * openHatEnergy + airShimmer)))
                rawTargets.append(CGFloat(min(1.0, 0.05 + 0.18 * hihatEnergy + 0.32 * openHatEnergy + airShimmer)))

                // Scale targets by volume gain, preserving resting floor at 0.05 when muted
                let targets = rawTargets.map { raw -> CGFloat in
                    let resting: CGFloat = 0.05
                    return resting + (raw - resting) * gain
                }

                // Asymmetric ballistic smoothing: fast attack (snappy transients), smooth acoustic decay
                for i in 0..<12 {
                    let target = targets[i]
                    let current = smoothedAmplitudes[i]
                    let attackRate: CGFloat
                    let decayRate: CGFloat
                    if i < 3 {
                        attackRate = 0.74
                        decayRate = 0.18
                    } else if i < 7 {
                        attackRate = 0.78
                        decayRate = 0.22
                    } else {
                        attackRate = 0.84
                        decayRate = 0.26
                    }

                    if target > current {
                        smoothedAmplitudes[i] += (target - current) * attackRate
                    } else {
                        smoothedAmplitudes[i] += (target - current) * decayRate
                    }
                }
                if self.visualizerAmplitudes != smoothedAmplitudes {
                    self.visualizerAmplitudes = smoothedAmplitudes
                }
            } else {
                // Resting state: graceful exponential decay to resting floor
                var allAtFloor = true
                for i in 0..<12 {
                    let current = smoothedAmplitudes[i]
                    let next = current + (0.05 - current) * 0.20
                    smoothedAmplitudes[i] = next
                    if next > 0.051 {
                        allAtFloor = false
                    }
                }
                if allAtFloor {
                    smoothedAmplitudes = Array(repeating: 0.05, count: 12)
                    if self.visualizerAmplitudes != smoothedAmplitudes {
                        self.visualizerAmplitudes = smoothedAmplitudes
                    }
                    visualizerTimer?.invalidate()
                    visualizerTimer = nil
                    lastVisualizerTick = 0.0
                } else {
                    if self.visualizerAmplitudes != smoothedAmplitudes {
                        self.visualizerAmplitudes = smoothedAmplitudes
                    }
                }
            }
        } else {
            // Collapsed: visualizer is not rendered, skip 12-band DSP simulation to save CPU & battery
            let restingFloor = Array(repeating: CGFloat(0.05), count: 12)
            if self.visualizerAmplitudes != restingFloor {
                smoothedAmplitudes = restingFloor
                self.visualizerAmplitudes = restingFloor
            }
            if !isPlaying {
                visualizerTimer?.invalidate()
                visualizerTimer = nil
                lastVisualizerTick = 0.0
            }
        }
    }

    public func openPlayer(for source: MediaSource) {
        switch source {
        case .appleMusic:
            appleMusicService.launchPlayer()
        case .spotify:
            spotifyService.launchPlayer()
        case .auto:
            if spotifyService.isRunning {
                spotifyService.launchPlayer()
            } else if appleMusicService.isRunning {
                appleMusicService.launchPlayer()
            } else if spotifyService.isAvailable {
                spotifyService.launchPlayer()
            } else if appleMusicService.isAvailable {
                appleMusicService.launchPlayer()
            }
        case .demo:
            break
        }
    }

    public func openPreferredPlayer() {
        openPlayer(for: effectiveService.source)
    }

    public func playPause() {
        let service = effectiveService
        if !service.isRunning && selectedSource != .demo {
            openPlayer(for: service.source)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.effectiveService.playPause()
                self?.syncFromActiveService()
            }
            return
        }
        service.playPause()
        self.isPlaying = service.isPlaying
        if self.isPlaying && visualizerTimer == nil {
            startVisualizerTimer()
        }
    }

    public func nextTrack() {
        directionResetTask?.cancel()
        isGoingForward = true
        effectiveService.nextTrack()
        syncFromActiveService()
    }

    public func previousTrack() {
        directionResetTask?.cancel()
        isGoingForward = false
        effectiveService.previousTrack()
        syncFromActiveService()
        directionResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.isGoingForward = true
        }
    }

    public func seek(to seconds: TimeInterval) {
        effectiveService.seek(to: seconds)
        self.playbackPosition = seconds
        self.lastSeekTime = CACurrentMediaTime()
        if selectedSource == .demo {
            simulatedService.seek(to: seconds)
        }
    }

    public func setVolume(_ volume: Double) {
        self.volume = max(0.0, min(1.0, volume))
        self.isMuted = (self.volume == 0)
        effectiveService.setVolume(self.volume)
    }

    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        effectiveService.setMuted(muted)
        self.volume = effectiveService.volume
    }

    public func setShuffle(_ active: Bool) {
        effectiveService.setShuffle(active)
        self.isShuffleActive = effectiveService.isShuffleActive
    }

    public func toggleShuffle() {
        effectiveService.toggleShuffle()
        self.isShuffleActive = effectiveService.isShuffleActive
    }

    public func setRepeatMode(_ mode: RepeatMode) {
        effectiveService.setRepeatMode(mode)
        self.repeatMode = effectiveService.repeatMode
    }

    public func cycleRepeatMode() {
        effectiveService.cycleRepeatMode()
        self.repeatMode = effectiveService.repeatMode
    }
}
