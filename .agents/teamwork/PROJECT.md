# Project: Notch Bidirectional Shuffle & Repeat Synchronization

## Architecture
The media architecture in Notch consists of:
1. **Domain Types & Protocols**:
   - `RepeatMode`: Three-state enum (`off`, `all`, `one`), `String`, `CaseIterable`, `Sendable`.
   - `MediaServiceProtocol`: `@MainActor` protocol declaring playback, volume, track, and state synchronization contracts.
2. **Media Services**:
   - `SpotifyService`: Asynchronous AppleScript integration with Spotify.app, with pre-querying of `shuffling` and `repeating`, stopped-state delimiter parsing, and 1.0s debouncing against rubber-banding.
   - `AppleMusicService`: Asynchronous AppleScript integration with Music.app querying `shuffle enabled` and `song repeat as string`.
   - `SimulatedMediaService`: In-memory simulated player advancing tracks in `tick()`, looping the current track when `repeatMode == .one`.
3. **State Management & UI**:
   - `UnifiedMediaManager`: `@MainActor` singleton managing source selection (`.auto`, `.spotify`, `.music`, `.demo`), polling active service state every 0.35s, and publishing state.
   - `NotchViewModel`: Observable object driving the Notch UI. Relays `mediaManager.objectWillChange` to views. Exposes computed properties delegating `isShuffleActive` and `repeatMode` to `mediaManager`. Refreshes active service state on `onMouseEnter()`.
   - `MediaControlsView`: SwiftUI view rendering shuffle and repeat controls with state-reactive styling and animations.
4. **Test Infrastructure**:
   - `NotchTestRunner`: Standalone CLI executable runner executing isolated test suites on the main actor without external dependencies.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | RepeatMode Relocation | Move `RepeatMode` enum from `MediaControlsView.swift` to `MediaServiceProtocol.swift` | M1 | R1 |
| 2 | MediaServiceProtocol Extension | Add `isShuffleActive`, `repeatMode`, `setShuffle`, `setRepeatMode`, `toggleShuffle`, `cycleRepeatMode` to protocol and protocol extension | M1 | R1 |
| 3 | Spotify Bidirectional Sync & Query | Pre-query `shuffling` and `repeating` in AppleScript before player state in `refreshState()`, parsing `|||` components for active and stopped states | M1 | R2 |
| 4 | Spotify Debouncing & Repeat Mapping | Enforce 1.0s debounce window (`CACurrentMediaTime() - lastUserInteractionTime > 1.0`) on incoming updates; map boolean repeat to `RepeatMode` | M1 | R2 |
| 5 | Spotify Setters | Implement `setShuffle(_:)` and `setRepeatMode(_:)` updating local state, timestamp, and firing asynchronous AppleScript | M1 | R2 |
| 6 | AppleMusicService Conformance | Query `shuffle enabled` and `song repeat as string`, mapping 1:1 to `isShuffleActive` and `RepeatMode`; implement async setters | M1 | R3 |
| 7 | SimulatedMediaService Conformance & Looping | Store shuffle/repeat properties and loop track in `tick()` when `repeatMode == .one` and `playbackPosition >= track.duration` | M1 | R3 |
| 8 | UnifiedMediaManager Published State & Forwarders | Publish `isShuffleActive` and `repeatMode`, sync in `syncFromActiveService()`, implement forwarding controls, and handle demo looping | M1 | R4 |
| 9 | NotchViewModel Delegation & Hover Refresh | Convert `isShuffleActive` and `repeatMode` to computed properties delegating to `mediaManager`, forward controls, call `refreshState()` in `onMouseEnter()` | M1 | R5 |
| 10 | Test Suite Isolation | Set `vm.mediaManager.selectedSource = .demo` in `runMediaControlsTests()` to isolate against live Spotify state | M1 | R6 |
| 11 | UnifiedMediaManager Unit Tests | Add comprehensive unit tests in `runUnifiedMediaManagerTests()` covering shuffle/repeat forwarding, cycling, and synchronization | M1 | R6 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Bidirectional Shuffle & Repeat Synchronization | Complete implementation of R1-R6 across protocol, services, manager, view model, and test runner | none | DONE |

## Interface Contracts
### `MediaServiceProtocol`
```swift
public enum RepeatMode: String, CaseIterable, Sendable {
    case off
    case all
    case one
}

@MainActor
public protocol MediaServiceProtocol: AnyObject {
    // Existing properties & methods...
    var isShuffleActive: Bool { get }
    var repeatMode: RepeatMode { get }

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
```

### `UnifiedMediaManager`
```swift
@Published public private(set) var isShuffleActive: Bool = false
@Published public private(set) var repeatMode: RepeatMode = .off

public func setShuffle(_ active: Bool)
public func toggleShuffle()
public func setRepeatMode(_ mode: RepeatMode)
public func cycleRepeatMode()
```

### `NotchViewModel`
```swift
public var isShuffleActive: Bool {
    get { mediaManager.isShuffleActive }
    set { mediaManager.setShuffle(newValue) }
}

public var repeatMode: RepeatMode {
    get { mediaManager.repeatMode }
    set { mediaManager.setRepeatMode(newValue) }
}

public func toggleShuffle()
public func cycleRepeatMode()
public func onMouseEnter()
```

## Code Layout
- `Sources/NotchKit/Media/MediaServiceProtocol.swift` (Protocol definition and RepeatMode enum)
- `Sources/NotchKit/Media/SpotifyService.swift` (Spotify service implementation)
- `Sources/NotchKit/Media/AppleMusicService.swift` (Apple Music service implementation)
- `Sources/NotchKit/Media/SimulatedMediaService.swift` (Simulated demo service implementation)
- `Sources/NotchKit/Media/UnifiedMediaManager.swift` (Manager state aggregation and control forwarding)
- `Sources/NotchKit/ViewModel/NotchViewModel.swift` (ViewModel bindings and hover refresh)
- `Sources/NotchKit/Views/MediaControlsView.swift` (Media controls UI)
- `Sources/NotchTestRunner/Main.swift` (Test runner and unit test suites)
