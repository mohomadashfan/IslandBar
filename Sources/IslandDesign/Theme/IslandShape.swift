import SwiftUI

/// The island outline.
///
/// When `earRadius > 0` the top edge is flush with the screen and flares outward with concave
/// "ears", the way a hardware notch meets the menu bar. With `earRadius == 0` it is a rounded
/// rectangle using `topRadius` for the top corners, for floating islands.
public struct IslandShape: Shape {
    public var bottomRadius: CGFloat
    public var earRadius: CGFloat
    public var topRadius: CGFloat

    public init(bottomRadius: CGFloat, earRadius: CGFloat = 0, topRadius: CGFloat = 0) {
        self.bottomRadius = bottomRadius
        self.earRadius = earRadius
        self.topRadius = topRadius
    }

    public var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(bottomRadius, AnimatablePair(earRadius, topRadius)) }
        set {
            bottomRadius = newValue.first
            earRadius = newValue.second.first
            topRadius = newValue.second.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return Path() }

        let ear = max(0, min(earRadius, w / 4, h / 2))
        let bodyWidth = w - ear * 2
        let bottom = max(0, min(bottomRadius, bodyWidth / 2, h - ear))
        let top = ear > 0 ? 0 : max(0, min(topRadius, w / 2, h / 2))

        var path = Path()
        if ear > 0 {
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addArc(tangent1End: CGPoint(x: w - ear, y: 0), tangent2End: CGPoint(x: w - ear, y: h), radius: ear)
            path.addArc(tangent1End: CGPoint(x: w - ear, y: h), tangent2End: CGPoint(x: 0, y: h), radius: bottom)
            path.addArc(tangent1End: CGPoint(x: ear, y: h), tangent2End: CGPoint(x: ear, y: 0), radius: bottom)
            path.addArc(tangent1End: CGPoint(x: ear, y: 0), tangent2End: CGPoint(x: 0, y: 0), radius: ear)
        } else {
            path.move(to: CGPoint(x: w / 2, y: 0))
            path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: h), radius: top)
            path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: 0, y: h), radius: bottom)
            path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: 0), radius: bottom)
            path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: w, y: 0), radius: top)
        }
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
