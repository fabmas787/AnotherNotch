# Media Services Exploration Report (R1, R2, R3)

## 1. Observation

A detailed inspection of the current media services architecture and related view and protocol files was conducted. The specific codebase observations are cataloged below.

### 1.1 `Sources/NotchKit/Views/MediaControlsView.swift`
- **Lines 4–8**: Definition of `RepeatMode`:
  ```swift
  public enum RepeatMode: String, CaseIterable, Sendable {
      case off
      case all
      case one
  }
  ```
- **Line 27**: Computed property referencing `viewModel.repeatMode`:
  ```swift
  private var repeatMode: RepeatMode {
      viewModel.repeatMode
  }
  ```
- **Line 79**: Icon presentation conditional on `.one`:
  ```swift
  Image(systemName: repeatMode == .one ? "repeat.1" : "repeat")
  ```
- **Line 80**: Color formatting based on `.off`:
  ```swift
  .foregroundStyle(repeatMode == .off ? Color.white : Color.green)
  ```
- **Line 83**: Dynamic tooltip:
  ```swift
  .help(repeatMode == .off ? "Repeat Off" : (repeatMode == .all ? "Repeat All" : "Repeat One"))
  ```
- **Lines 23–25 & 39**: `isShuffleActive` is queried from `viewModel.isShuffleActive` and sets foreground style (`isShuffleActive ? Color.green : Color.white`).

### 1.2 `Sources/NotchKit/Media/MediaServiceProtocol.swift`
- **Lines 3–21**: Protocol definition:
  ```swift
  import Foundation

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

      func playPause()
      func nextTrack()
      func previousTrack()
      func seek(to seconds: TimeInterval)
      func setVolume(_ volume: Double)
      func setMuted(_ muted: Bool)
      func refreshState()
  }
  ```
- Currently, no shuffle or repeat properties or methods exist on the protocol, and there is no protocol extension providing default implementations.
- All conformers (`SpotifyService`, `AppleMusicService`, `SimulatedMediaService`) are declared `@MainActor`.

### 1.3 `Sources/NotchKit/Media/SpotifyService.swift`
- **Execution Mechanism**: Line 120 executes AppleScript synchronously on a background serial queue via `AppleScriptRunner.runSync(scriptText)` inside `DispatchQueue.global(qos: .userInitiated).async`, with completion updating `@MainActor` properties on `DispatchQueue.main.async`. Asynchronous control actions (lines 184, 190, 196, 203, 212, 221, 227) use `AppleScriptRunner.runAsync(...)`.
- **`refreshState()` Script**: Lines 76–117 currently query `player state`, `name of current track`, `artist of current track`, `album of current track`, `duration of current track`, `player position`, `sound volume`, and `artwork url of current track`. Delimiter is `"|||"`.
- **Parsing**: Lines 126–134 currently check `if output == "stopped" || output == "not_running"`, and then `let components = output.components(separatedBy: "|||")` with `guard components.count >= 6 else { return }`.
- **Verified AppleScript Behavior**: Testing live against running Spotify on macOS revealed that `shuffling` and `repeating` are boolean properties. Running `tell application "Spotify" to return (shuffling as string) & "|||" & (repeating as string)` returns `"true|||false"`. Setting values is accomplished via `tell application "Spotify" to set shuffling to true/false` and `tell application "Spotify" to set repeating to true/false`.

### 1.4 `Sources/NotchKit/Media/AppleMusicService.swift`
- **Execution Mechanism**: Employs `AppleScriptRunner.runSync` in background threads for `refreshState()` and artwork export, and `AppleScriptRunner.runAsync` for playback controls (`playpause`, `next track`, `previous track`, `set player position`, `set sound volume`, `set mute`).
- **Verified AppleScript Behavior**: Testing live against running Music app on macOS verified:
  - `tell application "Music" to return (shuffle enabled as string) & "|||" & (song repeat as string)` returns `"false|||all"` (or `"off"`, `"one"`).
  - Both `shuffle enabled` and `song repeat` can be queried even when playback is stopped.
  - Setting values uses `tell application "Music" to set shuffle enabled to true/false` and `tell application "Music" to set song repeat to off/all/one`.
  - Apple Music state queries immediately following a setter can exhibit transient latency ("rubber-banding"), confirming the need to handle state updates carefully.

