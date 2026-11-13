import SwiftUI

public struct CompactNotchView: View {
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

    private var hasPhysicalNotch: Bool {
        viewModel.screenManager.currentGeometry.hasPhysicalNotch
    }

    private var notchWidth: CGFloat {
        viewModel.screenManager.currentGeometry.notchRect.width
    }

    private var notchHeight: CGFloat {
        viewModel.screenManager.currentGeometry.notchRect.height
    }

    private var wingWidth: CGFloat {
        viewModel.screenManager.currentGeometry.wingWidth
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Wing: Centered Album Art
            ZStack {
                if let track = currentTrack, track.duration > 0 {
                    ForEach([track]) { t in
                        AlbumArtView(track: t, size: 20, isPlaying: isPlaying)
                            .transition(.opacity)
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundColor(.white.opacity(0.85))
                        .transition(.opacity)
                }
            }
            .frame(width: 20, height: 20)
            .matchedGeometry(id: "albumArt", in: namespace)
            .frame(width: wingWidth, height: notchHeight, alignment: .center)

            // Center: Physical Notch Cutout or Fallback Pill
            ZStack {
                if !hasPhysicalNotch {
                    // Fallback camera housing with subtle lens reflection
                    Capsule()
                        .fill(Color(white: 0.05))
                        .frame(width: notchWidth, height: notchHeight)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 7, height: 7)
                        )
                } else {
                    // Clear space over physical hardware notch
                    Color.clear
                        .frame(width: notchWidth, height: notchHeight)
                }
            }
            .frame(width: notchWidth, height: notchHeight)

            // Right Wing: Centered Playing Status Indicator
            ZStack {
                AudioVisualizerSymbolView(isPlaying: isPlaying)
                    .opacity(hasPhysicalNotch || isPlaying ? 1.0 : 0.4)
            }
            .animation(.easeInOut(duration: 0.25), value: isPlaying)
            .frame(width: wingWidth, height: notchHeight, alignment: .center)
        }
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
