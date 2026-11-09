# Investigation Report: UI & State Synchronization for Shuffle and Repeat (R4 & R5)

## 1. Observation

### 1.1 `UnifiedMediaManager.swift` (`Sources/NotchKit/Media/UnifiedMediaManager.swift`)
- **Published Properties** (lines 15–22):
  ```swift
  @Published public private(set) var currentTrack: TrackInfo?
  @Published public private(set) var isPlaying: Bool = false
  @Published public private(set) var playbackPosition: TimeInterval = 0.0
  @Published public private(set) var volume: Double = 0.8
  @Published public private(set) var isMuted: Bool = false
  @Published public private(set) var visualizerAmplitudes: [CGFloat] = Array(repeating: 0.12, count: 12)
  @Published public private(set) var isGoingForward: Bool = true
  ```
  Neither `isShuffleActive` nor `repeatMode` is currently declared or published in `UnifiedMediaManager`.
- **Active Service Synchronization** (lines 115–157, `syncFromActiveService()`):
  ```swift
  let service = effectiveService
  ...
  self.isPlaying = service.isPlaying
  self.volume = service.volume
  self.isMuted = service.isMuted
  ```
  `syncFromActiveService()` does not currently sync `isShuffleActive` or `repeatMode`.
- **Service Switching** (lines 9–13):
  ```swift
  @Published public var selectedSource: MediaSource = .auto {
      didSet {
          updateActiveService()
      }
  }
  ```
  `updateActiveService()` invokes `syncFromActiveService()`.
- **Forwarder Controls**:
  Methods `playPause()`, `nextTrack()`, `previousTrack()`, `seek(to:)`, `setVolume(_:)`, and `setMuted(_:)` are implemented (lines 369–424), but no methods currently exist for `setShuffle(_:)`, `toggleShuffle()`, `setRepeatMode(_:)`, or `cycleRepeatMode()`.
- **Track Progression & Loop Behavior in Demo Mode** (lines 197–202 in `updateVisualizerAndSmoothProgress()`):
  ```swift
  if playbackPosition >= track.duration {
      if selectedSource == .demo {
          nextTrack()
      }
      return
  }
  ```
  When the simulated track finishes, it unconditionally calls `nextTrack()`, which will advance the track even if `repeatMode == .one`.

### 1.2 `NotchViewModel.swift` (`Sources/NotchKit/ViewModel/NotchViewModel.swift`)
*Note: The directory name is `ViewModel` (singular), located at `Sources/NotchKit/ViewModel/NotchViewModel.swift`.*
- **Stored State** (lines 26–27):
  ```swift
  @Published public var isShuffleActive: Bool = false
  @Published public var repeatMode: RepeatMode = .off
  ```
  Both properties are currently stored `@Published` variables isolated to `NotchViewModel`.
- **Combine Pipeline** (lines 74–79 in `init`):
  ```swift
  mediaManager.objectWillChange
      .sink { [weak self] _ in
          guard let self = self else { return }
          self.objectWillChange.send()
      }
      .store(in: &cancellables)
  ```
  `mediaManager.objectWillChange` is already hooked up to fire `NotchViewModel.objectWillChange.send()`.
- **Shuffle & Repeat Handlers** (lines 149–168):
  ```swift
  public func toggleShuffle() {
      // shortcut: local state only for shuffle/repeat, integrate with AppleScript services if bidirectional external sync needed
      withAnimation(.easeInOut(duration: 0.2)) {
          self.isShuffleActive.toggle()
      }
  }

  public func cycleRepeatMode() {
      // shortcut: local state only for shuffle/repeat, integrate with AppleScript services if bidirectional external sync needed
      withAnimation(.easeInOut(duration: 0.2)) {
          switch self.repeatMode {
          case .off:
              self.repeatMode = .all
          case .all:
              self.repeatMode = .one
          case .one:
              self.repeatMode = .off
          }
      }
  }
  ```
  Both methods mutate local state only and contain an explicit shortcut comment indicating the need for integration.