### 1.5 `Sources/NotchKit/Media/SimulatedMediaService.swift`
- **Lines 90–96**: Current `tick()` implementation:
  ```swift
  private func tick() {
      guard isPlaying, let track = currentTrack, track.duration > 0 else { return }
      playbackPosition += 0.1
      if playbackPosition >= track.duration {
          nextTrack()
      }
  }
  ```
- **Looping**: Currently always advances to `nextTrack()` when `playbackPosition >= track.duration`, incrementing `currentIndex = (currentIndex + 1) % Self.demoTracks.count`.

---

## 2. Logic Chain

The reasoning linking observations to concrete architecture and implementation decisions is structured below.

### 2.1 Moving `RepeatMode` and Enhancing `MediaServiceProtocol` (R1)
1. **Module Scope**: Both `MediaControlsView.swift` and `MediaServiceProtocol.swift` belong to the `NotchKit` module (under `Sources/NotchKit/`). Moving `RepeatMode` from `MediaControlsView.swift` to `MediaServiceProtocol.swift` does not break any visibility or require imports within `NotchKit`. Outside modules (such as `NotchTestRunner` and the `Notch` app executable) already import `NotchKit` and will continue to access `RepeatMode` seamlessly.
2. **Protocol Design**:
   - `MediaServiceProtocol` must declare:
     - `var isShuffleActive: Bool { get }`
     - `var repeatMode: RepeatMode { get }`
     - `func setShuffle(_ active: Bool)`
     - `func setRepeatMode(_ mode: RepeatMode)`
     - `func toggleShuffle()`
     - `func cycleRepeatMode()`
   - Providing default implementations for `toggleShuffle()` and `cycleRepeatMode()` in a `MediaServiceProtocol` extension means conforming services (`SpotifyService`, `AppleMusicService`, `SimulatedMediaService`) only need to implement stored properties and the `set*` setters.
   - The cycling logic strictly follows:
     `.off` -> `.all` -> `.one` -> `.off`.
     ```swift
     extension MediaServiceProtocol {
         public func toggleShuffle() {
             setShuffle(!isShuffleActive)
         }

         public func cycleRepeatMode() {
             let nextMode: RepeatMode
             switch repeatMode {
             case .off: nextMode = .all
             case .all: nextMode = .one
             case .one: nextMode = .off
             }
             setRepeatMode(nextMode)
         }
     }
     ```

### 2.2 Spotify Bidirectional Synchronization & Debouncing (R2)
1. **Pre-Querying Properties**: In AppleScript, querying `shuffling` and `repeating` inside the application check before inspecting `player state` ensures that repeat and shuffle statuses are captured even if player state is stopped.
2. **Stopped State String Protocol**:
   - If stopped returns `"stopped|||<isShuf>|||<isRep>"`, the existing code `if output == "stopped"` would evaluate to `false`, causing the stopped response to fall through to `guard components.count >= 6 else { return }`, failing to update stopped states.
   - Therefore, the response parser must parse components first (`output.components(separatedBy: "|||")`), handle `"stopped"` by setting `isPlaying = false; currentTrack = nil`, and parse the trailing shuffle/repeat components.
3. **Repeat Mode Mapping for Spotify**:
   - Spotify's AppleScript API only exposes `repeating` as a boolean (`true`/`false`), without distinguishing "repeat all" from "repeat one".
   - Mapping rules:
     - When incoming repeat is `false` -> set `repeatMode = .off`.
     - When incoming repeat is `true` -> if current `repeatMode == .off`, transition to `.all`; if current `repeatMode == .one`, maintain `.one`.
4. **Debouncing Strategy**:
   - Spotify takes a non-negligible duration to propagate state internally after AppleScript calls.
   - Adding `private var lastUserInteractionTime: CFTimeInterval = 0.0`:
     - In `setShuffle` and `setRepeatMode`, update local properties immediately, set `lastUserInteractionTime = CACurrentMediaTime()`, and fire AppleScript asynchronously.
     - In the main thread response handler of `refreshState()`, check `if CACurrentMediaTime() - self.lastUserInteractionTime > 1.0` before applying incoming shuffle and repeat states.

