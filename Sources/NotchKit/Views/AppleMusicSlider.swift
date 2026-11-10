import SwiftUI

public struct AppleMusicSlider: View {
    @Binding public var value: Double
    public var inRange: ClosedRange<Double> = 0.0...1.0
    public var onEditingChanged: (Bool) -> Void = { _ in }

    @GestureState private var isDragging: Bool = false
    @State private var isActivelyEditing: Bool = false

    private let idleHeight: CGFloat = 7
    private let activeHeight: CGFloat = 14
    private let hitTargetHeight: CGFloat = 28

    public init(
        value: Binding<Double>,
        inRange: ClosedRange<Double> = 0.0...1.0,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.inRange = inRange
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let normalizedValue = normalizedProgress()

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))

                Rectangle()
                    .fill(isDragging ? Color.white : Color.white.opacity(0.75))
                    .frame(width: max(0, min(width, width * normalizedValue)))
            }
            .clipShape(Capsule())
            .frame(height: isDragging ? activeHeight : idleHeight)
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { gesture in
                        if !isActivelyEditing {
                            isActivelyEditing = true
                            onEditingChanged(true)
                        }
                        let percentage = min(max(0.0, gesture.location.x / width), 1.0)
                        let newValue = inRange.lowerBound + percentage * (inRange.upperBound - inRange.lowerBound)
                        value = newValue
                    }
                    .onEnded { _ in
                        isActivelyEditing = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: hitTargetHeight)
        .onDisappear {
            if isActivelyEditing {
                isActivelyEditing = false
                onEditingChanged(false)
            }
        }
    }

    private func normalizedProgress() -> CGFloat {
        let total = inRange.upperBound - inRange.lowerBound
        guard total > 0 else { return 0 }
        let current = value - inRange.lowerBound
        return CGFloat(min(max(0.0, current / total), 1.0))
    }
}
