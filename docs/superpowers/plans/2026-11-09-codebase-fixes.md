# Notch Codebase Optimization and Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix system keyboard shortcut hijacking, multi-display notch positioning bugs, collapsed playback desync, lyrics race conditions, artwork memory bloat, and redundant 60fps CPU churn in the Notch music controller.

**Architecture:** Maintain the native Swift/SwiftUI architecture (AppKit borderless overlay panel with reactive NotchViewModel, UnifiedMediaManager, and platform services). Fix root causes directly at the owning boundaries with minimal surgical changes and zero added dependencies.

**Tech Stack:** macOS 14+, Swift 6.0, AppKit, SwiftUI, Carbon, Combine.

**Spec:** Ponytail Quality & Vulnerability Audit Findings #1-#14.

## Global Constraints
- Target platform: macOS 14.0+ (Swift 6.0 toolchain).
- Zero new third-party dependencies.
- All existing 11 test suites in `NotchTestRunner` must pass without regressions.
- Non-breaking changes to public library contracts (`NotchKit`).

## Review Focus
- Multi-monitor setups where the primary display has no notch and the secondary display has a hardware notch.
- Background process running while user types in other applications (no intercepted `⌘L` / `⌘P`).
- Rapid track switching while fetching lyrics over slow network connections (no stale lyrics overwrite).
- Memory footprint after playing multiple high-resolution album tracks (downsampled thumbnails only).
- Background battery impact when notch is collapsed vs expanded.

---

### Task 1: Fix System-Wide Hotkey Hijacking in StatusBarController

**Files:**
- Modify: `Sources/NotchKit/App/StatusBarController.swift:20-43`
- Test: `Sources/NotchTestRunner/Main.swift:713-755`

**Interfaces:**
- Consumes: `HotKeyManager.shared.register(keyCode:modifiers:action:)`
- Produces: Chorded global hotkeys (`⌃⌘L`, `⌃⌘P`, `⌃⌘N`) without intercepting system `⌘L` (browser address bar) or `⌘P` (print).

- [ ] **Step 1: Write test verifying global hotkey registration does not register bare `cmdKey`**
Update `runStatusBarControllerTests()` in `Sources/NotchTestRunner/Main.swift` to assert that bare `⌘L` and `⌘P` are not registered as system-wide hotkeys.

- [ ] **Step 2: Run test runner to observe current status**
Run: `swift run NotchTestRunner`

- [ ] **Step 3: Remove bare `cmdKey` global hotkey registrations in `StatusBarController.swift`**
In `Sources/NotchKit/App/StatusBarController.swift`, remove the registrations for `keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey)` and `keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey)`. Retain the composite chorded shortcuts `cmdKey | controlKey` (`⌃⌘L`, `⌃⌘P`, `⌃⌘N`). Local shortcuts when focused remain handled by `NotchPanel.keyDown`.

- [ ] **Step 4: Run test runner to verify it passes**
Run: `swift run NotchTestRunner`

---

### Task 2: Fix Multi-Display Notch Coordinate Calculation

**Files:**
- Modify: `Sources/NotchKit/Geometry/ScreenNotchManager.swift:110-125`
- Test: `Sources/NotchTestRunner/Main.swift:21-56`

**Interfaces:**
- Consumes: `NSScreen.screens`, `targetScreen.auxiliaryTopLeftArea`, `targetScreen.frame`
- Produces: `NotchGeometry` with `notchRect` properly positioned in global screen coordinate space.

- [ ] **Step 1: Write failing regression test for multi-display offset in `runGeometryTests`**
In `Sources/NotchTestRunner/Main.swift`, add a test case where `screenFrame` has a non-zero origin (e.g. `x: 1920, y: 0`) and verify that `notchRect.origin.x` aligns with the screen offset (`1920 + leftArea.maxX`).

- [ ] **Step 2: Run test runner to verify it fails**
Run: `swift run NotchTestRunner`

- [ ] **Step 3: Fix `notchRect` coordinate calculation in `ScreenNotchManager.swift`**
In `ScreenNotchManager.swift`, update:
```swift
let notchLeft = targetScreen.frame.origin.x + leftArea.maxX
let notchRight = targetScreen.frame.origin.x + rightArea.minX
```

- [ ] **Step 4: Run test runner to verify it passes**
Run: `swift run NotchTestRunner`

---

### Task 3: Fix Collapsed Playback Progress Stalling

**Files:**
- Modify: `Sources/NotchKit/Media/UnifiedMediaManager.swift:203-230`
- Test: `Sources/NotchTestRunner/Main.swift:172-185`

**Interfaces:**
- Consumes: `CACurrentMediaTime()`, `isExpanded`, `lastVisualizerTick`
- Produces: Accurately incremented `playbackPosition` both when expanded (60fps) and collapsed (1Hz).

- [ ] **Step 1: Write test verifying playback advances by full elapsed time when tick interval is 1.0s**
In `runUnifiedMediaManagerTests()`, simulate an elapsed interval of 1.0s and verify `playbackPosition` advances by 1.0s rather than being truncated to 0.016s.

- [ ] **Step 2: Run test to observe failure**
Run: `swift run NotchTestRunner`

- [ ] **Step 3: Correct the `dt` calculation in `UnifiedMediaManager.swift`**
Allow `dt` to match `elapsed` up to a reasonable cap (e.g. 1.25s) when collapsed, rather than falling back to 0.016s whenever `elapsed >= 0.25`:
```swift
let dt: TimeInterval
if lastVisualizerTick > 0 {
    let elapsed = now - lastVisualizerTick
    dt = (elapsed > 0.0001 && elapsed <= 1.25) ? elapsed : (isExpanded ? 0.016 : 1.0)
} else {
    dt = isExpanded ? 0.016 : 1.0
}
```

