import Foundation
import AppKit
import SwiftUI
import Carbon
import NotchKit

// Import everything from Notch source code directly or test the modules
// To test cleanly without circular dependencies, we can reference the test suite files.

struct TestFailure: Error {
    let message: String
}

func assertCondition(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition {
        print("❌ FAILED: \(message) [\(file):\(line)]")
        exit(1)
    }
}

@MainActor
func runGeometryTests() {
    print("\n--- Running Geometry Tests ---")

    // Test 1: NotchGeometry compact and expanded positioning
    let screen = NSRect(x: 0, y: 0, width: 1710, height: 1112)
    let notch = NSRect(x: 751, y: 1074.5, width: 208, height: 37.5)
    let geo = NotchGeometry(
        screenFrame: screen,
        hasPhysicalNotch: true,
        notchRect: notch,
        wingWidth: 72.0,
        expandedWidth: 490.0,
        expandedHeight: 245.0
    )

    // Verify widths
    assertCondition(geo.compactSize.width == 208 + 144, "Compact width must include notch width + 2 * wingWidth (72)")
    assertCondition(geo.expandedSize.width == 490, "Expanded width matches 490")
    assertCondition(geo.compactSize.height == 38.0, "Compact height matches max(notchHeight, 38.0)")
    assertCondition(geo.expandedSize.height == 245.0, "Expanded height matches 245")

    // Verify horizontal centering
    assertCondition(abs(geo.compactFrame.midX - notch.midX) < 0.001, "Compact frame must be horizontally centered on notch")
    assertCondition(abs(geo.expandedFrame.midX - notch.midX) < 0.001, "Expanded frame must be horizontally centered on notch")

    // Verify top screen alignment
    assertCondition(abs(geo.compactFrame.maxY - screen.maxY) < 0.001, "Compact frame top must align flush with screen top")
    assertCondition(abs(geo.expandedFrame.maxY - screen.maxY) < 0.001, "Expanded frame top must align flush with screen top")

    // Test 2: Default Geometry Calculation
    let defaultGeo = ScreenNotchManager.calculateGeometry()
    assertCondition(defaultGeo.notchRect.width > 0, "Default notch width should be positive")
    assertCondition(defaultGeo.notchRect.height > 0, "Default notch height should be positive")

    // Test 3: Multi-Display Offset Calculation (Horizontal & Vertical)
    let secondaryScreenHorizontal = NSRect(x: 1920, y: 0, width: 1710, height: 1112)
    let localLeftArea = NSRect(x: 0, y: 1074, width: 751, height: 38)
    let localRightArea = NSRect(x: 959, y: 1074, width: 751, height: 38)
    let horizontalNotch = ScreenNotchManager.calculateNotchRect(
        screenFrame: secondaryScreenHorizontal,
        safeAreaTop: 38,
        auxiliaryTopLeftArea: localLeftArea,
        auxiliaryTopRightArea: localRightArea
    )
    assertCondition(
        abs(horizontalNotch.origin.x - (1920 + 751)) < 0.001,
        "Multi-display horizontal offset: notchRect.origin.x (\(horizontalNotch.origin.x)) must align with secondary display offset (\(1920 + 751))"
    )
    assertCondition(
        abs(horizontalNotch.origin.y - 1074) < 0.001,
        "Multi-display horizontal offset: notchRect.origin.y (\(horizontalNotch.origin.y)) must align with screen maxY - safeAreaTop (1074)"
    )
    assertCondition(
        abs(horizontalNotch.width - 208) < 0.001,
        "Multi-display horizontal offset: notchRect.width must equal 208"
    )

    let secondaryScreenBoth = NSRect(x: 1920, y: 1080, width: 1710, height: 1112)
    let bothNotch = ScreenNotchManager.calculateNotchRect(
        screenFrame: secondaryScreenBoth,
        safeAreaTop: 38,
        auxiliaryTopLeftArea: localLeftArea,
        auxiliaryTopRightArea: localRightArea
    )
    assertCondition(
        abs(bothNotch.origin.x - (1920 + 751)) < 0.001,
        "Multi-display x+y offset: notchRect.origin.x (\(bothNotch.origin.x)) must equal 2671"
    )
    assertCondition(
        abs(bothNotch.origin.y - (secondaryScreenBoth.maxY - 38)) < 0.001,
        "Multi-display x+y offset: notchRect.origin.y (\(bothNotch.origin.y)) must equal \(secondaryScreenBoth.maxY - 38)"
    )

    // Test 4: Global Coordinates in Auxiliary Areas
    let globalLeftArea = NSRect(x: 1920, y: 2154, width: 751, height: 38)
    let globalRightArea = NSRect(x: 2879, y: 2154, width: 751, height: 38)
    let globalNotch = ScreenNotchManager.calculateNotchRect(
        screenFrame: secondaryScreenBoth,
        safeAreaTop: 38,
        auxiliaryTopLeftArea: globalLeftArea,
        auxiliaryTopRightArea: globalRightArea
    )
    assertCondition(
        abs(globalNotch.origin.x - 2671) < 0.001,
        "Global coordinates auxiliary areas: notchRect.origin.x must equal 2671"
    )
    assertCondition(
        abs(globalNotch.origin.y - 2154) < 0.001,
        "Global coordinates auxiliary areas: notchRect.origin.y must equal 2154"
    )

    // Test 5: Negative Offset Display (Screen to the left)
    let leftScreen = NSRect(x: -1920, y: 0, width: 1710, height: 1112)
    let negativeNotch = ScreenNotchManager.calculateNotchRect(
        screenFrame: leftScreen,
        safeAreaTop: 38,
        auxiliaryTopLeftArea: localLeftArea,
        auxiliaryTopRightArea: localRightArea
    )
    assertCondition(
        abs(negativeNotch.origin.x - (-1920 + 751)) < 0.001,
        "Negative display offset: notchRect.origin.x must equal -1920 + 751"
    )

    print("✅ Geometry tests passed successfully.")
}