### 2.3 Apple Music Conformance (R3)
1. **AppleScript Property Semantics**:
   - `shuffle enabled as string` evaluates to `"true"` or `"false"`.
   - `song repeat as string` evaluates to `"off"`, `"all"`, or `"one"`. This matches `RepeatMode.RawValue` 1:1.
2. **Implementation Strategy**:
   - In `refreshState()`, query both properties and append them to output components.
   - When parsed on the main thread, `self.isShuffleActive = (isShuf == "true")` and `self.repeatMode = RepeatMode(rawValue: sRep) ?? .off`.
   - Async setters execute `tell application "Music" to set shuffle enabled to ...` and `tell application "Music" to set song repeat to ...`.

### 2.4 Simulated Media Service Conformance (R3)
1. **State Tracking**: `SimulatedMediaService` maintains stored `isShuffleActive: Bool` and `repeatMode: RepeatMode`.
2. **Single-Track Looping**:
   - In `tick()`, when `playbackPosition >= track.duration`:
     - If `repeatMode == .one`: set `playbackPosition = 0.0` (do NOT invoke `nextTrack()`).
     - Otherwise: invoke `nextTrack()`.

---

## 3. Caveats

1. **Downstream UnifiedMediaManager Progress Loop**:
   In `UnifiedMediaManager.swift` (lines 197–202), `updateVisualizerAndSmoothProgress()` advances playback position and calls `nextTrack()` when `playbackPosition >= track.duration` for `.demo` mode. When implementing R4, `UnifiedMediaManager` must also respect `repeatMode == .one` by resetting `playbackPosition = 0.0` rather than skipping to the next song.
2. **Apple Music Debouncing**:
   While R2 explicitly mandates 1.0s debouncing for Spotify, Apple Music AppleScript execution can also experience slight polling latency. Implementing debouncing on `AppleMusicService` using the same `lastUserInteractionTime` pattern is recommended to ensure robust behavior.
3. **AppleScript Permission Prompts**:
   On first execution on macOS, `NSAppleScript` communicating with Spotify or Music prompts the user for system Automation permissions under macOS Privacy & Security. If permission is denied or the application is not running, the try/catch wrappers prevent runtime crashes.

---

## 4. Conclusion

The investigation confirms complete viability of requirements R1, R2, and R3 with clear, well-defined implementation patterns:
- Moving `RepeatMode` to `Sources/NotchKit/Media/MediaServiceProtocol.swift` establishes a single source of truth for repeat states across the app.
- Enhancing `MediaServiceProtocol` with default implementations for `toggleShuffle()` and `cycleRepeatMode()` simplifies conformer requirements.
- Updating `SpotifyService.swift` with pre-querying of `shuffling` and `repeating`, stopped-state delimiter parsing, 1.0s debouncing, and boolean-to-enum mapping fully eliminates rubber-banding.
- Conforming `AppleMusicService.swift` with direct 1:1 string mapping to `RepeatMode` provides native synchronization with Music.app.
- Adjusting `SimulatedMediaService.swift` in `tick()` provides predictable testable looping behavior for unit tests and demo mode.

---

## 5. Verification Method

To independently verify the investigation and subsequent implementation:

1. **Build Verification**:
   ```bash
   swift build
   ```
   Must compile cleanly with zero errors or warnings.

2. **Test Suite Verification**:
   ```bash
   swift run NotchTestRunner
   ```
   All 10 test suites must pass.

3. **Targeted AppleScript Verification**:
   To verify AppleScript queries directly in the local environment:
   ```bash
   osascript -e 'tell application "Spotify" to return (shuffling as string) & "|||" & (repeating as string)'
   osascript -e 'tell application "Music" to return (shuffle enabled as string) & "|||" & (song repeat as string)'
   ```

4. **Invalidation Conditions**:
   - If `RepeatMode` in `MediaControlsView.swift` is not removed, compiler will produce an ambiguous type error.
   - If `SpotifyService` parses `stopped` strictly as `output == "stopped"`, stopped state shuffle/repeat updates will be dropped.
   - If `SimulatedMediaService.tick()` loops on `.all` instead of `.one`, demo playlist progression will stall.