- **Hover Entry Handler** (lines 82–89):
  ```swift
  public func onMouseEnter() {
      guard !isHoverSuppressed else { return }
      exitDebounceTimer?.invalidate()
      exitDebounceTimer = nil
      withAnimation(.spring(response: 0.42, dampingFraction: 0.80, blendDuration: 0.0)) {
          self.isHovered = true
      }
  }
  ```
  `onMouseEnter()` does not call `mediaManager.effectiveService.refreshState()`.

### 1.3 `MediaControlsView.swift` (`Sources/NotchKit/Views/MediaControlsView.swift`)
- **`RepeatMode` Definition** (lines 4–8):
  ```swift
  public enum RepeatMode: String, CaseIterable, Sendable {
      case off
      case all
      case one
  }
  ```
- **Property Bindings** (lines 23–29):
  ```swift
  private var isShuffleActive: Bool {
      viewModel.isShuffleActive
  }

  private var repeatMode: RepeatMode {
      viewModel.repeatMode
  }
  ```
- **Shuffle Button** (lines 35–42):
  - Action: `viewModel.toggleShuffle()`
  - Icon: `"shuffle"`
  - Tint: `isShuffleActive ? Color.green : Color.white`
- **Repeat Button** (lines 76–84):
  - Action: `viewModel.cycleRepeatMode()`
  - Icon: `repeatMode == .one ? "repeat.1" : "repeat"`
  - Tint: `repeatMode == .off ? Color.white : Color.green`
  - Symbol Effect: `.contentTransition(.symbolEffect(.replace))`

### 1.4 Repo-Wide References to `RepeatMode`, `isShuffleActive`, `repeatMode`
A comprehensive `grep_search` across the repository identified occurrences in exactly three files:
1. `Sources/NotchKit/Views/MediaControlsView.swift`: Enum declaration (line 4) and view bindings/styling (lines 24, 28, 39, 79, 80, 83).
2. `Sources/NotchKit/ViewModel/NotchViewModel.swift`: Stored properties (lines 26–27) and toggling logic (lines 149–168).
3. `Sources/NotchTestRunner/Main.swift`: Unit test assertions in `runMediaControlsTests()` (lines 492–513):
   - Initial states: `assertCondition(vm.repeatMode == .off)` and `assertCondition(!vm.isShuffleActive)`
   - Cycling: `vm.cycleRepeatMode()` checking `.all`, `.one`, `.off`
   - Toggling: `vm.toggleShuffle()` checking `true`, `false`

### 1.5 Baseline Execution
`swift run NotchTestRunner` executes cleanly with all 10 existing test suites passing.

---

## 2. Logic Chain

1. **State Ownership & Combine Pipeline**:
   - By Observation 1.2, `NotchViewModel` relays all changes from `mediaManager.objectWillChange` to its own `objectWillChange`.
   - By declaring `@Published public private(set) var isShuffleActive: Bool = false` and `@Published public private(set) var repeatMode: RepeatMode = .off` in `UnifiedMediaManager`, any change to `mediaManager.isShuffleActive` or `mediaManager.repeatMode` automatically emits on `mediaManager.objectWillChange`.
   - Consequently, when `NotchViewModel.isShuffleActive` and `NotchViewModel.repeatMode` are converted from stored `@Published` properties to computed properties referencing `mediaManager.isShuffleActive` and `mediaManager.repeatMode`, all SwiftUI views observing `NotchViewModel` (including `MediaControlsView`) will automatically re-render without requiring redundant `@Published` wrappers on `NotchViewModel`.