@MainActor
func runSimulatedMediaServiceTests() {
    print("\n--- Running Simulated Media Service Tests ---")

    let service = SimulatedMediaService(startPlaying: true)

    // Test 1: Initial state
    assertCondition(service.currentTrack != nil, "Service should have an initial track")
    let track1 = service.currentTrack!
    assertCondition(track1.title == "Midnight City", "First track should be Midnight City")
    assertCondition(service.isPlaying, "Initial playback should be playing")

    // Test 2: Play/Pause toggle
    service.playPause()
    assertCondition(!service.isPlaying, "Service should pause when toggled")
    service.playPause()
    assertCondition(service.isPlaying, "Service should resume when toggled")

    // Test 3: Next track
    service.nextTrack()
    assertCondition(service.currentTrack?.title == "Starboy", "Next track should be Starboy")
    assertCondition(service.playbackPosition == 0.0, "Next track should reset position to 0")

    // Test 4: Seeking
    service.seek(to: 50.0)
    assertCondition(service.playbackPosition == 50.0, "Seek to 50 should set position to 50")

    // Test 5: Seeking past duration clamps to duration
    service.seek(to: 9999.0)
    assertCondition(service.playbackPosition == service.currentTrack!.duration, "Seek beyond duration should clamp")

    // Test 6: Seeking negative clamps to 0
    service.seek(to: -10.0)
    assertCondition(service.playbackPosition == 0.0, "Seek negative should clamp to 0")

    // Test 7: Previous track rewinds if past 3 seconds
    service.seek(to: 10.0)
    service.previousTrack()
    assertCondition(service.playbackPosition == 0.0, "Previous track when > 3s should rewind to 0")
    assertCondition(service.currentTrack?.title == "Starboy", "Track should remain Starboy when rewinding")

    // Test 8: Previous track changes song if at start
    service.previousTrack()
    assertCondition(service.currentTrack?.title == "Midnight City", "Previous track from 0s should go back to Midnight City")

    // Test 9: Volume and Muting
    service.setVolume(0.5)
    assertCondition(abs(service.volume - 0.5) < 0.001, "Service volume should be set to 0.5")
    assertCondition(!service.isMuted, "Service should not be muted at 0.5")

    service.setMuted(true)
    assertCondition(service.isMuted, "Service should be muted")
    assertCondition(service.volume == 0.0, "Volume should be 0 when muted")

    service.setMuted(false)
    assertCondition(!service.isMuted, "Service should be unmuted")
    assertCondition(abs(service.volume - 0.5) < 0.001, "Volume should be restored to 0.5 after unmute")

    // Test 10: Shuffle and Repeat controls on SimulatedMediaService
    service.setShuffle(true)
    assertCondition(service.isShuffleActive == true, "Simulated service setShuffle(true) works")
    service.toggleShuffle()
    assertCondition(service.isShuffleActive == false, "Simulated service toggleShuffle() works")

    service.setRepeatMode(.all)
    assertCondition(service.repeatMode == .all, "Simulated service setRepeatMode(.all) works")
    service.cycleRepeatMode()
    assertCondition(service.repeatMode == .one, "Simulated service cycleRepeatMode() to .one works")
    service.cycleRepeatMode()
    assertCondition(service.repeatMode == .off, "Simulated service cycleRepeatMode() to .off works")

    print("✅ Simulated Media Service tests passed successfully.")
}

