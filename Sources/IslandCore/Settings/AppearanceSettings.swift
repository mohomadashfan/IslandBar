import Foundation

/// sRGB colour that can be stored in JSON.
public struct RGBAColor: Codable, Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(white: Double, alpha: Double = 1) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    public static let black = RGBAColor(white: 0)
    public static let white = RGBAColor(white: 1)
    public static let clear = RGBAColor(white: 0, alpha: 0)
}

public enum ThemePreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case midnightBlack
    case liquidGlass
    case frostedGlass
    case minimalDark
    case minimalLight
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .midnightBlack: "Midnight Black"
        case .liquidGlass: "Liquid Glass"
        case .frostedGlass: "Frosted Glass"
        case .minimalDark: "Minimal Dark"
        case .minimalLight: "Minimal Light"
        case .custom: "Custom"
        }
    }

    /// Built-in values for the preset. `custom` has no values of its own and returns the
    /// Midnight Black look as a starting point.
    public var values: ThemeValues {
        switch self {
        case .midnightBlack, .custom:
            ThemeValues()
        case .liquidGlass:
            ThemeValues(
                background: RGBAColor(white: 0.08), backgroundOpacity: 0.25, material: .liquidGlass,
                borderColor: RGBAColor(white: 1, alpha: 0.35), borderWidth: 0.75,
                shadowOpacity: 0.35, shadowRadius: 14, foreground: .light,
                accent: RGBAColor(red: 0.45, green: 0.78, blue: 1)
            )
        case .frostedGlass:
            ThemeValues(
                background: RGBAColor(white: 0.12), backgroundOpacity: 0.45, material: .thin,
                borderColor: RGBAColor(white: 1, alpha: 0.18), borderWidth: 0.5,
                shadowOpacity: 0.3, shadowRadius: 12, foreground: .light,
                accent: RGBAColor(red: 0.6, green: 0.85, blue: 1)
            )
        case .minimalDark:
            ThemeValues(
                background: RGBAColor(white: 0.13), backgroundOpacity: 1, material: .none,
                borderColor: RGBAColor(white: 1, alpha: 0.08), borderWidth: 0.5,
                shadowOpacity: 0.2, shadowRadius: 8, foreground: .light,
                accent: RGBAColor(red: 0.98, green: 0.62, blue: 0.25)
            )
        case .minimalLight:
            ThemeValues(
                background: RGBAColor(white: 0.97), backgroundOpacity: 1, material: .none,
                borderColor: RGBAColor(white: 0, alpha: 0.1), borderWidth: 0.5,
                shadowOpacity: 0.18, shadowRadius: 10, foreground: .dark,
                accent: RGBAColor(red: 0.0, green: 0.45, blue: 0.95)
            )
        }
    }
}

public enum BlurMaterial: String, Codable, Sendable, CaseIterable {
    case none, ultraThin, thin, regular, thick
    /// System Liquid Glass on macOS 26+, an equivalent material elsewhere.
    case liquidGlass

    public var displayName: String {
        switch self {
        case .none: "None"
        case .ultraThin: "Ultra Thin"
        case .thin: "Thin"
        case .regular: "Regular"
        case .thick: "Thick"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

public enum ForegroundTone: String, Codable, Sendable, CaseIterable {
    case light, dark

    public var displayName: String {
        switch self {
        case .light: "Light text"
        case .dark: "Dark text"
        }
    }
}

public enum FontDesignOption: String, Codable, Sendable, CaseIterable {
    case standard, rounded, monospaced, serif

    public var displayName: String {
        switch self {
        case .standard: "Default"
        case .rounded: "Rounded"
        case .monospaced: "Monospaced"
        case .serif: "Serif"
        }
    }
}

/// The visual (non-geometric) parts of a theme.
public struct ThemeValues: Codable, Sendable, Equatable {
    public var background = RGBAColor.black
    public var backgroundOpacity = 1.0
    public var material = BlurMaterial.none
    public var borderColor = RGBAColor.clear
    public var borderWidth = 0.0
    public var shadowOpacity = 0.4
    public var shadowRadius = 10.0
    public var foreground = ForegroundTone.light
    public var accent = RGBAColor(red: 0.35, green: 0.85, blue: 0.55)
    public var fontDesign = FontDesignOption.rounded
    public var fontScale = 1.0

    public init() {}

    public init(
        background: RGBAColor, backgroundOpacity: Double, material: BlurMaterial,
        borderColor: RGBAColor, borderWidth: Double, shadowOpacity: Double, shadowRadius: Double,
        foreground: ForegroundTone, accent: RGBAColor,
        fontDesign: FontDesignOption = .rounded, fontScale: Double = 1
    ) {
        self.background = background
        self.backgroundOpacity = backgroundOpacity
        self.material = material
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.foreground = foreground
        self.accent = accent
        self.fontDesign = fontDesign
        self.fontScale = fontScale
    }
}

/// Island geometry, independent of the selected theme.
public struct LayoutSettings: Codable, Sendable, Equatable {
    public var expandedWidth = 480.0
    public var expandedHeight = 236.0
    public var cornerRadius = 22.0
    public var compactCornerRadius = 10.0
    public var padding = 14.0
    public var iconSize = 15.0
    /// Width of each side "wing" when a live activity shows in the compact island.
    public var wingWidth = 74.0
    /// Size of the virtual island on displays without a notch.
    public var virtualWidth = 200.0
    public var virtualHeight = 32.0

    public init() {}

    public static let expandedWidthRange = 360.0...720.0
    public static let expandedHeightRange = 180.0...400.0
    public static let cornerRadiusRange = 0.0...40.0
}

public struct AppearanceSettings: Codable, Sendable, Equatable {
    public var preset = ThemePreset.midnightBlack
    /// Values used when `preset == .custom`.
    public var custom = ThemeValues()
    public var layout = LayoutSettings()

    public init() {}

    /// The theme currently in effect.
    public var activeTheme: ThemeValues {
        preset == .custom ? custom : preset.values
    }

    /// Switches to the custom theme, seeded from whatever is showing now so editing starts
    /// from the current look rather than jumping to unrelated values.
    public mutating func beginCustomizing() {
        guard preset != .custom else { return }
        custom = preset.values
        preset = .custom
    }
}

public enum AnimationStyle: String, Codable, Sendable, CaseIterable {
    case spring, bouncy, snappy, smooth, easeInOut

    public var displayName: String {
        switch self {
        case .spring: "Spring"
        case .bouncy: "Bouncy"
        case .snappy: "Snappy"
        case .smooth: "Smooth"
        case .easeInOut: "Ease In-Out"
        }
    }
}

public enum ContentTransitionStyle: String, Codable, Sendable, CaseIterable {
    case fade, scale, blur, slide

    public var displayName: String {
        switch self {
        case .fade: "Fade"
        case .scale: "Scale"
        case .blur: "Blur"
        case .slide: "Slide"
        }
    }
}

public struct AnimationSettings: Codable, Sendable, Equatable {
    public var style = AnimationStyle.spring
    /// Multiplier: 2 is twice as fast, 0.5 half as fast.
    public var speed = 1.0
    public var contentTransition = ContentTransitionStyle.blur
    public var animateMediaIndicator = true
    public var artworkTransitions = true

    public init() {}

    public static let speedRange = 0.5...2.0

    /// Nominal duration of an expand/collapse at the current speed, used to time window
    /// resizing around the SwiftUI animation.
    public var nominalDuration: Double {
        let base: Double = switch style {
        case .spring, .smooth: 0.45
        case .bouncy: 0.55
        case .snappy: 0.3
        case .easeInOut: 0.35
        }
        return base / min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
    }
}
