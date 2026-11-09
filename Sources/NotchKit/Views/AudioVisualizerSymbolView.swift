import SwiftUI

public struct AudioVisualizerSymbolView: View {
    public var isPlaying: Bool

    public init(isPlaying: Bool = true) {
        self.isPlaying = isPlaying
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            Image(systemName: "timelapse")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(.white)
                .symbolEffect(.drawOn.wholeSymbol, options: .nonRepeating, isActive: isPlaying)
        } else {
            Image(systemName: "timelapse")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(.white)
        }
    }
}