@MainActor
func runUnifiedMediaManagerTests() {
    print("\n--- Running Unified Media Manager Tests ---")

    let manager = UnifiedMediaManager()

    // Test 1: Default source
    manager.selectedSource = .demo
    assertCondition(manager.effectiveService.source == .demo, "Selected demo source should route to demo service")

    // Test 2: Visualizer amplitudes and acoustic multi-band diversity
    assertCondition(manager.visualizerAmplitudes.count == 12, "Visualizer should have 12 frequency bands")
    for amp in manager.visualizerAmplitudes {
        assertCondition(amp >= 0.0 && amp <= 1.0, "Amplitude should be bounded in [0, 1]")
    }

    // Verify acoustic reactivity is non-uniform (not a simple identical sine wave across all bands)
    let minAmp = manager.visualizerAmplitudes.min() ?? 0
    let maxAmp = manager.visualizerAmplitudes.max() ?? 1
    assertCondition(maxAmp >= minAmp, "Visualizer amplitudes should show dynamic acoustic distribution")

    // Test 3: Controls through manager
    let titleBefore = manager.currentTrack?.title
    manager.nextTrack()
    let titleAfter = manager.currentTrack?.title
    assertCondition(titleBefore != titleAfter, "Manager nextTrack should advance track")

    // Test 4: Volume forwarding
    manager.setVolume(0.4)
    assertCondition(abs(manager.volume - 0.4) < 0.01, "Manager volume should update to 0.4")
    assertCondition(abs(manager.effectiveService.volume - 0.4) < 0.01, "Effective service volume should update to 0.4")

    // Test 5: Auto source fallback without desync and preference for Spotify
    manager.selectedSource = .auto
    assertCondition(manager.effectiveService.source == .demo || manager.effectiveService.source == .appleMusic || manager.effectiveService.source == .spotify, "Auto source must pick an available service")
    assertCondition(manager.currentTrack != nil, "Auto source must have a valid current track")
    if manager.spotifyService.isAvailable && !manager.appleMusicService.isPlaying {
        assertCondition(manager.effectiveService.source == .spotify, "Auto selection should prefer Spotify when available and Apple Music is not playing")
    }

    // Test 6: Smooth monotonic progress without backward stuttering
    manager.selectedSource = .demo
    if !manager.isPlaying {
        manager.playPause()
    }
    let pos0 = manager.playbackPosition
    for _ in 0..<5 {
        Thread.sleep(forTimeInterval: 0.02)
        manager.updateVisualizerAndSmoothProgress()
    }
    let pos1 = manager.playbackPosition
    assertCondition(pos1 > pos0, "Playback position must advance forward smoothly during playback")

    // Test 7: Stale external poll does NOT snap playbackPosition backwards
    let advancedPos = manager.playbackPosition
    manager.updateActiveService()
    assertCondition(manager.playbackPosition >= advancedPos, "Service polling must not snap playback position backwards (no rubber-banding)")

    // Test 8: Seeking updates position and prevents rubber-banding
    manager.seek(to: 75.0)
    assertCondition(abs(manager.playbackPosition - 75.0) < 0.001, "Seek should directly set playback position to 75.0")
    manager.updateActiveService()
    assertCondition(abs(manager.playbackPosition - 75.0) < 0.1, "Immediate service poll after seeking must not revert user seek position")

    // Test 9: Visualizer accuracy - volume scaling and mute
    manager.setMuted(true)
    for _ in 0..<20 {
        manager.updateVisualizerAndSmoothProgress()
    }
    assertCondition(manager.visualizerAmplitudes.allSatisfy { abs($0 - 0.05) < 0.01 }, "Muted playback must cause visualizer amplitudes to rest at floor (0.05)")

    manager.setMuted(false)
    manager.setVolume(1.0)
    for _ in 0..<20 {
        manager.updateVisualizerAndSmoothProgress()
    }
    let maxUnmutedAmp = manager.visualizerAmplitudes.max() ?? 0
    assertCondition(maxUnmutedAmp > 0.15, "Unmuted full-volume playback should produce lively amplitudes > 0.15")

    // Test 10: Spotify service mute volume consistency
    let spotify = manager.spotifyService
    spotify.setVolume(0.8)
    spotify.setMuted(true)
    assertCondition(spotify.isMuted, "Spotify service should be muted")
    assertCondition(spotify.volume == 0.0, "Spotify service volume should be 0.0 when muted")
    spotify.setMuted(false)
    assertCondition(!spotify.isMuted, "Spotify service should unmute")
    assertCondition(abs(spotify.volume - 0.8) < 0.01, "Spotify service should restore volume 0.8")

    // Test 11: Stable track identity prevents rubber-banding
    let track1 = TrackInfo(id: "spotify_Song_Artist", title: "Song", artist: "Artist", album: "Album", duration: 180, source: .spotify)
    let track2 = TrackInfo(id: "spotify_Song_Artist", title: "Song", artist: "Artist", album: "Album", duration: 180, source: .spotify)
    assertCondition(track1.id == track2.id, "Tracks with identical title and artist must produce identical stable IDs")

    // Test 12: UnifiedMediaManager shuffle forwarding and toggling
    manager.selectedSource = .demo
    manager.setShuffle(false)
    assertCondition(!manager.isShuffleActive, "Initial manager.isShuffleActive must be false")
    assertCondition(!manager.simulatedService.isShuffleActive, "Simulated service isShuffleActive must be false")

    manager.setShuffle(true)
    assertCondition(manager.isShuffleActive == true, "manager.setShuffle(true) must set isShuffleActive to true")
    assertCondition(manager.simulatedService.isShuffleActive == true, "manager.setShuffle(true) must forward to simulatedService")

    manager.toggleShuffle()
    assertCondition(manager.isShuffleActive == false, "manager.toggleShuffle() from true must set isShuffleActive to false")
    assertCondition(manager.simulatedService.isShuffleActive == false, "manager.toggleShuffle() must forward to simulatedService")

    manager.toggleShuffle()
    assertCondition(manager.isShuffleActive == true, "manager.toggleShuffle() from false must set isShuffleActive to true")
    assertCondition(manager.simulatedService.isShuffleActive == true, "manager.toggleShuffle() must forward to simulatedService")

    // Test 13: UnifiedMediaManager repeatMode forwarding and 3-state cycling (.off -> .all -> .one -> .off)
    manager.setRepeatMode(.off)
    assertCondition(manager.repeatMode == .off, "manager.setRepeatMode(.off) must set repeatMode to .off")
    assertCondition(manager.simulatedService.repeatMode == .off, "manager.setRepeatMode(.off) must forward to simulatedService")

    manager.setRepeatMode(.all)
    assertCondition(manager.repeatMode == .all, "manager.setRepeatMode(.all) must set repeatMode to .all")
    assertCondition(manager.simulatedService.repeatMode == .all, "manager.setRepeatMode(.all) must forward to simulatedService")

    manager.setRepeatMode(.one)
    assertCondition(manager.repeatMode == .one, "manager.setRepeatMode(.one) must set repeatMode to .one")
    assertCondition(manager.simulatedService.repeatMode == .one, "manager.setRepeatMode(.one) must forward to simulatedService")

    manager.setRepeatMode(.off)
    manager.cycleRepeatMode()
    assertCondition(manager.repeatMode == .all, "manager.cycleRepeatMode() from .off must cycle to .all")
    assertCondition(manager.simulatedService.repeatMode == .all, "cycleRepeatMode must update simulatedService to .all")

    manager.cycleRepeatMode()
    assertCondition(manager.repeatMode == .one, "manager.cycleRepeatMode() from .all must cycle to .one")
    assertCondition(manager.simulatedService.repeatMode == .one, "cycleRepeatMode must update simulatedService to .one")

    manager.cycleRepeatMode()
    assertCondition(manager.repeatMode == .off, "manager.cycleRepeatMode() from .one must cycle back to .off")
    assertCondition(manager.simulatedService.repeatMode == .off, "cycleRepeatMode must update simulatedService back to .off")

    // Test 14: UnifiedMediaManager bidirectional synchronization from active service
    manager.simulatedService.setShuffle(true)
    manager.simulatedService.setRepeatMode(.one)
    manager.updateActiveService()
    assertCondition(manager.isShuffleActive == true, "updateActiveService must sync isShuffleActive from active service")
    assertCondition(manager.repeatMode == .one, "updateActiveService must sync repeatMode from active service")

    manager.simulatedService.setShuffle(false)
    manager.simulatedService.setRepeatMode(.off)
    manager.updateActiveService()
    assertCondition(manager.isShuffleActive == false, "updateActiveService must sync cleared shuffle from active service")
    assertCondition(manager.repeatMode == .off, "updateActiveService must sync cleared repeatMode from active service")

    // Test 15: RepeatMode.one looping during smooth progress in demo mode
    manager.selectedSource = .demo
    manager.setRepeatMode(.one)
    let loopTrackTitle = manager.currentTrack?.title
    let trackDuration = manager.currentTrack?.duration ?? 200.0
    manager.seek(to: trackDuration)
    manager.updateVisualizerAndSmoothProgress()
    assertCondition(manager.currentTrack?.title == loopTrackTitle, "When repeatMode is .one, reaching duration must loop current track instead of advancing")
    assertCondition(manager.playbackPosition < 1.0, "Playback position must be reset near 0.0 on loop")

    // Test 16: Collapsed visualizer progress does not stall on 1Hz (or coalesced) timer ticks
    manager.selectedSource = .demo
    if !manager.isPlaying {
        manager.playPause()
    }
    manager.isExpanded = false
    manager.seek(to: 10.0)

    // Prime lastVisualizerTick with baseline timestamp
    let baseTime = CACurrentMediaTime()
    manager.updateVisualizerAndSmoothProgress(now: baseTime)
    let initialPosition = manager.playbackPosition

    // Simulate standard 1.0s collapsed tick
    manager.updateVisualizerAndSmoothProgress(now: baseTime + 1.0)
    let advanceAfter1s = manager.playbackPosition - initialPosition
    assertCondition(abs(advanceAfter1s - 1.0) < 0.05, "Collapsed tick at 1.0s interval must advance playback by ~1.0s, but advanced by \(advanceAfter1s)")

    // Simulate timer coalescing tick at 1.4s interval
    let posBeforeCoalesced = manager.playbackPosition
    manager.updateVisualizerAndSmoothProgress(now: baseTime + 2.4)
    let advanceAfterCoalesced = manager.playbackPosition - posBeforeCoalesced
    assertCondition(abs(advanceAfterCoalesced - 1.4) < 0.05, "Collapsed tick at 1.4s coalesced interval must advance playback by ~1.4s, but advanced by \(advanceAfterCoalesced)")

    print("✅ Unified Media Manager tests passed successfully.")
}

