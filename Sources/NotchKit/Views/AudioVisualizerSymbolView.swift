import SwiftUI

public struct AudioVisualizerSymbolView: View {
    public var isPlaying: Bool

    public init(isPlaying: Bool = true) {
        self.isPlaying = isPlaying
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            Image(systemName: "timelapse")
                .font(.custom("SFProDisplay-Semibold", size: 20))
                .foregroundStyle(.white)
                .symbolEffect(.drawOn.wholeSymbol, options: .nonRepeating, isActive: isPlaying)
        } else {
            Image(systemName: "timelapse")
                .font(.custom("SFProDisplay-Semibold", size: 20))
                .foregroundStyle(.white)
        }
    }
}
