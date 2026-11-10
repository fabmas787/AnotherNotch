# Notch

Notch is a native macOS media controller and heads-up display built with Swift, SwiftUI, and AppKit. It integrates directly into the physical display notch of modern Apple Silicon MacBooks or renders an adaptive floating pill on external and non-notch displays. The utility provides persistent playback controls, volume adjustment, seeking, and real-time synchronized lyrics for Apple Music and Spotify, running as a lightweight accessory application without Dock clutter.

---

## Functional Features

### Display and Notch Adaptation
- **Hardware Notch Snapping**: Detects physical display notch boundaries using AppKit `NSScreen` properties (`auxiliaryTopLeftArea`, `auxiliaryTopRightArea`, and `safeAreaInsets.top`). The HUD aligns flush against the upper bezel and centers dynamically on the notch midpoint.
- **Multi-Display Coordinate Offsets**: Normalizes screen-local auxiliary bounds against global display coordinates, ensuring proper positioning on secondary, mirrored, or arrangement-offset monitors including negative-offset displays.
- **Adaptive Fallback Pill**: Renders a compact camera housing and simulated lens on external monitors or Mac models without a physical notch cutout.
- **Dynamic Reconfiguration**: Subscribes to `NSApplication.didChangeScreenParametersNotification` to recompute geometry immediately upon display connection, disconnection, or resolution changes.

### Window Behavior and Interaction
- **Hover Expansion**: Smoothly expands downward from compact wings into an expanded control HUD when hovered, using spring animations (`.spring(response: 0.42, dampingFraction: 0.80)`).
- **Debounced Collapse**: Employs an exit hysteresis timer (0.45s) on cursor departure to prevent accidental collapse when scrubbing, adjusting sliders, or transitioning across UI elements.
- **Pin Mode**: Enables locking the expanded card in place via a UI toggle, menu bar action, or keyboard shortcut. When pinned, the window accepts key input; when unpinned, hover interaction does not steal focus from underlying applications.
- **Selective Hit-Testing**: Uses a custom view container that restricts mouse event interception strictly to the visible geometry of the notch, allowing clicks outside the active pill or card to pass through unimpeded to background applications.
- **Background Accessory Lifecycle**: Configured with `LSUIElement = true` and `NSApplication.ActivationPolicy.accessory`, running without a Dock icon while remaining accessible through the status bar and global hotkeys.

### Media Playback and Routing
- **Multi-Source Coordination**: The `UnifiedMediaManager` detects and routes between Apple Music, Spotify, and an offline simulated demo player. When configured to Auto, priority is given to actively playing applications, followed by running applications with valid track metadata.
- **Apple Music Integration**: Communicates via asynchronous, non-blocking `NSAppleScript` execution and subscribes to distributed notifications (`com.apple.Music.playerInfo`) for immediate state synchronization.
- **Spotify Integration**: Interacts via `NSAppleScript` commands and listens for `com.spotify.client.PlaybackStateChanged` distributed notifications.
- **Offline Demo Player**: Ships with a built-in simulated playlist (`SimulatedMediaService`) providing full seeking, track skipping, play/pause, and looping capabilities for development and testing environments without active media subscriptions.

### Playback Controls and Audio Scrubbing
- **Core Transport Controls**: Supports play, pause, track skipping, and rewinding. Transport buttons integrate Apple layer-bounce symbol effects (`.symbolEffect(.bounce.down.byLayer)`) for tactile visual feedback.
- **Shuffle and Repeat**: Toggles shuffle state with visual accent indicators and cycles repeat modes between off, repeat all, and repeat one (`repeat.1`).
- **Interactive Scrubber Bar**: Drag-to-seek progress bar utilizing an Apple Music-style spring slider that expands in thickness while dragging. Features live elapsed and remaining timestamps formatted as `m:ss` and `-m:ss`.
- **Directional Slide Transitions**: Album artwork and typography transition directionally based on whether the user skipped forward or backward.