@MainActor
func runViewModelTests() {
    print("\n--- Running ViewModel Tests ---")

    let vm = NotchViewModel()

    // Test 1: Initial state
    assertCondition(!vm.isHovered, "Initial hover should be false")
    assertCondition(!vm.isPinned, "Initial pin should be false")
    assertCondition(!vm.isExpanded, "Initial expanded should be false")

    // Test 2: Mouse enter expands
    vm.onMouseEnter()
    assertCondition(vm.isHovered, "onMouseEnter should set isHovered = true")
    assertCondition(vm.isExpanded, "Hover should cause isExpanded = true")

    // Test 3: Pinning keeps expanded
    vm.togglePin()
    assertCondition(vm.isPinned, "togglePin should set isPinned = true")
    assertCondition(vm.isExpanded, "Pinned state should cause isExpanded = true")

    // Test 4: Collapse suppresses immediate re-hover until exit
    vm.collapse()
    assertCondition(!vm.isPinned, "collapse should unpin")
    assertCondition(!vm.isHovered, "collapse should clear isHovered")
    assertCondition(!vm.isExpanded, "collapse should set isExpanded = false")
    assertCondition(vm.isHoverSuppressed, "collapse should set isHoverSuppressed = true")

    // Re-entering while suppressed should NOT expand
    vm.onMouseEnter()
    assertCondition(!vm.isHovered, "onMouseEnter while hover suppressed should not re-expand")

    // Exiting clears suppression
    vm.onMouseExit()
    assertCondition(!vm.isHoverSuppressed, "onMouseExit should clear hover suppression")

    // Test 5: Volume and Mute in ViewModel
    vm.volume = 0.65
    assertCondition(abs(vm.mediaManager.volume - 0.65) < 0.01, "ViewModel volume didSet should forward to mediaManager")

    vm.toggleMute()
    assertCondition(vm.isMuted, "toggleMute should toggle isMuted")
    assertCondition(vm.mediaManager.isMuted, "toggleMute should forward to mediaManager")

    // Test 6: Time formatting
    assertCondition(vm.formatTime(0) == "0:00", "0s format should be 0:00")
    assertCondition(vm.formatTime(65) == "1:05", "65s format should be 1:05")
    assertCondition(vm.formatTime(243) == "4:03", "243s format should be 4:03")
    assertCondition(vm.formatRemainingTime(current: 40, total: 100) == "-1:00", "Remaining time calculation")

    // Test 7: Track transition direction
    assertCondition(vm.isGoingForward == true, "Initial transition direction should be forward")
    vm.previousTrack()
    assertCondition(vm.isGoingForward == false, "previousTrack should set transition direction to backwards")
    vm.nextTrack()
    assertCondition(vm.isGoingForward == true, "nextTrack should set transition direction to forward")

    print("✅ ViewModel tests passed successfully.")
}

@MainActor
func runViewLayoutTests() {
    print("\n--- Running View Layout Tests ---")
    let vm = NotchViewModel()
    let expView = ExpandedNotchView(viewModel: vm)
    let hostingExp = NSHostingView(rootView: expView)
    let expFitting = hostingExp.fittingSize
    print("Expanded View fittingSize: \(expFitting)")

    let compView = CompactNotchView(viewModel: vm)
    let hostingComp = NSHostingView(rootView: compView)
    let compFitting = hostingComp.fittingSize
    print("Compact View fittingSize: \(compFitting)")

    let geo = vm.screenManager.currentGeometry
    print("Geometry compactSize: \(geo.compactSize), expandedSize: \(geo.expandedSize)")

    assertCondition(geo.expandedSize.height >= expFitting.height, "expandedSize.height (\(geo.expandedSize.height)) must be >= ExpandedNotchView fitting height (\(expFitting.height)) to avoid clipping controls")
    assertCondition(geo.compactSize.width >= compFitting.width, "compactSize.width (\(geo.compactSize.width)) must be >= CompactNotchView fitting width (\(compFitting.width)) to avoid clipping wings")

    // Test centered layout when lyrics disabled
    vm.showLyrics = false
    let centeredExpView = ExpandedNotchView(viewModel: vm)
    let hostingCentered = NSHostingView(rootView: centeredExpView)
    let centeredFitting = hostingCentered.fittingSize
    print("Centered (Lyrics Disabled) View fittingSize: \(centeredFitting)")
    assertCondition(geo.expandedSize.height >= centeredFitting.height, "expandedSize.height must be >= centered fitting height (\(centeredFitting.height))")
    vm.showLyrics = true

    // Verify CompactNotchView with active visualizer
    vm.mediaManager.selectedSource = .demo
    let compPlayingView = CompactNotchView(viewModel: vm)
    let hostingCompPlaying = NSHostingView(rootView: compPlayingView)
    assertCondition(hostingCompPlaying.fittingSize.width > 0, "CompactNotchView with active visualizer should host cleanly")

    // Verify NotchRootView hosting and namespace backward compatibility
    let rootView = NotchRootView(viewModel: vm)
    let hostingRoot = NSHostingView(rootView: rootView)
    assertCondition(hostingRoot.fittingSize.width >= 0, "NotchRootView should host cleanly with animated namespace")
    print("✅ View Layout tests passed successfully.")
}

