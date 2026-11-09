import SwiftUI

/// Displays a 3-line synchronized lyrics view:
/// - Previous line (dim white)
/// - Current line in the middle (pure bright white)
/// - Next line (dim white)
public struct LyricsView: View {
    @ObservedObject public var viewModel: NotchViewModel
    @ObservedObject private var lyricsService: LyricsService

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self._lyricsService = ObservedObject(wrappedValue: viewModel.lyricsService)
    }

    private var activePosition: TimeInterval {
        let base = viewModel.isScrubbing ? viewModel.scrubPosition : viewModel.mediaManager.playbackPosition
        return base + LyricsService.anticipationLeadTime
    }

    private var activeIndex: Int? {
        lyricsService.activeIndex(for: activePosition)
    }

    private var threeLines: (previous: String?, current: String?, next: String?) {
        lyricsService.threeLines(for: activePosition)
    }

    private var hasActiveTrack: Bool {
        guard let track = viewModel.mediaManager.currentTrack else { return false }
        return track.duration > 0 || (!track.title.isEmpty && track.title != "No Music Playing")
    }

    public var body: some View {
        VStack(alignment: .center, spacing: 6) {
            if !hasActiveTrack {
                statusView(icon: "music.note", text: "Play music to see lyrics")
            } else if lyricsService.isLoading {
                loadingView
            } else if lyricsService.isInstrumental {
                statusView(icon: "waveform", text: "Instrumental")
            } else if lyricsService.hasNoLyrics || lyricsService.currentLyrics.isEmpty {
                statusView(icon: "quote.bubble", text: "Lyrics unavailable")
            } else {
                syncedLyricsView
            }
        }
        .frame(height: 108, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipped()
    }

    // MARK: - Synced 3-Line Presentation

    @ViewBuilder
    private var syncedLyricsView: some View {
        let lines = threeLines
        let active = activeIndex ?? -1
        let isForward = lyricsService.isMovingForward

        SyncedLyricsLinesView(
            previous: lines.previous,
            current: lines.current,
            next: lines.next,
            activeIndex: active,
            isForward: isForward
        )
        .equatable()
    }

    // MARK: - Fallback States

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.65)
                .colorInvert()
            Text("Loading lyrics...")
                .font(.system(size: 13.0, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func statusView(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14.0, weight: .medium))
                .foregroundColor(.white.opacity(0.40))
            Text(text)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.50))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Equatable 3-Line Subview (prevents 60fps frame cancellations during transitions)

private struct SyncedLyricsLinesView: View, Equatable {
    let previous: String?
    let current: String?
    let next: String?
    let activeIndex: Int
    let isForward: Bool

    nonisolated static func == (lhs: SyncedLyricsLinesView, rhs: SyncedLyricsLinesView) -> Bool {
        lhs.activeIndex == rhs.activeIndex &&
        lhs.isForward == rhs.isForward &&
        lhs.previous == rhs.previous &&
        lhs.current == rhs.current &&
        lhs.next == rhs.next
    }

    var body: some View {
        VStack(spacing: 5) {
            // Line 1: Preceding line (dim white)
            ZStack(alignment: .center) {
                Text(previous ?? " ")
                    .id("prev_\(activeIndex)")
                    .font(.system(size: 13.0, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(previous != nil ? 0.38 : 0.0))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: isForward ? 14 : -14).combined(with: .opacity),
                            removal: .offset(y: isForward ? -14 : 14).combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Line 2: Active line (prominent white)
            ZStack(alignment: .center) {
                Text(current ?? "...")
                    .id("curr_\(activeIndex)")
                    .font(.system(size: 15.0, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.98))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: isForward ? 16 : -16).combined(with: .opacity),
                            removal: .offset(y: isForward ? -16 : 16).combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Line 3: Next line (dim white)
            ZStack(alignment: .center) {
                Text(next ?? " ")
                    .id("next_\(activeIndex)")
                    .font(.system(size: 13.0, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(next != nil ? 0.38 : 0.0))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: isForward ? 14 : -14).combined(with: .opacity),
                            removal: .offset(y: isForward ? -14 : 14).combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: activeIndex)
    }
}