### Synchronized Lyrics Display
- **LRCLIB Integration**: Queries the public LRCLIB REST API for timestamped LRC transcripts using track title, artist, and duration criteria.
- **Three-Line Synchronized Interface**: Displays a scrollable three-line interface featuring the previous line (dimmed), active line (bright white), and upcoming line (dimmed).
- **Vocal Anticipation Offset**: Advances lyric highlights 0.35 seconds ahead of raw playback time to compensate for vocal entry delay.
- **Binary Search Indexing**: Calculates current lyric indices in logarithmic time (`O(log n)`) against playback timecodes.
- **Bounded In-Memory Cache**: Maintains an in-memory cache of up to 50 parsed track lyrics using an LRU eviction policy to minimize network overhead.
- **Graceful Fallback Handling**: Distinct UI states for loading indicators, instrumental tracks, unavailable lyrics, and unformatted text transcripts.

### Hotkeys and Keyboard Shortcuts
- **Global Carbon Hotkeys**: System-wide shortcuts registered via Carbon APIs without requiring macOS Accessibility permissions:
  - `Control + Command + N`: Toggle notch overlay visibility.
  - `Control + Command + P`: Toggle HUD pin mode.
  - `Control + Command + L`: Toggle lyrics view visibility.
- **Panel Key Navigation**: When the notch panel is focused:
  - `Escape`: Collapse and unpin the HUD.
  - `Space`: Toggle play/pause playback.
  - `Command + P` or `Control + Command + P`: Toggle pin mode.
  - `Command + L` or `Control + Command + L`: Toggle lyrics view.

---

## Code Architecture

### Project Hierarchy

```
Notch/
├── Package.swift
├── scripts/
│   └── build_app.sh
├── Sources/
│   ├── NotchKit/
│   │   ├── App/
│   │   │   ├── HotKeyManager.swift
│   │   │   └── StatusBarController.swift
│   │   ├── Geometry/
│   │   │   └── ScreenNotchManager.swift
│   │   ├── Lyrics/
│   │   │   ├── LRCParser.swift
│   │   │   ├── LyricLine.swift
│   │   │   └── LyricsService.swift
│   │   ├── Media/
│   │   │   ├── AppleMusicService.swift
│   │   │   ├── AppleScriptRunner.swift
│   │   │   ├── MediaServiceProtocol.swift
│   │   │   ├── SimulatedMediaService.swift
│   │   │   ├── SpotifyService.swift
│   │   │   ├── TrackInfo.swift
│   │   │   └── UnifiedMediaManager.swift
│   │   ├── ViewModel/
│   │   │   └── NotchViewModel.swift
│   │   ├── Views/
│   │   │   ├── AlbumArtView.swift
│   │   │   ├── AppleMusicSlider.swift
│   │   │   ├── AppleNotchShape.swift
│   │   │   ├── AudioVisualizerSymbolView.swift
│   │   │   ├── CompactNotchView.swift
│   │   │   ├── ExpandedNotchView.swift
│   │   │   ├── LiquidGlassBackground.swift
│   │   │   ├── LyricsView.swift
│   │   │   ├── MediaControlsView.swift
│   │   │   ├── NotchRootView.swift
│   │   │   └── ScrubberBarView.swift
│   │   └── Window/
│   │       ├── NotchPanel.swift
│   │       └── NotchWindowController.swift
│   ├── NotchApp/
│   │   └── NotchApp.swift
│   └── NotchTestRunner/
│       └── Main.swift
```

### Module Responsibilities

#### Geometry and Display Management (`Sources/NotchKit/Geometry/`)
- `ScreenNotchManager.swift`: Queries active screen parameters, checks `safeAreaInsets.top` to identify physical notch presence, translates auxiliary area frames into global coordinates, and publishes `NotchGeometry` state changes.
- `NotchGeometry`: Immutable struct encapsulating screen bounds, notch dimensions, wing offsets, compact frame bounds, expanded frame bounds, and overall bounding window frames.