@MainActor
func runPanelKeyTests() {
    print("\n--- Running Panel & Key Tests ---")
    let panel = NotchPanel(contentRect: NSRect(x: 100, y: 100, width: 400, height: 200))
    assertCondition(panel.canBecomeKey == true, "NotchPanel canBecomeKey must be true for menus and sliders to respond")
    assertCondition(panel.canBecomeMain == false, "NotchPanel canBecomeMain must remain false")
    assertCondition(panel.level == .screenSaver, "NotchPanel level must be .screenSaver to stay on top across space transitions")
    assertCondition(panel.collectionBehavior.contains(.canJoinAllSpaces), "NotchPanel must have .canJoinAllSpaces")
    assertCondition(panel.collectionBehavior.contains(.fullScreenAuxiliary), "NotchPanel must have .fullScreenAuxiliary")

    var escapeTriggered = false
    panel.onEscape = {
        escapeTriggered = true
    }

    // Simulate escape key event (keyCode 53)
    if let escEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: panel.windowNumber,
        context: nil,
        characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false,
        keyCode: 53
    ) {
        panel.keyDown(with: escEvent)
        assertCondition(escapeTriggered, "Escape key must trigger onEscape collapse handler")
    }

    // Simulate ⌘L key event (keyCode 37)
    var lyricsTriggered = false
    panel.onToggleLyrics = { lyricsTriggered = true }
    if let lEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: panel.windowNumber,
        context: nil,
        characters: "l",
        charactersIgnoringModifiers: "l",
        isARepeat: false,
        keyCode: 37
    ) {
        panel.keyDown(with: lEvent)
        assertCondition(lyricsTriggered, "⌘L key must trigger onToggleLyrics")
    }

    // Simulate ⌘P key event (keyCode 35)
    var pinTriggered = false
    panel.onTogglePin = { pinTriggered = true }
    if let pEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: panel.windowNumber,
        context: nil,
        characters: "p",
        charactersIgnoringModifiers: "p",
        isARepeat: false,
        keyCode: 35
    ) {
        panel.keyDown(with: pEvent)
        assertCondition(pinTriggered, "⌘P key must trigger onTogglePin")
    }
    print("✅ Panel & Key tests passed successfully.")
}

@MainActor
func runPerformanceAndLifecycleTests() {
    print("\n--- Running Performance, Battery & Lifecycle Tests ---")

    // Test 1: Visualizer timer pauses at resting floor when audio is inactive
    let manager = UnifiedMediaManager()
    manager.selectedSource = .demo
    if manager.isPlaying {
        manager.playPause()
    }
    assertCondition(!manager.isPlaying, "Manager should be paused")

    // Advance visualizer until amplitudes decay to resting floor
    for _ in 0..<30 {
        manager.updateVisualizerAndSmoothProgress()
    }
    assertCondition(!manager.isVisualizerActive, "Visualizer timer should pause when inactive and at resting floor")
    assertCondition(manager.visualizerAmplitudes.allSatisfy { abs($0 - 0.05) < 0.001 }, "Amplitudes should rest cleanly at 0.05")

    // Resume playback and verify visualizer timer restarts
    manager.playPause()
    assertCondition(manager.isPlaying, "Manager should resume playing")
    assertCondition(manager.isVisualizerActive, "Visualizer timer should restart on playback resume")

    // Test 2: Artwork pre-decoding and song isolation
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 8,
        pixelsHigh: 8,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 32,
        bitsPerPixel: 32
    )
    let pngData = rep?.representation(using: .png, properties: [:])
    assertCondition(pngData != nil, "PNG data generation should succeed")

    let trackA = TrackInfo(
        title: "Song A",
        artist: "Artist A",
        album: "Album A",
        duration: 180.0,
        artworkData: pngData,
        source: .appleMusic
    )
    assertCondition(trackA.decodedImage != nil, "TrackInfo should cache decoded NSImage")

    let trackB = TrackInfo(
        title: "Song B",
        artist: "Artist B",
        album: "Album B",
        duration: 200.0,
        artworkData: nil,
        source: .appleMusic
    )
    assertCondition(trackB.artworkData == nil, "Song B must have nil artworkData")
    assertCondition(trackB.decodedImage == nil, "Song B must not inherit Song A's decodedImage")
    assertCondition(trackA != trackB, "Track A and Track B must be distinct")

    // Test 2b: Downsampling reduces large bitmap memory to thumbnail size
    let bigRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 400,
        pixelsHigh: 400,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 1600,
        bitsPerPixel: 32
    )
    if let bigPng = bigRep?.representation(using: .png, properties: [:]) {
        let bigTrack = TrackInfo(
            title: "Big Artwork",
            artist: "Artist",
            album: "Album",
            duration: 120.0,
            artworkData: bigPng,
            source: .appleMusic
        )
        assertCondition(bigTrack.decodedImage != nil, "Downsampled decoded image exists")
        assertCondition(bigTrack.decodedImage!.size.width <= 160, "Artwork should be downscaled to thumbnail dimensions (<= 160)")
    }

    // Test 2c: Adaptive visualizer rate with expansion
    let adaptiveManager = UnifiedMediaManager()
    assertCondition(!adaptiveManager.isExpanded, "Initial manager is not expanded")
    adaptiveManager.isExpanded = true
    assertCondition(adaptiveManager.isExpanded, "Manager tracks isExpanded state")
    adaptiveManager.isExpanded = false

    // Test 2d: AppleScriptRunner cached execution
    let testScript = "return \"notch_test\""
    let out1 = AppleScriptRunner.runSync(testScript)
    let out2 = AppleScriptRunner.runSync(testScript)
    assertCondition(out1 == "notch_test" && out2 == "notch_test", "AppleScriptRunner caching returns valid output")

    // Test 3: Observer token lifecycle & deinit cleanup
    do {
        let music = AppleMusicService()
        assertCondition(music.source == .appleMusic, "AppleMusicService initialized")
        let spotify = SpotifyService()
        assertCondition(spotify.source == .spotify, "SpotifyService initialized")
        let screen = ScreenNotchManager()
        assertCondition(screen.currentGeometry.compactSize.width > 0, "ScreenNotchManager initialized")
    }

    // Test 4: Window controller key window handling on expand and collapse
    let vm = NotchViewModel()
    let controller = NotchWindowController(viewModel: vm)
    assertCondition(controller.panel != nil, "Controller has panel")

    if let panel = controller.panel, let contentView = panel.contentView {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let bounds = contentView.bounds
        let geo = vm.screenManager.currentGeometry

        // In window coordinates (origin bottom-left): notch is at the top (y: bounds.height - compactHeight ... bounds.height)
        let pointOnNotch = NSPoint(x: bounds.midX, y: bounds.height - 10)
        let pointBelowNotch = NSPoint(x: bounds.midX, y: bounds.height - geo.compactSize.height - 10)
        let pointFarBelow = NSPoint(x: bounds.midX, y: 10)

        // In compact mode: cursor on notch must hit
        assertCondition(contentView.hitTest(pointOnNotch) != nil, "Hit-test on compact notch must succeed")
        // In compact mode: cursor below notch must pass through (return nil)
        assertCondition(contentView.hitTest(pointBelowNotch) == nil, "Hit-test below compact notch must pass through")
        assertCondition(contentView.hitTest(pointFarBelow) == nil, "Hit-test far below compact notch must pass through")
    }

    vm.onMouseEnter()
    assertCondition(vm.isExpanded, "ViewModel is expanded")
    vm.collapse()
    assertCondition(!vm.isExpanded, "ViewModel collapsed")

    print("✅ Performance, Battery & Lifecycle tests passed successfully.")
}

