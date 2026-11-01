import AppKit
import IslandCore
import SwiftUI

extension Color {
    public init(_ rgba: RGBAColor) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

extension RGBAColor {
    /// Converts any SwiftUI colour (e.g. from a `ColorPicker`) to sRGB components.
    public init(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            alpha: Double(converted.alphaComponent)
        )
    }
}

/// The resolved visual system handed to every island view through the environment.
public struct IslandTheme: Sendable, Equatable {
    public var values: ThemeValues
    public var layout: LayoutSettings

    public init(values: ThemeValues = ThemeValues(), layout: LayoutSettings = LayoutSettings()) {
        self.values = values
        self.layout = layout
    }

    public init(_ appearance: AppearanceSettings) {
        self.init(values: appearance.activeTheme, layout: appearance.layout)
    }

    public static let `default` = IslandTheme()

    public var isDark: Bool { values.foreground == .light }
    public var colorScheme: ColorScheme { isDark ? .dark : .light }

    public var primary: Color { isDark ? .white : .black }
    public var secondary: Color { primary.opacity(0.62) }
    public var tertiary: Color { primary.opacity(0.32) }
    /// Subtle fill for controls and wells inside the island.
    public var fill: Color { primary.opacity(0.09) }
    public var accent: Color { Color(values.accent) }
    public var background: Color { Color(values.background).opacity(values.backgroundOpacity) }
    public var border: Color { Color(values.borderColor) }

    public var iconSize: CGFloat { CGFloat(layout.iconSize) }
    public var padding: CGFloat { CGFloat(layout.padding) }

    public var fontDesign: Font.Design {
        switch values.fontDesign {
        case .standard: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .serif: .serif
        }
    }

    /// Fixed sizes keep the island crisp; the theme's scale adjusts them all together.
    public func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * CGFloat(values.fontScale), weight: weight, design: fontDesign)
    }

    public var captionFont: Font { font(11) }
    public var bodyFont: Font { font(13) }
    public var headlineFont: Font { font(13, weight: .semibold) }
    public var titleFont: Font { font(15, weight: .semibold) }

    public func monospacedDigits(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        font(size, weight: weight).monospacedDigit()
    }
}

extension EnvironmentValues {
    @Entry public var islandTheme = IslandTheme.default
    @Entry public var islandAnimations = IslandAnimations.default
}