#### Windowing and Event Handling (`Sources/NotchKit/Window/`)
- `NotchPanel.swift`: Custom `NSPanel` subclass configured with style masks `[.borderless, .nonactivatingPanel]`, floating at window level `.screenSaver`. Conforms to `.canJoinAllSpaces`, `.fullScreenAuxiliary`, and `.stationary` collection behaviors to maintain persistence across Spaces and fullscreen applications.
- `NotchWindowController.swift`: Coordinates window frames, binds view-model events, handles space transition notifications (`NSWorkspace.activeSpaceDidChangeNotification`), and manages key window focus.
- `NotchPassthroughHostingView`: Overrides AppKit `hitTest(_:)` against a dynamically computed interactive rectangle, passing non-interactive transparent points through to underlying macOS windows.

#### Continuous Curvature Rendering (`Sources/NotchKit/Views/`)
- `AppleNotchShape.swift`: Custom SwiftUI `InsettableShape` constructing Apple-standard continuous G2 squircle curves. Implements cubic Bézier formulas using the Apple squircle curvature constant `k = 0.55228475`. Generates concave top fillets ("ears") meeting the display bezel flush at `(minX, minY)` and `(maxX, minY)`, alongside squircle bottom corners. Supports animatable radii for state transitions.
- `LiquidGlassBackground.swift`: Dual-layer background rendering a solid pitch-black foundation bordered by a subtle multi-stop specular gradient rim along the bottom contour.
- `CompactNotchView.swift`: Compact wing layout housing an album art miniature on the left wing and an animated audio playback indicator (`AudioVisualizerSymbolView`) on the right wing, positioned around the hardware cutout.
- `ExpandedNotchView.swift`: Two-column split layout for synchronized lyrics mode alongside hero artwork and metadata, or a centered layout when lyrics are disabled.
- `AppleMusicSlider.swift`: Custom slider implementation featuring interactive hit-target expansion from 7pt to 14pt during drag gestures with spring recovery.

#### Media Integration and Script Engine (`Sources/NotchKit/Media/`)
- `AppleScriptRunner.swift`: Thread-safe execution wrapper maintaining a pre-compiled `NSAppleScript` cache (bounded to 20 instances) evaluated on a dedicated serial background dispatch queue (`com.notch.applescript`).
- `AppleMusicService.swift`: Handles AppleScript queries for player state, track titles, artists, albums, duration, player positions, shuffle, repeat, and volume. Album art is extracted via AppleScript raw data descriptor handles and decoded on a dedicated utility queue.
- `SpotifyService.swift`: Controls Spotify via AppleScript, extracting metadata and remote artwork URLs for asynchronous image fetching.
- `TrackInfo.swift`: Data representation of track metadata, remote URLs, and embedded raw artwork bytes. Implements image downsampling using ImageIO (`CGImageSourceCreateThumbnailAtIndex`) capped at 160px to maintain minimal heap allocations.
- `UnifiedMediaManager.swift`: Aggregates player services, normalizes volume and mute states, and drives progress tracking. Throttles timer ticks from 60 Hz during expanded state to 1 Hz when collapsed, disabling visualizer computation during collapse to conserve battery.

#### Lyrics Engine (`Sources/NotchKit/Lyrics/`)
- `LRCParser.swift`: Regular expression parser supporting standard and high-precision LRC timestamp formats (`[mm:ss.xx]`, `[mm:ss.xxx]`, and `[mm:ss]`). Extracts millisecond timecodes, sorts chronologically, filters whitespace lines, and generates sequential identifiers.
- `LyricsService.swift`: Network actor managing requests to `https://lrclib.net/api/get`. Implements title and artist sanitization (stripping remastered, featured artist tags, and edition markers), executes binary search for active lyric lines, and manages a 50-track in-memory cache.

#### Global Shortcuts and Status Item (`Sources/NotchKit/App/`)
- `HotKeyManager.swift`: Encapsulates Carbon `RegisterEventHotKey` APIs to register system-wide key combinations without requiring Accessibility permissions.
- `StatusBarController.swift`: Manages the `NSStatusItem` in the macOS menu bar, updating toggle states for pin mode, lyrics visibility, and overlay status.

---

## Technical Specifications