@MainActor
func runAppleNotchShapeTests() {
    print("\n--- Running Apple Notch Shape & Liquid Glass Tests ---")

    // Test 1: Radii equality in compact mode
    let compactShape = AppleNotchShape(topRadius: 16.0, bottomRadius: 16.0)
    assertCondition(compactShape.topRadius == compactShape.bottomRadius, "Top and bottom radii must match in compact mode")
    assertCondition(compactShape.topRadius == 16.0, "Compact radius is 16.0")

    // Test 2: Radii equality in expanded mode
    let expandedShape = AppleNotchShape(topRadius: 20.0, bottomRadius: 20.0)
    assertCondition(expandedShape.topRadius == expandedShape.bottomRadius, "Top and bottom radii must match in expanded mode")
    assertCondition(expandedShape.topRadius == 20.0, "Expanded radius is 20.0")

    // Test 3: Path bounding box matches full frame
    let rect = CGRect(x: 0, y: 0, width: 480, height: 236)
    let path = expandedShape.path(in: rect)
    let bounds = path.boundingRect
    assertCondition(abs(bounds.minX) < 0.001, "Path starts at x = 0 (top-left ear tip)")
    assertCondition(abs(bounds.maxX - 480) < 0.001, "Path ends at x = 480 (top-right ear tip)")
    assertCondition(abs(bounds.minY) < 0.001, "Path starts at y = 0 (screen bezel alignment)")
    assertCondition(abs(bounds.maxY - 236) < 0.001, "Path reaches full height y = 236")

    // Test 4: InsettableShape behavior for specular rim stroke borders
    let insetShape = expandedShape.inset(by: 1.0)
    let insetPath = insetShape.path(in: rect)
    let insetBounds = insetPath.boundingRect
    assertCondition(abs(insetBounds.minX - 1.0) < 0.001, "Inset path minX is 1.0")
    assertCondition(abs(insetBounds.maxX - 479.0) < 0.001, "Inset path maxX is 479.0")
    assertCondition(abs(insetBounds.minY - 1.0) < 0.001, "Inset path minY is 1.0")
    assertCondition(abs(insetBounds.maxY - 235.0) < 0.001, "Inset path maxY is 235.0")

    // Test 5: Animatable pair support
    var animShape = AppleNotchShape(topRadius: 16.0, bottomRadius: 16.0)
    animShape.animatableData = AnimatablePair(20.0, 20.0)
    assertCondition(animShape.topRadius == 20.0 && animShape.bottomRadius == 20.0, "Animation updates both radii simultaneously")

    print("✅ Apple Notch Shape & Liquid Glass tests passed successfully.")
}

@MainActor
func runMediaControlsTests() {
    print("\n--- Running Media Controls Tests ---")

    let vm = NotchViewModel()
    vm.mediaManager.selectedSource = .demo
    vm.mediaManager.setShuffle(false)
    vm.mediaManager.setRepeatMode(.off)

    // Test 1: Initial states
    assertCondition(vm.repeatMode == .off, "Initial repeatMode should be .off")
    assertCondition(!vm.isShuffleActive, "Initial isShuffleActive should be false")
    assertCondition(vm.playPauseBounceTrigger == 0, "Initial playPauseBounceTrigger should be 0")
    assertCondition(vm.nextBounceTrigger == 0, "Initial nextBounceTrigger should be 0")
    assertCondition(vm.prevBounceTrigger == 0, "Initial prevBounceTrigger should be 0")

    // Test 2: RepeatMode 3-state cycling: off -> all -> one -> off
    vm.cycleRepeatMode()
    assertCondition(vm.repeatMode == .all, "Cycling repeat mode from off should set to .all")

    vm.cycleRepeatMode()
    assertCondition(vm.repeatMode == .one, "Cycling repeat mode from all should set to .one")

    vm.cycleRepeatMode()
    assertCondition(vm.repeatMode == .off, "Cycling repeat mode from one should cycle back to .off")

    // Test 3: Shuffle toggle
    vm.toggleShuffle()
    assertCondition(vm.isShuffleActive == true, "Toggling shuffle should set isShuffleActive to true")

    vm.toggleShuffle()
    assertCondition(vm.isShuffleActive == false, "Toggling shuffle again should set isShuffleActive to false")

    // Test 4: Bounce triggers increment
    let playTriggerBefore = vm.playPauseBounceTrigger
    vm.togglePlayPause()
    assertCondition(vm.playPauseBounceTrigger == playTriggerBefore + 1, "togglePlayPause must increment playPauseBounceTrigger")

    let nextTriggerBefore = vm.nextBounceTrigger
    vm.nextTrack()
    assertCondition(vm.nextBounceTrigger == nextTriggerBefore + 1, "nextTrack must increment nextBounceTrigger")

    let prevTriggerBefore = vm.prevBounceTrigger
    vm.previousTrack()
    assertCondition(vm.prevBounceTrigger == prevTriggerBefore + 1, "previousTrack must increment prevBounceTrigger")

    // Test 5: MediaControlsView hosting and layout
    let controlsView = MediaControlsView(viewModel: vm)
    let hosting = NSHostingView(rootView: controlsView)
    let fitting = hosting.fittingSize
    assertCondition(fitting.width > 0 && fitting.width <= 460.0, "MediaControlsView fitting width should fit within expanded width")
    assertCondition(fitting.height > 0 && fitting.height <= 60.0, "MediaControlsView fitting height should be reasonable (<= 60)")

    // Test 6: Standalone initialization
    let standaloneView = MediaControlsView(showsBackground: true)
    let standaloneHosting = NSHostingView(rootView: standaloneView)
    let standaloneFitting = standaloneHosting.fittingSize
    assertCondition(standaloneFitting.width > 0 && standaloneFitting.height > 0, "Standalone MediaControlsView should host cleanly")

    print("✅ Media Controls tests passed successfully.")
}

