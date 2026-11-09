# Test & Runner Infrastructure Investigation Report (R6 & Verification)

## 1. Observation

### 1.1 `Package.swift` Targets, Products, and Dependencies
Inspection of `/Users/fabio/Documents/Notch/Package.swift` (lines 1–31) directly confirms:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotchKit", targets: ["NotchKit"]),
        .executable(name: "Notch", targets: ["Notch"]),
        .executable(name: "NotchTestRunner", targets: ["NotchTestRunner"]),
    ],
    targets: [
        .target(
            name: "NotchKit",
            path: "Sources/NotchKit"
        ),
        .executableTarget(
            name: "Notch",
            dependencies: ["NotchKit"],
            path: "Sources/NotchApp"
        ),
        .executableTarget(
            name: "NotchTestRunner",
            dependencies: ["NotchKit"],
            path: "Sources/NotchTestRunner"
        ),
    ]
)
```
- **No `testTarget`**: The project does not utilize `XCTest` or `.testTarget`. Instead, tests are packaged into a standalone CLI `.executableTarget` named `NotchTestRunner`.
- **Target Dependencies**: `NotchTestRunner` depends exclusively on `NotchKit`. `NotchKit` contains all shared geometry, media services, view models, and views.
- **Platform**: `macOS (.v14)`. Swift tools version is `6.0`.

### 1.2 `Sources/NotchTestRunner/Main.swift` Architecture and Test Suite Inventory
Inspection of `/Users/fabio/Documents/Notch/Sources/NotchTestRunner/Main.swift` reveals:
- **Assertion and Failure Mechanism** (lines 9–18):
  ```swift
  struct TestFailure: Error {
      let message: String
  }

  func assertCondition(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
      if !condition {
          print("❌ FAILED: \(message) [\(file):\(line)]")
          exit(1)
      }
  }
  ```
  Failures immediately abort execution with exit code `1`, printing the verbatim failure message along with source file and line number.
- **Entry Point and Execution Flow** (lines 578–601):
  ```swift
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

          print("\n========================================")
          print("🎉 ALL TESTS PASSED SUCCESSFULLY! (10 suites)")
          print("========================================\n")
      }
  }
  ```
  Every suite function is decorated with `@MainActor` and called sequentially on the main actor thread.
- **Complete Inventory of 10 Test Suites Executed**:
  1. `runGeometryTests()` (lines 20–56): Screen frame calculations, physical notch positioning, compact/expanded frame sizing, and horizontal centering.
  2. `runAppleNotchShapeTests()` (lines 445–483): Top/bottom corner radii, shape path bounding box, insettable shape outlines, and animatable pair interpolation.
  3. `runSimulatedMediaServiceTests()` (lines 58–117): Track list sequencing, play/pause toggles, seeking clamping, track rewind rules, and volume/mute restoring.
  4. `runUnifiedMediaManagerTests()` (lines 119–214): Source routing (`.demo`), 12-band visualizer amplitude distribution, volume forwarding, auto-source selection, smooth progress progression, seeking without rubber-banding, and visualizer volume gating.
  5. `runViewModelTests()` (lines 216–274): Hover expansion, pin toggle, collapse suppression, volume/mute reactive bindings, and time formatting (`formatTime`, `formatRemainingTime`).
  6. `runViewLayoutTests()` (lines 276–307): `ExpandedNotchView`, `CompactNotchView`, and `NotchRootView` fitting sizes inside `NSHostingView`.
  7. `runPanelKeyTests()` (lines 309–341): `NotchPanel` level (`.screenSaver`), collection behaviors, key capability, and Escape key dismissal.
  8. `runPerformanceAndLifecycleTests()` (lines 343–443): Visualizer resting floor decay, artwork decoding and instance isolation, service observer deinit cleanup, and compact hit-test window coordinate passthrough.
  9. `runMediaControlsTests()` (lines 485–543): RepeatMode cycling, shuffle toggling, button bounce triggers, and `MediaControlsView` layout.
  10. `runStatusBarControllerTests()` (lines 544–576): Menu bar extra status item presence, 18x18 icon, and default menu actions.

### 1.3 `runMediaControlsTests()` and Background Spotify Leakage
In `Sources/NotchTestRunner/Main.swift` (lines 485–514):
```swift
@MainActor
func runMediaControlsTests() {
    print("\n--- Running Media Controls Tests ---")

    let vm = NotchViewModel()

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
...
```
Observations in `Sources/NotchKit/ViewModel/NotchViewModel.swift` (lines 26–27, 60–65, 149–168):
- `NotchViewModel.init` defaults to `mediaManager: UnifiedMediaManager = .shared`.
- Currently, `NotchViewModel` has stored in-memory properties:
  ```swift
  @Published public var isShuffleActive: Bool = false
  @Published public var repeatMode: RepeatMode = .off
  ```
  with shortcut comments: `// shortcut: local state only for shuffle/repeat, integrate with AppleScript services if bidirectional external sync needed`.
- In `Sources/NotchKit/Media/UnifiedMediaManager.swift` (lines 9, 58–78, 86–96):
  `selectedSource` defaults to `.auto`.
  In `.auto`, if Spotify is installed/running on the developer machine, `effectiveService` returns `spotifyService`.
  `startPollTimer()` polls `syncFromActiveService()` every 0.35 seconds.
- In `Sources/NotchKit/Media/SpotifyService.swift` (lines 28–32, 65–100):
  `init()` immediately invokes `refreshState()` querying Spotify via AppleScript.

### 1.4 `runUnifiedMediaManagerTests()` Current Coverage
Lines 120–214 of `Sources/NotchTestRunner/Main.swift` contain Tests 1–11:
- Test 1: Default source routing to `.demo`.
- Test 2: Visualizer amplitudes (12 frequency bands bounded in [0, 1]).
- Test 3: `manager.nextTrack()` updates track title.
- Test 4: `manager.setVolume(0.4)` updates manager and effective service volume.
- Test 5: Auto source fallback logic and Spotify preference when available.
- Test 6: Smooth monotonic progress advances position without backward jumps.
- Test 7: Stale external poll does not revert playback position.
- Test 8: Seeking updates position and prevents rubber-banding.
- Test 9: Visualizer amplitude floor (0.05) when muted vs unmuted.
- Test 10: Spotify service mute volume consistency (retaining pre-mute level).
- Test 11: Stable track identity based on title and artist hash.
**Zero tests** currently exist for `isShuffleActive`, `repeatMode`, `setShuffle`, `toggleShuffle`, `setRepeatMode`, `cycleRepeatMode`, or bidirectional sync from active service on `UnifiedMediaManager`.

### 1.5 Other Verification Mechanisms in Workspace
- `scripts/build_app.sh`: Releases and packages standalone signed bundle `Notch.app` via `swift build -c release`, generates `Info.plist`, copies `AppIcon.icns`, and signs with `codesign --force --deep --sign -`.
- Execution commands verified:
  - `swift build` (exited with code 0).
  - `swift run NotchTestRunner` (all 10 suites executed, exited with code 0).
- No other test runners, XCTest bundles, or test files exist in the repository.

---

## 2. Logic Chain

### 2.1 The Spotify State Leakage Mechanism
1. **Delegation requirement (R5)**: R5 replaces `vm.isShuffleActive` and `vm.repeatMode` with computed properties delegating to `vm.mediaManager.isShuffleActive` and `vm.mediaManager.repeatMode`.
2. **Singleton sharing**: In `runMediaControlsTests()`, `let vm = NotchViewModel()` uses default arguments `mediaManager: UnifiedMediaManager = .shared`.
3. **Default source selection**: In `UnifiedMediaManager`, `selectedSource` defaults to `.auto`.
4. **Service resolution**: When `selectedSource == .auto`, `effectiveService` resolves to `spotifyService` if Spotify is installed and running on the host Mac.
5. **AppleScript state poll (R2 & R4)**: In R2, `SpotifyService.refreshState()` queries `shuffling` and `repeating` from Spotify. In R4, `UnifiedMediaManager.syncFromActiveService()` copies these values into `manager.isShuffleActive` and `manager.repeatMode`.
6. **Assertion Failure in Test 1**: If the user's Spotify app was running in shuffle mode (`shuffling == true`) or repeat mode (`repeating == true`), `vm.isShuffleActive` evaluates to `true` or `vm.repeatMode` evaluates to `.all`/`.one`. Test 1 fails immediately on:
   `assertCondition(!vm.isShuffleActive, "Initial isShuffleActive should be false")` or
   `assertCondition(vm.repeatMode == .off, "Initial repeatMode should be .off")`.
7. **Cross-process mutation in Tests 2, 3, 4**: When `vm.cycleRepeatMode()`, `vm.toggleShuffle()`, `vm.togglePlayPause()`, `vm.nextTrack()`, and `vm.previousTrack()` are called, they forward to `spotifyService`. This fires live AppleScript commands across the OS into the user's Spotify app, modifying their personal playback during test execution, and causing race conditions because AppleScript execution is asynchronous.
8. **Isolation Solution**: Inserting `vm.mediaManager.selectedSource = .demo` immediately after `let vm = NotchViewModel()` switches `effectiveService` to `simulatedService` (`SimulatedMediaService`). `SimulatedMediaService` executes purely in-memory, without IPC, AppleScript, or network activity. Its initial state is deterministically `isShuffleActive == false` and `repeatMode == .off`, perfectly isolating `runMediaControlsTests()`.

### 2.2 Requirements for `runUnifiedMediaManagerTests()`
To satisfy R6 and ensure production reliability, `runUnifiedMediaManagerTests()` needs dedicated verification for:
1. Initial state when routed to `.demo` (`isShuffleActive == false`, `repeatMode == .off`).
2. Explicit setter forwarding (`setShuffle(true/false)`, `setRepeatMode(.off/.all/.one)`).
3. Toggle and cycling behavior (`toggleShuffle()`, `cycleRepeatMode()`).
4. Inward state synchronization (`syncFromActiveService()` copying service properties to manager).
5. Source switching propagation (switching between sources preserves or refreshes active state).

---

## 3. Caveats
- No caveats regarding test runner discovery: the complete test architecture is located in `Sources/NotchTestRunner/Main.swift`.
- Note on `UnifiedMediaManager.shared`: Because `NotchViewModel()` defaults to `.shared`, modifying `selectedSource` on `vm.mediaManager` in one test can theoretically mutate `.shared` for subsequent suites if not isolated or reset. Explicitly setting `selectedSource = .demo` in `runMediaControlsTests()` ensures hermetic execution regardless of suite order.
- In `SimulatedMediaService`, R3 specifies that `tick()` loops the track when `repeatMode == .one` and `playbackPosition >= track.duration`. Adding assertions for this behavior in `runSimulatedMediaServiceTests()` is recommended in addition to `runUnifiedMediaManagerTests()`.

---

## 4. Conclusion & Actionable Code Proposals

### 4.1 Changes Required in `Sources/NotchTestRunner/Main.swift`

#### A. Isolation in `runMediaControlsTests()`
Target: `Sources/NotchTestRunner/Main.swift`, lines 489–491.
```swift
// BEFORE:
@MainActor
func runMediaControlsTests() {
    print("\n--- Running Media Controls Tests ---")

    let vm = NotchViewModel()

    // Test 1: Initial states
    assertCondition(vm.repeatMode == .off, "Initial repeatMode should be .off")
    assertCondition(!vm.isShuffleActive, "Initial isShuffleActive should be false")

// AFTER:
@MainActor
func runMediaControlsTests() {
    print("\n--- Running Media Controls Tests ---")

    let vm = NotchViewModel()
    vm.mediaManager.selectedSource = .demo

    // Test 1: Initial states
    assertCondition(vm.repeatMode == .off, "Initial repeatMode should be .off")
    assertCondition(!vm.isShuffleActive, "Initial isShuffleActive should be false")
```

#### B. New Shuffle and Repeat Mode Test Scenarios in `runUnifiedMediaManagerTests()`
Target: `Sources/NotchTestRunner/Main.swift`, append after Test 11 (around line 212).
```swift
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
```

#### C. Recommended Companion Tests in `runSimulatedMediaServiceTests()`
In `Sources/NotchTestRunner/Main.swift` (inside `runSimulatedMediaServiceTests()`, after Test 9):
```swift
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

    // Test 11: RepeatMode.one looping in SimulatedMediaService tick()
    service.setRepeatMode(.one)
    let currentTitle = service.currentTrack?.title
    service.seek(to: (service.currentTrack?.duration ?? 100) - 0.05)
    // Trigger tick logic via seek past duration or simulated passage
    service.seek(to: service.currentTrack?.duration ?? 100)
    // Verify track does not skip to next track when repeatMode is .one
    assertCondition(service.currentTrack?.title == currentTitle, "Repeat one must keep current track active")
```

---

## 5. Verification Method

To independently verify the investigation findings and test suite execution:

1. **Build verification**:
   ```bash
   swift build
   ```
   *Expected output*: Exits with code 0 (`Build complete!`).

2. **Automated test suite execution**:
   ```bash
   swift run NotchTestRunner
   ```
   *Expected output*: Runs all 10 test suites in sequence, ending with:
   `🎉 ALL TESTS PASSED SUCCESSFULLY! (10 suites)` and exit code 0.

3. **Verify isolation in `runMediaControlsTests()`**:
   Inspect line 489 of `Sources/NotchTestRunner/Main.swift` using `view_file` to confirm `vm.mediaManager.selectedSource = .demo` is in place.
   *Invalidation condition*: If `vm.mediaManager.selectedSource` is left at `.auto`, and Spotify is playing or shuffling in the background, `assertCondition(!vm.isShuffleActive)` or `assertCondition(vm.repeatMode == .off)` will fail with exit code 1.

4. **Verify release build packaging**:
   ```bash
   ./scripts/build_app.sh
   ```
   *Expected output*: Generates `Notch.app` and reports `✅ Notch.app successfully built and signed at: .../Notch.app`.
