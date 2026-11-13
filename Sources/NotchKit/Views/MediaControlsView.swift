import SwiftUI

public struct MediaControlsView: View {
    @ObservedObject public var viewModel: NotchViewModel
    public var showsBackground: Bool

    public init(viewModel: NotchViewModel = NotchViewModel(), showsBackground: Bool = false) {
        self.viewModel = viewModel
        self.showsBackground = showsBackground
    }

    private var isPlaying: Bool {
        viewModel.mediaManager.isPlaying
    }

    private var isShuffleActive: Bool {
        viewModel.isShuffleActive
    }

    private var repeatMode: RepeatMode {
        viewModel.repeatMode
    }

    @ViewBuilder
    private var controlsBody: some View {
        HStack(spacing: 32) {
            // MARK: - Shuffle Button
            Button {
                viewModel.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(isShuffleActive ? Color.green : Color.white)
            }
            .help("Shuffle")

            // MARK: - Previous Track Button
            Button {
                viewModel.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: viewModel.prevBounceTrigger)
            }
            .help("Previous Track")

            // MARK: - Play / Pause Button
            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .semibold, design: .default)) // Larger size for primary control
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(isPlaying ? "Pause" : "Play")

            // MARK: - Next Track Button
            Button {
                viewModel.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: viewModel.nextBounceTrigger)
            }
            .help("Next Track")

            // MARK: - Repeat / Repeat One Button
            Button {
                viewModel.cycleRepeatMode()
            } label: {
                Image(systemName: repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(repeatMode == .off ? Color.white : Color.green)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(repeatMode == .off ? "Repeat Off" : (repeatMode == .all ? "Repeat All" : "Repeat One"))
        }
        // Global font applied to container: SF Pro Semibold
        .font(.system(size: 22, weight: .semibold, design: .default))
        .buttonStyle(.plain)
    }

    public var body: some View {
        if showsBackground {
            controlsBody
                .padding()
                .background(Color.black.ignoresSafeArea()) // Dark reference background for white icon visibility
        } else {
            controlsBody
        }
    }
}

struct MediaControlsView_Previews: PreviewProvider {
    static var previews: some View {
        MediaControlsView(showsBackground: true)
    }
}
