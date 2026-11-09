import SwiftUI

/// A custom Apple-standard continuous curvature Notch shape featuring:
/// - Smooth concave fillets ("ears") at the top corners touching the screen bezel.
/// - G2 continuous squircle curvature at the bottom corners.
/// - Conforms to `InsettableShape` for precise specular rim stroke borders.
public struct AppleNotchShape: InsettableShape, Sendable {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat
    public var insetAmount: CGFloat

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    public init(topRadius: CGFloat = 16, bottomRadius: CGFloat = 16, insetAmount: CGFloat = 0) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.insetAmount = insetAmount
    }

    public func inset(by amount: CGFloat) -> AppleNotchShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }

        let minX = r.minX
        let minY = r.minY
        let maxX = r.maxX
        let maxY = r.maxY

        // Clamp radii so geometry stays solid and valid for any bounds
        let tr = max(0, min(topRadius - insetAmount, min(r.width / 3.0, r.height / 2.0)))
        let br = max(0, min(bottomRadius - insetAmount, min(r.width / 3.0, r.height / 2.0)))
        // Apple continuous squircle curvature constant
        let k: CGFloat = 0.55228475

        var path = Path()

        // 1. Top-left ear: Starts flush with screen bezel at (minX, minY),
        // curves smoothly down and inward to meet the vertical wall at (minX + tr, minY + tr).
        path.move(to: CGPoint(x: minX, y: minY))
        path.addCurve(
            to: CGPoint(x: minX + tr, y: minY + tr),
            control1: CGPoint(x: minX + (k * tr), y: minY),
            control2: CGPoint(x: minX + tr, y: minY + ((1.0 - k) * tr))
        )

        // 2. Left side: Vertical wall down to the bottom corner start.
        path.addLine(to: CGPoint(x: minX + tr, y: maxY - br))

        // 3. Bottom-left corner: Continuous convex squircle curving to the bottom edge.
        path.addCurve(
            to: CGPoint(x: minX + tr + br, y: maxY),
            control1: CGPoint(x: minX + tr, y: maxY - ((1.0 - k) * br)),
            control2: CGPoint(x: minX + tr + ((1.0 - k) * br), y: maxY)
        )

        // 4. Bottom edge: Horizontal line across the bottom.
        path.addLine(to: CGPoint(x: maxX - tr - br, y: maxY))

        // 5. Bottom-right corner: Continuous convex squircle curving up to the vertical wall.
        path.addCurve(
            to: CGPoint(x: maxX - tr, y: maxY - br),
            control1: CGPoint(x: maxX - tr - ((1.0 - k) * br), y: maxY),
            control2: CGPoint(x: maxX - tr, y: maxY - ((1.0 - k) * br))
        )

        // 6. Right side: Vertical wall up to the top ear start.
        path.addLine(to: CGPoint(x: maxX - tr, y: minY + tr))

        // 7. Top-right ear: Curves smoothly up and outward to meet the screen bezel at (maxX, minY).
        path.addCurve(
            to: CGPoint(x: maxX, y: minY),
            control1: CGPoint(x: maxX - tr, y: minY + ((1.0 - k) * tr)),
            control2: CGPoint(x: maxX - (k * tr), y: minY)
        )

        // 8. Top edge: Straight line flush along the screen bezel closing back to (minX, minY).
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.closeSubpath()

        return path
    }
}