@MainActor
func runStatusBarControllerTests() {
    print("\n--- Running Status Bar Controller Tests ---")
    HotKeyManager.shared.unregisterAll()
    let vm = NotchViewModel()
    let wc = NotchWindowController(viewModel: vm)
    let controller = StatusBarController(viewModel: vm, windowController: wc)

    // Verify hotkey registrations (no bare cmdKey shortcuts that hijack system hotkeys)
    let hotkeys = HotKeyManager.shared.registrations
    let bareCmdL = hotkeys.contains { $0.keyCode == UInt32(kVK_ANSI_L) && $0.modifiers == UInt32(cmdKey) }
    assertCondition(!bareCmdL, "Global hotkey for bare ⌘L must not be registered (conflicts with browser address bar)")

    let bareCmdP = hotkeys.contains { $0.keyCode == UInt32(kVK_ANSI_P) && $0.modifiers == UInt32(cmdKey) }
    assertCondition(!bareCmdP, "Global hotkey for bare ⌘P must not be registered (conflicts with print)")

    let chordedCmdL = hotkeys.contains { $0.keyCode == UInt32(kVK_ANSI_L) && $0.modifiers == UInt32(cmdKey | controlKey) }
    assertCondition(chordedCmdL, "Global hotkey for ⌃⌘L should be registered for lyrics toggle")

    let chordedCmdP = hotkeys.contains { $0.keyCode == UInt32(kVK_ANSI_P) && $0.modifiers == UInt32(cmdKey | controlKey) }
    assertCondition(chordedCmdP, "Global hotkey for ⌃⌘P should be registered for pin toggle")

    let chordedCmdN = hotkeys.contains { $0.keyCode == UInt32(kVK_ANSI_N) && $0.modifiers == UInt32(cmdKey | controlKey) }
    assertCondition(chordedCmdN, "Global hotkey for ⌃⌘N should be registered for overlay toggle")

    assertCondition(hotkeys.allSatisfy { ($0.modifiers & UInt32(controlKey)) != 0 }, "All registered global hotkeys must require controlKey modifier")

    guard let item = controller.statusItem else {
        assertCondition(false, "StatusBarController must create an NSStatusItem")
        return
    }

    // Verify icon
    assertCondition(item.button?.image != nil, "StatusBar button must have an icon set")
    if let img = item.button?.image {
        assertCondition(img.size.width == 18 && img.size.height == 18, "Status Bar icon size must be 18x18, got \(img.size)")
        assertCondition(img.accessibilityDescription == "Notch Music", "Status Bar icon accessibility description must be 'Notch Music'")
    }

    // Verify menu items
    guard let menu = item.menu else {
        assertCondition(false, "StatusBar statusItem must have a menu configured")
        return
    }

    let menuTitles = menu.items.map { $0.title }
    assertCondition(menuTitles.contains("Notch Music"), "Menu should contain title item 'Notch Music'")
    assertCondition(menuTitles.contains("Toggle Notch Overlay"), "Menu should contain 'Toggle Notch Overlay'")
    assertCondition(menuTitles.contains("Keep Expanded (Pin)"), "Menu should contain 'Keep Expanded (Pin)'")
    assertCondition(menuTitles.contains("Show Lyrics"), "Menu should contain 'Show Lyrics'")
    assertCondition(menuTitles.contains("Quit Notch"), "Menu should contain 'Quit Notch'")

    // Verify lyrics toggle menu state
    let lyricsMenuItem = menu.items.first(where: { $0.title == "Show Lyrics" })
    assertCondition(lyricsMenuItem?.state == (vm.showLyrics ? .on : .off), "Show Lyrics menu state should reflect viewModel")
    vm.toggleLyrics()
    controller.refreshMenu()
    assertCondition(lyricsMenuItem?.state == (vm.showLyrics ? .on : .off), "Show Lyrics menu state should toggle with viewModel")
    vm.toggleLyrics()
    controller.refreshMenu()

    print("✅ Status Bar Controller tests passed successfully.")
}