- [ ] **Step 4: Run test runner to verify it passes**
Run: `swift run NotchTestRunner`

---

### Task 4: Fix Lyrics Race Condition and Bound Cache

**Files:**
- Modify: `Sources/NotchKit/Lyrics/LyricsService.swift:20-80`
- Test: `Sources/NotchTestRunner/Main.swift:758-881`

**Interfaces:**
- Consumes: `TrackInfo`, `URLSession`
- Produces: Thread-safe, race-free `currentLyrics` and a bounded memory cache (max 50 tracks).

- [ ] **Step 1: Write test simulating rapid track switching during lyric fetches**
In `runLyricsTests()`, add a test where a fetch is launched for Track A, followed immediately by Track B; assert that when Track A's task finishes, it does not overwrite Track B's lyrics.

- [ ] **Step 2: Run test runner to verify failure**
Run: `swift run NotchTestRunner`

- [ ] **Step 3: Update `LyricsService.swift` with cancellation on cache hits and identity check**
In `fetchLyrics(for:)`:
- Cancel `activeFetchTask` before returning on cache hits.
- In `activeFetchTask`, check `guard !Task.isCancelled, self.currentTrackKey == key else { return }`.
- Bound `cache` to 50 entries using simple eviction when full.

- [ ] **Step 4: Run test runner to verify it passes**
Run: `swift run NotchTestRunner`

---

### Task 5: Eliminate Artwork Memory Bloat and Stabilize AppleScript Caching

**Files:**
- Modify: `Sources/NotchKit/Media/AppleMusicService.swift:233-288`
- Test: `Sources/NotchTestRunner/Main.swift:520-557`

**Interfaces:**
- Consumes: `AppleScriptRunner.runSync`, `TrackInfo.downsampledImage`
- Produces: Memory-efficient thumbnails (<= 160px) and static AppleScript cache keys.

- [ ] **Step 1: Write test verifying Apple Music artwork is downsampled and does not store uncompressed full-res image**
Add assertion in `Main.swift` verifying `AppleMusicService` produces thumbnail-sized decoded images.

- [ ] **Step 2: Update artwork export in `AppleMusicService.swift`**
- Use a stable temporary file path `notch_artwork_cache.jpg` so the AppleScript string is constant and cached in `AppleScriptRunner.scriptCache`.
- When instantiating `TrackInfo`, pass `artworkData: data` and `decodedImage: nil`, letting `TrackInfo` downsample to 160px.

- [ ] **Step 3: Run test runner to verify it passes**
Run: `swift run NotchTestRunner`

---

### Task 6: Clean Up Double Mute Invocation, Uncompiled Regex, and Font Resolution

**Files:**
- Modify: `Sources/NotchKit/ViewModel/NotchViewModel.swift:156-159`
- Modify: `Sources/NotchKit/Lyrics/LRCParser.swift:10`
- Modify: `Sources/NotchKit/Views/AppleMusicSlider.swift:47-52`
- Modify: `Sources/NotchKit/Views/MediaControlsView.swift:7,51,79`
- Modify: `Sources/NotchKit/Views/ScrubberBarView.swift:44`
- Modify: `Sources/NotchKit/Views/AudioVisualizerSymbolView.swift:13,18`

**Interfaces:**
- Consumes: Standard SwiftUI fonts, static NSRegularExpression
- Produces: Robust, clean UI code without duplicate event dispatch or font lookup fallbacks.

- [ ] **Step 1: Update `NotchViewModel.swift`**
Remove duplicate `mediaManager.setMuted(self.isMuted)` in `toggleMute()`.

- [ ] **Step 2: Update `LRCParser.swift`**
Change `tagRegex` to `private static let tagRegex = try? NSRegularExpression(...)`.

- [ ] **Step 3: Update `AppleMusicSlider.swift`**
Ensure `onEditingChanged(true)` is only sent once when the drag begins, not on every drag update.

- [ ] **Step 4: Update font definitions in Views**
Replace `.font(.custom("SFProDisplay-Semibold", size: N))` with `.font(.system(size: N, weight: .semibold, design: .default))` in `MediaControlsView`, `ScrubberBarView`, and `AudioVisualizerSymbolView`.

- [ ] **Step 5: Run test runner to verify all tests pass**
Run: `swift run NotchTestRunner`

---

### Task 7: Optimize Battery & CPU (Unrendered 60 FPS Visualizer Simulation)

**Files:**
- Modify: `Sources/NotchKit/Media/UnifiedMediaManager.swift:202-368`
- Test: `Sources/NotchTestRunner/Main.swift:142-152,471-493`

**Interfaces:**
- Consumes: `isPlaying`, `isExpanded`
- Produces: Smooth progress updates without triggering 60 Hz SwiftUI view re-renders for unused amplitude data.

- [ ] **Step 1: Review visualizer amplitudes usage**
Keep amplitudes updated only when visualizer is rendered or needed by tests, and avoid re-publishing identical or unused amplitudes when nothing observes them.

- [ ] **Step 2: Run test runner to confirm performance test suite passes**
Run: `swift run NotchTestRunner`

---

### Task 8: Full Verification and Standalone Build

**Files:**
- Build: `scripts/build_app.sh`
- Test: `Sources/NotchTestRunner/Main.swift`

- [ ] **Step 1: Run complete test suite**
Run: `swift run NotchTestRunner`
Expected: ALL TESTS PASSED SUCCESSFULLY! (11 suites)

- [ ] **Step 2: Build release application package**
Run: `./scripts/build_app.sh`
Expected: `✅ Notch.app successfully built and signed at: .../Notch.app`
