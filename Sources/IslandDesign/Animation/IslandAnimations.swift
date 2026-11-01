import IslandCore
import SwiftUI

/// Maps animation settings to concrete SwiftUI animations and transitions.
///
/// With Reduce Motion on, every movement becomes a short cross-fade: no springs, no scaling,
/// no sliding.
public struct IslandAnimations: Sendable, Equatable {
    public var settings: AnimationSettings
    public var reduceMotion: Bool

    public init(settings: AnimationSettings = AnimationSettings(), reduceMotion: Bool = false) {
        self.settings = settings
        self.reduceMotion = reduceMotion
    }

    public static let `default` = IslandAnimations()

    private var speed: Double {
        min(max(settings.speed, AnimationSettings.speedRange.lowerBound), AnimationSettings.speedRange.upperBound)
    }

    private static let reducedMotion = Animation.easeInOut(duration: 0.18)

    public var expand: Animation {
        if reduceMotion { return Self.reducedMotion }
        return switch settings.style {
        case .spring: .spring(response: 0.42 / speed, dampingFraction: 0.8)
        case .bouncy: .spring(response: 0.5 / speed, dampingFraction: 0.66)
        case .snappy: .snappy(duration: 0.3 / speed)
        case .smooth: .smooth(duration: 0.45 / speed)
        case .easeInOut: .easeInOut(duration: 0.35 / speed)
        }
    }

    /// Contraction is slightly firmer than expansion so the island settles without overshoot.
    public var collapse: Animation {
        if reduceMotion { return Self.reducedMotion }
        return switch settings.style {
        case .spring, .bouncy: .spring(response: 0.38 / speed, dampingFraction: 0.9)
        case .snappy: .snappy(duration: 0.26 / speed)
        case .smooth: .smooth(duration: 0.4 / speed)
        case .easeInOut: .easeInOut(duration: 0.3 / speed)
        }
    }

    public var content: Animation {
        reduceMotion ? Self.reducedMotion : .easeInOut(duration: 0.22 / speed)
    }

    public var notificationArrival: Animation {
        if reduceMotion { return Self.reducedMotion }
        return .spring(response: 0.36 / speed, dampingFraction: settings.style == .bouncy ? 0.6 : 0.75)
    }

    /// `nil` disables artwork transitions entirely.
    public var artwork: Animation? {
        guard settings.artworkTransitions else { return nil }
        return reduceMotion ? Self.reducedMotion : .easeInOut(duration: 0.35 / speed)
    }

    public var animatesIndicators: Bool {
        settings.animateMediaIndicator && !reduceMotion
    }

    public var contentTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return switch settings.contentTransition {
        case .fade: .opacity
        case .scale: .scale(scale: 0.92).combined(with: .opacity)
        case .blur: .modifier(active: BlurFade(radius: 6, opacity: 0), identity: BlurFade(radius: 0, opacity: 1))
        case .slide: .move(edge: .top).combined(with: .opacity)
        }
    }

    public var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.85, anchor: .top).combined(with: .opacity)
    }
}

struct BlurFade: ViewModifier {
    var radius: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}
