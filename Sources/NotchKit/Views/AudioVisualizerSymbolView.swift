import SwiftUI

public struct AudioVisualizerSymbolView: View {
    public var isPlaying: Bool

    public init(isPlaying: Bool = true) {
        self.isPlaying = isPlaying
    }

    public var body: some View {
        if #available(macOS 14.0, *) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isPlaying ? Color.white : Color.white.opacity(0.4))
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isPlaying)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isPlaying ? Color.white : Color.white.opacity(0.4))
        }
    }
}
