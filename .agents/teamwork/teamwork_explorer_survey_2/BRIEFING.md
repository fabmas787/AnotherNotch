# BRIEFING — 2026-11-06T23:59:58Z

## Mission
Investigate UI & State wiring for Shuffle and Repeat (R4 and R5) across UnifiedMediaManager, NotchViewModel, MediaControlsView, and related files.

## 🔒 My Identity
- Archetype: explorer
- Roles: UI & State Explorer
- Working directory: /Users/fabio/Documents/Notch/.agents/teamwork/teamwork_explorer_survey_2
- Original parent: 5ea9c19d-8d0c-4392-b6e6-4cec7a3ddb85
- Milestone: Survey & Investigation

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Do NOT write or modify any code files
- Deliver handoff.md with 5-component report
- Report via send_message to orchestrator

## Current Parent
- Conversation ID: 5ea9c19d-8d0c-4392-b6e6-4cec7a3ddb85
- Updated: 2026-11-06T23:59:58Z

## Investigation State
- **Explored paths**:
  - `Sources/NotchKit/Media/UnifiedMediaManager.swift`
  - `Sources/NotchKit/ViewModel/NotchViewModel.swift` (note: `ViewModel` singular)
  - `Sources/NotchKit/Views/MediaControlsView.swift`
  - `Sources/NotchKit/Media/MediaServiceProtocol.swift`
  - `Sources/NotchKit/Media/SpotifyService.swift`
  - `Sources/NotchKit/Media/AppleMusicService.swift`
  - `Sources/NotchKit/Media/SimulatedMediaService.swift`
  - `Sources/NotchKit/Views/ExpandedNotchView.swift`
  - `Sources/NotchKit/Views/NotchRootView.swift`
  - `Sources/NotchKit/App/StatusBarController.swift`
  - `Sources/NotchKit/Window/NotchWindowController.swift`
  - `Sources/NotchApp/NotchApp.swift`
  - `Sources/NotchTestRunner/Main.swift`
  - `Package.swift`
- **Key findings**:
  - `UnifiedMediaManager` currently lacks `isShuffleActive` and `repeatMode` `@Published` properties, synchronization in `syncFromActiveService()`, and forwarder methods. Also needs loop check for `repeatMode == .one` in `updateVisualizerAndSmoothProgress()`.
  - `NotchViewModel` currently stores `isShuffleActive` and `repeatMode` locally as `@Published` properties with shortcut comments. Needs conversion to computed properties delegating to `mediaManager`. Already forwards `mediaManager.objectWillChange` to `self.objectWillChange.send()`.
  - `NotchViewModel.onMouseEnter()` needs `mediaManager.effectiveService.refreshState()` added.
  - `MediaControlsView` currently defines `RepeatMode` (lines 4-8). When moved to `MediaServiceProtocol.swift`, removing it from `MediaControlsView.swift` leaves the view intact since they share the `NotchKit` module.
  - Repo search confirms only `MediaControlsView`, `NotchViewModel`, and `NotchTestRunner/Main.swift` reference `repeatMode` or `isShuffleActive`.
  - Baseline tests (`swift run NotchTestRunner`) currently pass. Setting `vm.mediaManager.selectedSource = .demo` in `runMediaControlsTests()` isolates tests from background Spotify instances.
- **Unexplored areas**: None; exploration complete.

## Key Decisions Made
- Confirmed that `NotchViewModel.objectWillChange` already receives and relays `mediaManager.objectWillChange`, ensuring zero UI reactivity lag when delegating properties to `mediaManager`.
- Identified that `repeatMode == .one` in `UnifiedMediaManager.updateVisualizerAndSmoothProgress()` must seek to 0 rather than `nextTrack()` for demo mode.
- Produced comprehensive 5-component report at `/Users/fabio/Documents/Notch/.agents/teamwork/teamwork_explorer_survey_2/handoff.md`.

## Artifact Index
- DISPATCH.md — Initial dispatch instructions
- progress.md — Liveness heartbeat and progress log
- handoff.md — Final 5-component investigation report
