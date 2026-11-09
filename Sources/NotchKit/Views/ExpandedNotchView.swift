import SwiftUI

public struct ExpandedNotchView: View {
    @ObservedObject public var viewModel: NotchViewModel
    public var namespace: Namespace.ID?

    public init(viewModel: NotchViewModel, namespace: Namespace.ID? = nil) {
        self.viewModel = viewModel
        self.namespace = namespace
    }

    private var currentTrack: TrackInfo? {
        viewModel.mediaManager.currentTrack
    }

    private var isPlaying: Bool {
        viewModel.mediaManager.isPlaying
    }

    private var hasActiveTrack: Bool {
        guard let track = currentTrack else { return false }
        return track.duration > 0 || (!track.title.isEmpty && track.title != "No Music Playing")
    }

    private var geometry: NotchGeometry {
        viewModel.screenManager.currentGeometry
    }

    private var notchHeight: CGFloat {
        geometry.notchRect.height
    }

    private var expandedWidth: CGFloat {
        geometry.expandedSize.width
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Notch Clearance: Safe clearance under hardware or fallback notch
            // Top left and top right ears remain completely clean pitch black glass (no Spotify or Playing text)
            Color.clear
                .frame(height: max(notchHeight, 36.0) + 6.0)

            if viewModel.showLyrics {
                // Split Layout: Left = Artwork + Track Info, Right = 3-Line Lyrics
                HStack(alignment: .center, spacing: 20) {
                    // Left Column: Hero Album Artwork + Track Typography
                    VStack(spacing: 8) {
                        ZStack {
                            if let track = currentTrack {
                                ForEach([track]) { t in
                                    AlbumArtView(track: t, size: 64.0, isPlaying: isPlaying)
                                        .transition(
                                            viewModel.isGoingForward
                                                ? .asymmetric(
                                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)
                                                )
                                                : .asymmetric(
                                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                                )
                                        )
                                }
                            } else {
                                AlbumArtView(track: nil, size: 64.0, isPlaying: false)
                                    .transition(.opacity)
                            }
                        }
                        .frame(width: 64.0, height: 64.0)
                        .matchedGeometry(id: "albumArt", in: namespace)

                        VStack(spacing: 2) {
                            Text(currentTrack?.title ?? "No Song Playing")
                                .font(.system(size: 14.0, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.96))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.center)

                            Text(currentTrack?.artist ?? "Select or play music")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(width: 156.0)

                    // Right Column: Synchronized 3-Line Lyrics
                    LyricsView(viewModel: viewModel)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .transition(.opacity)
            } else {
                // Centered Layout: Centered Hero Album Artwork & Track Typography
                VStack(spacing: 0) {
                    ZStack {
                        if let track = currentTrack {
                            ForEach([track]) { t in
                                AlbumArtView(track: t, size: 76.0, isPlaying: isPlaying)
                                    .transition(
                                        viewModel.isGoingForward
                                            ? .asymmetric(
                                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)
                                            )
                                            : .asymmetric(
                                                insertion: .move(edge: .leading).combined(with: .opacity),
                                                removal: .move(edge: .trailing).combined(with: .opacity)
                                            )
                                    )
                            }
                        } else {
                            AlbumArtView(track: nil, size: 76.0, isPlaying: false)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: 76.0, height: 76.0)
                    .matchedGeometry(id: "albumArt", in: namespace)
                    .padding(.top, 2)

                    VStack(spacing: 3) {
                        Text(currentTrack?.title ?? "No Song Playing")
                            .font(.system(size: 15.0, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.96))
                            .lineLimit(1)
                            .multilineTextAlignment(.center)

                        Text(currentTrack?.artist ?? "Select or play music")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 10)
                }
                .transition(.opacity)
            }

            Spacer(minLength: 8)

            // Scrubber Bar with generous horizontal padding so timestamps stay safely in bounds
            ScrubberBarView(
                viewModel: viewModel,
                duration: currentTrack?.duration ?? 0.0
            )
            .padding(.horizontal, 36)

            Spacer(minLength: 8)

            // Animated SF Symbols Media Controls Bar centered
            MediaControlsView(viewModel: viewModel)
                .padding(.bottom, 18)
        }
        .frame(width: expandedWidth)
    }
}

private extension View {
    @ViewBuilder
    func matchedGeometry(id: AnyHashable, in namespace: Namespace.ID?) -> some View {
        if let namespace = namespace {
            self.matchedGeometryEffect(id: id, in: namespace, properties: .frame, anchor: .center)
        } else {
            self
        }
    }
}