2. **Bidirectional Synchronization in `UnifiedMediaManager`**:
   - By Observation 1.1, `syncFromActiveService()` copies properties from `effectiveService`.
   - Incorporating `self.isShuffleActive = service.isShuffleActive` and `self.repeatMode = service.repeatMode` into `syncFromActiveService()` ensures that:
     a) Periodic polling (every 0.35s via `pollTimer`) synchronizes external AppleScript changes (e.g. user toggles shuffle/repeat inside Spotify or Apple Music desktop app).
     b) Manual service switching (`selectedSource` didSet -> `updateActiveService()`) immediately reflects the target service's current state.
   - For forwarder methods (`setShuffle`, `toggleShuffle`, `setRepeatMode`, `cycleRepeatMode`), invoking `effectiveService.<method>()` updates the service, and updating `self.isShuffleActive = effectiveService.isShuffleActive` (and `repeatMode`) immediately publishes the new state to the UI without waiting for the next 0.35s polling tick.

3. **Smooth Progression vs Track Looping in Demo Mode**:
   - By Observation 1.1, in `UnifiedMediaManager.updateVisualizerAndSmoothProgress()`, when `playbackPosition >= track.duration`, if `selectedSource == .demo`, `nextTrack()` is called.
   - If `repeatMode == .one`, advancing to `nextTrack()` breaks the single-track repeat semantics for demo playback.
   - Guarding this check with `if repeatMode == .one { seek(to: 0.0) } else { nextTrack() }` harmonizes `UnifiedMediaManager` with `SimulatedMediaService.tick()`.

4. **ViewModel Delegation & User Hover Trigger**:
   - By Observation 1.2, `NotchViewModel.toggleShuffle()` and `cycleRepeatMode()` currently contain local state shortcut logic. Forwarding these calls to `mediaManager.toggleShuffle()` and `mediaManager.cycleRepeatMode()` aligns with R5.
   - By Observation 1.2, calling `mediaManager.effectiveService.refreshState()` in `NotchViewModel.onMouseEnter()` triggers an immediate out-of-band state fetch via AppleScript whenever the user moves their cursor over the notch. Because `refreshState()` executes AppleScript asynchronously in background queues in both `SpotifyService` and `AppleMusicService`, this does not block the UI or hitch the expand animation, ensuring the notch displays fresh status on expansion.

5. **Type Relocation Impact**:
   - By Observation 1.3, `RepeatMode` is currently declared in `MediaControlsView.swift`.
   - Moving `public enum RepeatMode: String, CaseIterable, Sendable { case off, all, one }` to `Sources/NotchKit/Media/MediaServiceProtocol.swift` makes `RepeatMode` accessible across all media services, `UnifiedMediaManager`, `NotchViewModel`, and views in the `NotchKit` module without requiring cross-module imports.
   - Existing code in `MediaControlsView.swift` and `NotchTestRunner/Main.swift` will continue to compile unchanged.

---

## 3. Caveats

1. **Test Suite Isolation (R6 Dependency)**:
   - In `Sources/NotchTestRunner/Main.swift`, `runMediaControlsTests()` currently creates `let vm = NotchViewModel()`.
   - By default, `NotchViewModel` uses `selectedSource = .auto`. If Spotify or Apple Music is running in the background on the machine running tests, `vm.repeatMode` and `vm.isShuffleActive` would reflect the real background player instead of `.off` and `false`.
   - As noted in R6, setting `vm.mediaManager.selectedSource = .demo` at the start of `runMediaControlsTests()` is essential to ensure tests remain isolated from local background application states.
2. **AppleScript Rubber-Banding Debounce Window**:
   - When the user clicks Shuffle or Repeat, `SpotifyService` and `AppleMusicService` fire asynchronous AppleScript commands.
   - `UnifiedMediaManager`'s 0.35s polling loop could theoretically overwrite the optimistic state if AppleScript returns older cached state before the command finishes. R2's 1.0s `lastUserInteractionTime` debounce guard in `SpotifyService` handles this suppression at the service layer.
