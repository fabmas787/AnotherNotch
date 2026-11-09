import SwiftUI

public struct ScrubberBarView: View {
    @ObservedObject public var viewModel: NotchViewModel
    public let duration: TimeInterval

    public init(
        viewModel: NotchViewModel,
        duration: TimeInterval
    ) {
        self.viewModel = viewModel
        self.duration = duration
    }

    private var activePosition: TimeInterval {
        viewModel.isScrubbing ? viewModel.scrubPosition : viewModel.mediaManager.playbackPosition
    }

    public var body: some View {
        VStack(spacing: 6) {
            AppleMusicSlider(
                value: Binding(
                    get: { activePosition },
                    set: { viewModel.scrubPosition = $0 }
                ),
                inRange: 0...max(0.001, duration),
                onEditingChanged: { isScrubbing in
                    if isScrubbing {
                        viewModel.isScrubbing = true
                        viewModel.scrubPosition = activePosition
                    } else {
                        viewModel.seek(to: viewModel.scrubPosition)
                        viewModel.isScrubbing = false
                    }
                }
            )

            // Monospaced timestamps
            HStack {
                Text(viewModel.formatTime(activePosition))
                Spacer()
                Text(viewModel.formatRemainingTime(current: activePosition, total: duration))
            }
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(.white.opacity(0.6))
            .monospacedDigit()
        }
    }
}