| Parameter | Specification |
|---|---|
| Platform Requirement | macOS 14.0 (Sonoma) or later |
| Supported Architectures | Apple Silicon (arm64), Intel (x86_64) |
| Toolchain | Swift 6.0 |
| Window Level | `NSWindow.Level.screenSaver` |
| Window Style Mask | `[.borderless, .nonactivatingPanel]` |
| Application Policy | `LSUIElement = true` (`.accessory`) |
| Expanded Canvas Dimensions | 520pt × 290pt |
| Compact Corner Radius | 16pt (Apple continuous squircle) |
| Expanded Corner Radius | 20pt (Apple continuous squircle) |
| Curvature Constant (k) | 0.55228475 |
| Collapse Exit Debounce | 0.45 seconds |
| Lyric Anticipation Offset | 0.35 seconds |
| Lyric Cache Limit | 50 tracks (FIFO/LRU) |
| AppleScript Cache Limit | 20 compiled scripts |
| Artwork Thumbnail Max Size | 160px (ImageIO downsampled) |
| Expanded Display Refresh | 60 Hz |
| Collapsed Refresh Rate | 1 Hz |

---

## Getting Started

### Prerequisites

- macOS 14.0 or later
- Swift 6.0 command-line tools installed (`xcode-select --install` or Xcode 16+)

### Running in Development

Execute the executable target directly via the Swift Package Manager:

```bash
swift run Notch
```

### Running the Test Suite

Execute the standalone test runner:

```bash
swift run NotchTestRunner
```

### Building the Standalone Application

Package a native `.app` bundle signed with an ad-hoc signature:

```bash
./scripts/build_app.sh
open Notch.app
```

The script builds a release binary (`swift build -c release`), creates the `Notch.app` bundle directory structure, injects `Info.plist` with required bundle keys (`LSUIElement`, `CFBundleIdentifier`, `NSAppleEventsUsageDescription`), copies application icons, and signs the bundle with `codesign`.

---

## Automated Test Verification

The included test runner (`NotchTestRunner`) executes 11 validation suites:

1. **Geometry Suite**: Validates compact and expanded frame calculations, horizontal centering against notch midpoints, flush alignment with top screen edges, fallback positioning on non-notch displays, and multi-display coordinate translation across horizontal and vertical monitor offsets.
2. **Apple Notch Shape and Liquid Glass Suite**: Validates squircle curvature paths, continuous fillet generation, inset stroke integrity, and background configuration.
3. **Simulated Media Service Suite**: Verifies playlist playback, sequential track advancement, boundary clamping on forward and backward seeks, play/pause toggles, and volume and mute operations.
4. **Unified Media Manager Suite**: Tests automated player routing, preference hierarchies between Spotify and Apple Music, manual source selection, and service delegation.
5. **ViewModel Suite**: Tests hover detection, debounce invalidation, pin state toggling, keyboard collapse suppression, reactive volume synchronization, and timecode formatting.
6. **View Layout Suite**: Measures `fittingSize` for `CompactNotchView` and `ExpandedNotchView` against calculated window geometry frames to verify layouts render within frame bounds without clipping.
7. **Panel and Key Handling Suite**: Tests non-activating panel attributes, key event routing, Escape key collapse, and modifier key identification.
8. **Performance, Battery, and Lifecycle Suite**: Validates timer throttling (1 Hz collapsed vs. 60 Hz expanded), visualizer deactivation when collapsed, and memory cleanup upon deinitialization.
9. **Media Controls Suite**: Tests transport button actions, state bindings for shuffle and cyclic repeat modes, and layer-bounce trigger increments.
10. **Status Bar Controller Suite**: Tests menu item hierarchy, reactive synchronization with view-model states, and Carbon global hotkey registrations.
11. **Synchronized Lyrics Suite**: Verifies LRC string parsing across varied timestamp formats (`[mm:ss.xx]`, `[mm:ss.xxx]`, `[mm:ss]`), binary search position matching, three-line sliding window extraction, vocal anticipation offsets, cache eviction bounds, and instrumental track state transitions.

---

## License

This project is licensed under the GNU General Public License v3.0. See the [LICENSE](LICENSE) file for details.