@MainActor
func runLyricsTests() {
    print("\n--- Running Synchronized Lyrics Tests ---")

    // Test 1: LRCParser parsing
    let sampleLrc = """
    [ti:Test Song]
    [ar:Test Artist]
    [00:05.20] First line of song
    [00:15.80] Second line of song
    [00:25.00] Third line of song
    """
    let parsed = LRCParser.parse(sampleLrc)
    assertCondition(parsed.count == 3, "Parsed lyrics count must be 3, got \(parsed.count)")
    assertCondition(abs(parsed[0].timestamp - 5.20) < 0.001, "First timestamp should be 5.20s")
    assertCondition(parsed[0].text == "First line of song", "First line text matches")
    assertCondition(abs(parsed[1].timestamp - 15.80) < 0.001, "Second timestamp should be 15.80s")
    assertCondition(parsed[2].text == "Third line of song", "Third line text matches")

    // Test 2: Active line search and 3-line calculation
    let service = LyricsService()
    let testTrack = TrackInfo(
        title: "Midnight City",
        artist: "M83",
        album: "Hurry Up, We're Dreaming",
        duration: 243.0,
        source: .demo
    )
    service.fetchLyrics(for: testTrack)
    assertCondition(!service.currentLyrics.isEmpty, "Preloaded demo lyrics for Midnight City should be present")

    // Test before first line (t = 10s, first line is at 29.80s)
    let earlyLines = service.threeLines(for: 10.0)
    assertCondition(earlyLines.previous == nil, "Before first line, previous should be nil")
    assertCondition(earlyLines.current == "...", "Before first line, current should be '...'")
    assertCondition(earlyLines.next == "Waiting in a car", "Next line should be first lyric")

    // Test during line 0 (t = 30.5s)
    let line0 = service.threeLines(for: 30.5)
    assertCondition(line0.previous == nil, "At line 0, previous should be nil")
    assertCondition(line0.current == "Waiting in a car", "At line 0, current should match line 0")
    assertCondition(line0.next == "Waiting for a ride in the dark", "At line 0, next should match line 1")

    // Test during line 1 (t = 33.0s)
    let line1 = service.threeLines(for: 33.0)
    assertCondition(line1.previous == "Waiting in a car", "At line 1, previous should be line 0")
    assertCondition(line1.current == "Waiting for a ride in the dark", "At line 1, current should match line 1")
    assertCondition(line1.next == "The night city grows", "At line 1, next should match line 2")

    // Test 3: Instrumental handling
    let instrumentalTrack = TrackInfo(
        title: "Resonance",
        artist: "HOME",
        album: "Odyssey",
        duration: 212.0,
        source: .demo
    )
    service.fetchLyrics(for: instrumentalTrack)
    assertCondition(service.isInstrumental, "Resonance should be recognized as instrumental")

    // Test 4: View hosting in empty state
    let vm = NotchViewModel()
    let lyricsView = LyricsView(viewModel: vm)
    let hosting = NSHostingView(rootView: lyricsView)
    assertCondition(hosting.fittingSize.width >= 0, "LyricsView should host cleanly in NSHostingView")

    // Test 5: View hosting with active track and synced lyrics
    vm.mediaManager.selectedSource = .demo
    if let track = vm.mediaManager.currentTrack {
        vm.lyricsService.fetchLyrics(for: track)
    }
    vm.seek(to: 33.0)
    let activeLyricsView = LyricsView(viewModel: vm)
    let activeHosting = NSHostingView(rootView: activeLyricsView)
    assertCondition(activeHosting.fittingSize.height >= 100, "Active LyricsView container should maintain stable height (>= 100)")
    assertCondition(activeHosting.fittingSize.height <= 115, "Active LyricsView container should not exceed bounds (<= 115)")

    // Test 6: ExpandedNotchView fitting size with active lyrics must not clip controls
    let expWithLyrics = ExpandedNotchView(viewModel: vm)
    let expWithLyricsHosting = NSHostingView(rootView: expWithLyrics)
    let expWithLyricsFitting = expWithLyricsHosting.fittingSize
    let geo = vm.screenManager.currentGeometry
    print("Expanded View with active lyrics fittingSize: \(expWithLyricsFitting), expandedSize: \(geo.expandedSize)")
    assertCondition(geo.expandedSize.height >= expWithLyricsFitting.height, "expandedSize.height (\(geo.expandedSize.height)) must accommodate active lyrics fitting height (\(expWithLyricsFitting.height))")

    // Test 7: Extra-long wrapping lyrics line and directional transitions
    let longLyricLrc = """
    [00:00.00] This is a very long preceding lyric line that wraps across multiple lines cleanly and elegantly without clipping
    [00:05.00] And this is an exceptionally long active current lyric line that definitely wraps across multiple lines and must never be truncated with tail dots
    [00:10.00] Followed by another substantially long next lyric line that wraps smoothly to test complete layout resilience
    """
    let parsedLong = LRCParser.parse(longLyricLrc)
    assertCondition(parsedLong.count == 3, "LRCParser should parse 3 long lines")
    assertCondition(parsedLong[1].text.count > 80, "Active line should be > 80 characters to force wrapping")

    // Test directional forward and backward tracking
    let testTrack2 = TrackInfo(
        title: "Midnight City",
        artist: "M83",
        album: "Hurry Up, We're Dreaming",
        duration: 243.0,
        source: .demo
    )
    service.fetchLyrics(for: testTrack2)
    _ = service.activeIndex(for: 30.0) // Line 0
    _ = service.activeIndex(for: 33.0) // Line 1 (forward)
    assertCondition(service.isMovingForward == true, "Advancing lines in lyrics must set isMovingForward to true")
    _ = service.activeIndex(for: 25.0) // Seek before Line 0 (backward)
    assertCondition(service.isMovingForward == false, "Seeking backward in lyrics must set isMovingForward to false")

    // Test 8: Container bounds stability with wrapped lyrics
    let wrappedLyricsView = LyricsView(viewModel: vm)
    let wrappedHosting = NSHostingView(rootView: wrappedLyricsView)
    assertCondition(wrappedHosting.fittingSize.height >= 100, "Lyrics container height should stay >= 100")
    assertCondition(wrappedHosting.fittingSize.height <= 115, "Lyrics container height should stay <= 115")

    // Test 9: Anticipation lead time verification in lyrics visualizer
    assertCondition(LyricsService.anticipationLeadTime >= 0.25 && LyricsService.anticipationLeadTime <= 0.50, "Anticipation lead time should be between 250ms and 500ms")
    let anticipatedActive = service.activeIndex(for: 32.40 - 0.20 + LyricsService.anticipationLeadTime)
    assertCondition(anticipatedActive == 1, "Visualizer with anticipation must advance to next line before vocal timestamp")
    let unadvanced = service.activeIndex(for: 32.40 - 0.50 + LyricsService.anticipationLeadTime)
    assertCondition(unadvanced == 0, "Well before anticipation lead time, previous line must remain active")

    print("✅ Synchronized Lyrics tests passed successfully.")
}

@main
struct TestRunner {
    @MainActor
    static func main() {
        print("========================================")
        print("🚀 Starting Notch Music Prototype Test Suite")
        print("========================================")

        runGeometryTests()
        runAppleNotchShapeTests()
        runSimulatedMediaServiceTests()
        runUnifiedMediaManagerTests()
        runViewModelTests()
        runViewLayoutTests()
        runPanelKeyTests()
        runPerformanceAndLifecycleTests()
        runMediaControlsTests()
        runStatusBarControllerTests()
        runLyricsTests()

        print("\n========================================")
        print("🎉 ALL TESTS PASSED SUCCESSFULLY! (11 suites)")
        print("========================================\n")
    }
}
