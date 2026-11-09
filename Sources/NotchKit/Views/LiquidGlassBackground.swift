import SwiftUI
import AppKit

// MARK: - Dynamic Morphing Notch Shell
public struct LiquidGlassBackground: View {
    public let isExpanded: Bool
    public let hasPhysicalNotch: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(isExpanded: Bool, hasPhysicalNotch: Bool = false) {
        self.isExpanded = isExpanded
        self.hasPhysicalNotch = hasPhysicalNotch
    }

    /// Consistent Apple squircle corner radius: 16pt in compact mode, 20pt in expanded mode.
    /// The top corners ("ears") touching the screen bezel match the bottom corners.
    private var cornerRadius: CGFloat {
        isExpanded ? 20.0 : 16.0
    }

    private var notchShape: AppleNotchShape {
        AppleNotchShape(topRadius: cornerRadius, bottomRadius: cornerRadius)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Pure uniform black base across both compact and expanded states
            notchShape
                .fill(Color.black)

            if !isExpanded {
                // Minimized State: seamless subtle stroke along bottom curve
                notchShape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white.opacity(0.12), location: 0.5),
                                .init(color: .white.opacity(0.22), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
        }
    }
}
