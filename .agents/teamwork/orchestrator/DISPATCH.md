## 2026-11-06T22:54:15Z
Synchronize shuffle and loop/repeat statuses bidirectionally between the Notch app and Spotify/Apple Music for production use as specified in the approved implementation plan.

Working directory: /Users/fabio/Documents/Notch
Integrity mode: development

## Requirements

### R1. RepeatMode and MediaServiceProtocol Extension
Move `public enum RepeatMode: String, CaseIterable, Sendable { case off, all, one }` from `Sources/NotchKit/Views/MediaControlsView.swift` to `Sources/NotchKit/Media/MediaServiceProtocol.swift`. Extend `MediaServiceProtocol` with:
- `isShuffleActive: Bool { get }`
- `repeatMode: RepeatMode { get }`
- `func setShuffle(_ active: Bool)`
- `func setRepeatMode(_ mode: RepeatMode)`
- `func toggleShuffle()`
- `func cycleRepeatMode()`
Provide default implementations in a `MediaServiceProtocol` extension for `toggleShuffle()` calling `setShuffle(!isShuffleActive)` and `cycleRepeatMode()` cycling `.off` -> `.all` -> `.one` -> `.off`.

### R2. Bidirectional Spotify Synchronization & Debouncing
In `SpotifyService.swift`:
- Add `isShuffleActive: Bool`, `repeatMode: RepeatMode`, and `private var lastUserInteractionTime: CFTimeInterval = 0.0`.
- In `refreshState()`: query `shuffling` and `repeating` in AppleScript before player state checks, returning them with delimiter `|||` for both active and stopped states.
- In the main thread response handler: ignore incoming updates for 1.0 second after user interaction (`CACurrentMediaTime() - lastUserInteractionTime > 1.0`) to avoid AppleScript rubber-banding. Update `isShuffleActive` and map Spotify's boolean repeat state to `RepeatMode` (`false` -> `.off`, `true` -> `.all` if currently `.off`, keeping `.one` if already set).
- Implement `setShuffle(_ active: Bool)` and `setRepeatMode(_ mode: RepeatMode)` to update local state, record `lastUserInteractionTime = CACurrentMediaTime()`, and fire AppleScript asynchronously (`set shuffling to ...`, `set repeating to ...`).

### R3. AppleMusicService and SimulatedMediaService Conformance
- In `AppleMusicService.swift`: query `shuffle enabled` and `song repeat as string` (mapping 1:1 to `"off"`, `"all"`, `"one"`). Implement `setShuffle` and `setRepeatMode`.
- In `SimulatedMediaService.swift`: store `isShuffleActive` and `repeatMode`. In `tick()`, loop track when `repeatMode == .one` and `playbackPosition >= track.duration`.

### R4. UnifiedMediaManager State Propagation
In `UnifiedMediaManager.swift`:
- Expose `@Published public private(set) var isShuffleActive: Bool = false` and `@Published public private(set) var repeatMode: RepeatMode = .off`.
- In `syncFromActiveService()`: copy `isShuffleActive` and `repeatMode` from `service`.
- Implement forwarder controls `setShuffle`, `toggleShuffle`, `setRepeatMode`, and `cycleRepeatMode` updating published properties.

### R5. NotchViewModel Integration
In `NotchViewModel.swift`:
- Replace stored `@Published` properties `isShuffleActive` and `repeatMode` with computed properties delegating to `mediaManager`.
- Forward `toggleShuffle()` and `cycleRepeatMode()` to `mediaManager`.
- In `onMouseEnter()`: call `mediaManager.effectiveService.refreshState()`.

### R6. Test Suite Isolation and Unit Tests
In `Sources/NotchTestRunner/Main.swift`:
- In `runMediaControlsTests()`: isolate the test by setting `vm.mediaManager.selectedSource = .demo` upon initialization so live background Spotify state does not pollute assertions.
- Add tests in `runUnifiedMediaManagerTests()` verifying shuffle/repeat controls and state propagation.

## Verification Resources
- Build command: `swift build`
- Test runner: `swift run NotchTestRunner`

## Acceptance Criteria

### Protocol and Types
- [ ] `RepeatMode` is defined in `Sources/NotchKit/Media/MediaServiceProtocol.swift` and no longer defined in `Sources/NotchKit/Views/MediaControlsView.swift`.
- [ ] `MediaServiceProtocol` declares `isShuffleActive`, `repeatMode`, `setShuffle`, `setRepeatMode`, `toggleShuffle`, and `cycleRepeatMode`.
- [ ] Default extension methods for `toggleShuffle()` and `cycleRepeatMode()` are implemented on `MediaServiceProtocol`.

### Service Implementations
- [ ] `SpotifyService` queries `shuffling` and `repeating` in AppleScript during `refreshState()` and suppresses incoming updates within 1.0s of user interaction (`CACurrentMediaTime() - lastUserInteractionTime > 1.0`).
- [ ] `SpotifyService.setShuffle` and `SpotifyService.setRepeatMode` update local state, record interaction timestamp, and execute AppleScript commands asynchronously.
- [ ] `AppleMusicService` queries and sets `shuffle enabled` and `song repeat as string`.
- [ ] `SimulatedMediaService` maintains `isShuffleActive` and `repeatMode`, and loops track when `repeatMode == .one` and playback position reaches duration.

### State Propagation & ViewModel
- [ ] `UnifiedMediaManager` publishes `isShuffleActive` and `repeatMode` synced from the active service and provides forwarding controls.
- [ ] `NotchViewModel` computed properties delegate `isShuffleActive` and `repeatMode` to `mediaManager`.
- [ ] `NotchViewModel.onMouseEnter()` invokes `mediaManager.effectiveService.refreshState()`.

### Build & Tests
- [ ] `runMediaControlsTests()` initializes `vm.mediaManager.selectedSource = .demo` to isolate against live player state.
- [ ] `runUnifiedMediaManagerTests()` contains tests verifying shuffle and repeat mode control and propagation.
- [ ] `swift build` succeeds with zero errors.
- [ ] `swift run NotchTestRunner` succeeds with all test assertions passing.
