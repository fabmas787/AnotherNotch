import SwiftUI

public struct AlbumArtView: View {
    public let track: TrackInfo?
    public let size: CGFloat
    public let isPlaying: Bool

    public init(track: TrackInfo?, size: CGFloat = 64.0, isPlaying: Bool = true) {
        self.track = track
        self.size = size
        self.isPlaying = isPlaying
    }

    /// Unified corner radius conforming to Apple design tokens: 14pt for main card, 6pt for mini wings.
    private var cornerRadius: CGFloat {
        size > 50 ? 14.0 : (size > 30 ? 10.0 : 6.0)
    }

    public var body: some View {
        ZStack {
            // Subtle ambient depth glow (monochrome, non-neon)
            if isPlaying {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .blur(radius: 6)
                    .scaleEffect(1.04)
            }

            // Main Artwork Box
            ZStack {
                if let image = track?.decodedImage ?? track?.artworkData.flatMap({ NSImage(data: $0) }) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                } else if let url = track?.artworkURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            liquidGlassPlaceholder
                        }
                    }
                    .frame(width: size, height: size)
                    .clipped()
                } else {
                    liquidGlassPlaceholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // Dynamic multi-stop specular refraction rim
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.40), location: 0.0),
                                .init(color: .white.opacity(0.12), location: 0.35),
                                .init(color: .black.opacity(0.20), location: 0.70),
                                .init(color: .white.opacity(0.25), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.30), radius: 8, x: 0, y: 4)
    }

    private var liquidGlassPlaceholder: some View {
        ZStack {
            // Dark Frosted Acrylic Surface
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.18).opacity(0.85),
                            Color(white: 0.08).opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Vinyl groove lines
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .scaleEffect(0.72)

            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                .scaleEffect(0.48)

            // Center spindle hole
            Circle()
                .fill(Color(white: 0.08))
                .frame(width: size * 0.18, height: size * 0.18)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            // Minimalist icon
            Image(systemName: track?.source.systemIcon ?? "music.note")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
        }
    }
}