3. **Computed Property Setters in `NotchViewModel`**:
   - `NotchViewModel.isShuffleActive` and `repeatMode` can either be read-only computed properties or provide setters that delegate to `mediaManager.setShuffle(newValue)` / `mediaManager.setRepeatMode(newValue)`. Providing getters and setters is recommended to support direct two-way bindings if ever used in SwiftUI controls or previews.

---

## 4. Conclusion

The implementation path for R4 and R5 is clear, cohesive, and isolated:

### Proposed Changes for R4 (`Sources/NotchKit/Media/UnifiedMediaManager.swift`)
1. **Properties**: Add:
   ```swift
   @Published public private(set) var isShuffleActive: Bool = false
   @Published public private(set) var repeatMode: RepeatMode = .off
   ```
2. **`syncFromActiveService()`**: Add:
   ```swift
   self.isShuffleActive = service.isShuffleActive
   self.repeatMode = service.repeatMode
   ```
3. **Forwarders**: Add:
   ```swift
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
   ```
4. **Demo Repeat One Looping**: In `updateVisualizerAndSmoothProgress()`, replace `if selectedSource == .demo { nextTrack() }` with:
   ```swift
   if selectedSource == .demo {
       if repeatMode == .one {
           seek(to: 0.0)
       } else {
           nextTrack()
       }
   }
   ```

### Proposed Changes for R5 (`Sources/NotchKit/ViewModel/NotchViewModel.swift`)
1. **Replace Stored Properties** (lines 26–27):
   ```swift
   public var isShuffleActive: Bool {
       get { mediaManager.isShuffleActive }
       set { mediaManager.setShuffle(newValue) }
   }

   public var repeatMode: RepeatMode {
       get { mediaManager.repeatMode }
       set { mediaManager.setRepeatMode(newValue) }
   }
   ```
2. **Update `toggleShuffle()` and `cycleRepeatMode()`** (lines 149–168):
   ```swift
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
   ```
3. **Update `onMouseEnter()`** (lines 82–89):
   ```swift
   public func onMouseEnter() {
       guard !isHoverSuppressed else { return }
       exitDebounceTimer?.invalidate()
       exitDebounceTimer = nil
       mediaManager.effectiveService.refreshState()
       withAnimation(.spring(response: 0.42, dampingFraction: 0.80, blendDuration: 0.0)) {
           self.isHovered = true
       }
   }
   ```

### Proposed Changes for `MediaControlsView.swift`
- Remove lines 3–8 (`public enum RepeatMode ...`), which moves to `MediaServiceProtocol.swift`. No other changes needed in `MediaControlsView.swift`.

---

## 5. Verification Method

1. **Build Verification**:
   ```bash
   swift build
   ```
   Expect zero compiler errors or warnings regarding `RepeatMode`, `isShuffleActive`, or `repeatMode`.
2. **Unit Test Verification**:
   ```bash
   swift run NotchTestRunner
   ```
   Verify that all 10 suites pass, including `runUnifiedMediaManagerTests()`, `runViewModelTests()`, and `runMediaControlsTests()`.
3. **Manual / State Propagation Inspection**:
   - Set `vm.mediaManager.selectedSource = .demo`.
   - Call `vm.toggleShuffle()`; verify `vm.isShuffleActive == true` and `vm.mediaManager.isShuffleActive == true`.
   - Call `vm.cycleRepeatMode()`; verify `vm.repeatMode == .all` and `vm.mediaManager.repeatMode == .all`.
   - Call `vm.cycleRepeatMode()`; verify `vm.repeatMode == .one`.
   - Call `vm.cycleRepeatMode()`; verify `vm.repeatMode == .off`.
4. **Invalidation Conditions**:
   - If `NotchViewModel.objectWillChange` fails to trigger view updates when `mediaManager` updates `isShuffleActive` or `repeatMode`. (Invalidated if `mediaManager.objectWillChange` sink is disconnected in `init`).
   - If tests fail when Spotify is running in the background. (Invalidated if `vm.mediaManager.selectedSource = .demo` is omitted in `runMediaControlsTests()`).
