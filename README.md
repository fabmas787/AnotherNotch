# Notch Music Prototype

A native macOS utility inspired by [boringNotch](https://github.com/TheBoredTeam/boring.notch) that utilizes the physical display notch as an interactive music controller and dynamic island.

---

## 🌟 Features

- **Hardware Notch Snapping**: Detects physical notch dimensions dynamically using AppKit's `NSScreen.auxiliaryTopLeftArea`, `auxiliaryTopRightArea`, and `safeAreaInsets.top`.
- **Non-Notch / External Display Support**: Automatically falls back to a sleek top-center pill on displays without a hardware notch.
- **Smooth Spring Transitions**: Expands downward on mouse hover into a feature-packed media control island with fluid animations (`.spring(response: 0.38, dampingFraction: 0.78)`).
- **Debounced Collapse**: Includes a graceful hysteresis exit timer (0.35s) to prevent accidental collapse when moving between controls.
- **Pin Mode**: Lock the expanded music card open while multitasking using the pin button or menu bar extra.
- **Live Soundwave Visualizer**: Multi-band animated audio equalizer bars that respond dynamically during playback.
- **Interactive Scrubber Bar**: Drag or click anywhere on the progress bar to scrub/seek playback with live elapsed and remaining timestamps.
- **Full Volume & Mute Controls**: Native sound volume slider and one-click mute button synced across players.
- **Dynamic Album Artwork**: Displays high-resolution album covers fetched directly from active playback (Spotify artwork URL or Apple Music), with ambient gradient glow fallback.
- **Multi-Source Media Player**:
  - **Auto-Detect**: Automatically selects and controls active playback from Apple Music or Spotify without state desync.
  - **Apple Music**: Native non-blocking `NSAppleScript` controls with instant change updates via `com.apple.Music.playerInfo`.
  - **Spotify**: Native non-blocking `NSAppleScript` controls with instant change updates via `com.spotify.client.PlaybackStateChanged`.
  - **Built-in Interactive Demo Player**: Complete playlist with realistic tracks, seeking, volume, and beat animations for instant testing on any Mac.
- **Keyboard Navigation & Dismissal**: Press `Escape` while focused to smoothly collapse or unpin the notch HUD.
- **Menu Bar Status Item (`NSStatusItem`)**: Quick access to toggle the overlay, pin/unpin, switch active source, or quit.
- **Zero Dock Clutter**: Configured with `LSUIElement = true` / `.accessory` activation policy, keeping your Dock clean.

---

## 🏗 Architecture

```
Notch/
├── Package.swift                    # SwiftPM manifest (macOS 14+)
├── scripts/
│   └── build_app.sh                 # Releases and packages signed Notch.app
├── Sources/
│   ├── NotchKit/                    # Reusable framework
│   │   ├── Geometry/
│   │   │   └── ScreenNotchManager.swift    # NSScreen inspection & coordinate conversion
│   │   ├── Media/
│   │   │   ├── TrackInfo.swift             # Track metadata, artwork URLs & source definitions
│   │   │   ├── MediaServiceProtocol.swift  # Protocol for media players with volume/mute
│   │   │   ├── AppleMusicService.swift     # Apple Music integration with async AppleScript
│   │   │   ├── SpotifyService.swift        # Spotify integration with artwork URL fetching
│   │   │   ├── SimulatedMediaService.swift # Demo music player with volume & seeking
│   │   │   └── UnifiedMediaManager.swift   # Source coordinator, smooth progress & visualizer engine
│   │   ├── ViewModel/
│   │   │   └── NotchViewModel.swift        # State management (hover, pin, collapse, volume, scrubbing)
│   │   ├── Views/
│   │   │   ├── NotchRootView.swift         # Root container & transition controller
│   │   │   ├── CompactNotchView.swift      # Wings hugging the physical notch cutout
│   │   │   ├── ExpandedNotchView.swift     # Expanded media card HUD
│   │   │   ├── AlbumArtView.swift          # Live artwork image with gradient vinyl fallback
│   │   │   ├── AudioVisualizerSymbolView.swift # SF Symbol timelapse visualizer
│   │   │   ├── ScrubberBarView.swift       # Interactive scrubber & timestamps
│   │   │   └── AppleMusicSlider.swift      # Apple Music-style spring-expanding slider
│   │   ├── Window/
│   │   │   ├── NotchPanel.swift            # Custom non-activating borderless NSPanel with key & Escape support
│   │   │   └── NotchWindowController.swift # Window lifecycle & frame animator
│   │   └── App/
│   │       └── StatusBarController.swift   # Menu bar extra (status item) with reactive bindings
│   ├── NotchApp/
│   │   └── NotchApp.swift           # Application entry point (@main)
│   └── NotchTestRunner/
│       └── Main.swift               # Comprehensive unit & integration test runner (6 suites)
```

---

## 🚀 Getting Started

### Prerequisites

- macOS 14.0 or later (Tested on macOS 27.2 Apple Silicon)
- Swift 6.0+ toolchain (`swift` / Command Line Tools)

### Building and Running

1. **Run in development mode**:
   ```bash
   swift run Notch
   ```

2. **Run all automated tests**:
   ```bash
   swift run NotchTestRunner
   ```

3. **Build the standalone native `Notch.app` bundle**:
   ```bash
   ./scripts/build_app.sh
   open Notch.app
   ```

---

## 🧪 Automated Test Verification

The test runner tests all core modules across 6 test suites:
- **Geometry Suite**: Hardware notch positioning, horizontal centering on notch midX, flush alignment with screen top, and display fallback positioning.
- **Simulated Media Suite**: Playlist sequencing, play/pause toggles, track advancement and looping, forward/backward seek bounds clamping, rewind logic, and volume/mute handling.
- **Unified Media Manager Suite**: Service routing, source selection, auto-detection without state desynchronization, 12-band audio amplitude generation, and volume forwarding.
- **ViewModel Suite**: Hover states, pin states, collapse hover suppression, volume & mute reactive bindings, expansion logic, and time string formatting (`m:ss` and `-m:ss`).
- **View Layout Suite**: Verifies fitting sizes for both `CompactNotchView` and `ExpandedNotchView` against calculated window geometry frames to prevent control clipping.
- **Panel & Key Suite**: Confirms non-activating key capability for UI controls and Escape key collapse handling.
