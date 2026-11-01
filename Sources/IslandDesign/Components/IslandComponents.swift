import SwiftUI

/// Round icon button used throughout the island.
public struct IslandIconButton: View {
    var symbol: String
    var size: CGFloat?
    var prominent: Bool
    var help: String
    var action: () -> Void

    @Environment(\.islandTheme) private var theme

    public init(_ symbol: String, size: CGFloat? = nil, prominent: Bool = false, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.size = size
        self.prominent = prominent
        self.help = help
        self.action = action
    }

    public var body: some View {
        let iconSize = size ?? theme.iconSize
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: iconSize * 2, height: iconSize * 2)
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle(fill: prominent ? theme.primary.opacity(0.16) : .clear, pressedFill: theme.fill))
        .foregroundStyle(theme.primary)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct IslandPressStyle: ButtonStyle {
    var fill: Color
    var pressedFill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(configuration.isPressed ? pressedFill : fill))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Capsule text button for secondary actions inside the island.
public struct IslandPillButton: View {
    var title: String
    var symbol: String?
    var action: () -> Void

    @Environment(\.islandTheme) private var theme

    public init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(theme.font(11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(theme.fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.primary)
    }
}

public struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat
    var color: Color?

    @Environment(\.islandTheme) private var theme

    public init(progress: Double, lineWidth: CGFloat = 3, color: Color? = nil) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.color = color
    }

    public var body: some View {
        ZStack {
            Circle().stroke(theme.tertiary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color ?? theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

public struct MeterBar: View {
    var value: Double
    var color: Color?

    @Environment(\.islandTheme) private var theme

    public init(value: Double, color: Color? = nil) {
        self.value = value
        self.color = color
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.fill)
                Capsule()
                    .fill(color ?? theme.accent)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

/// Shown when a module has nothing to display or an integration is unavailable.
public struct IslandEmptyState: View {
    var symbol: String
    var title: String
    var message: String?

    @Environment(\.islandTheme) private var theme

    public init(symbol: String, title: String, message: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.tertiary)
            Text(title)
                .font(theme.headlineFont)
                .foregroundStyle(theme.primary)
            if let message {
                Text(message)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }
}

/// The standard raised card used for tiles and rows inside the island.
public struct IslandCardBackground: View {
    var cornerRadius: CGFloat

    @Environment(\.islandTheme) private var theme

    public init(cornerRadius: CGFloat = 10) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(theme.fill)
            .overlay(shape.fill(LinearGradient(colors: [theme.primary.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(theme.primary.opacity(0.07), lineWidth: 0.5))
    }
}

extension View {
    public func islandCard(cornerRadius: CGFloat = 10) -> some View {
        background(IslandCardBackground(cornerRadius: cornerRadius))
    }
}

/// Minimal line chart with a soft fill, for metric history.
public struct Sparkline: View {
    var values: [Double]
    var maxValue: Double?
    var color: Color?

    @Environment(\.islandTheme) private var theme

    public init(values: [Double], maxValue: Double? = nil, color: Color? = nil) {
        self.values = values
        self.maxValue = maxValue
        self.color = color
    }

    public var body: some View {
        GeometryReader { proxy in
            let points = Self.points(values, maxValue: maxValue, in: proxy.size)
            if points.count > 1 {
                let line = Path { path in path.addLines(points) }
                let area = Path { path in
                    path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                    path.addLines(points)
                    path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                    path.closeSubpath()
                }
                let tint = color ?? theme.accent
                area.fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                line.stroke(tint, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    static func points(_ values: [Double], maxValue: Double?, in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let top = max(maxValue ?? values.max() ?? 1, 0.000_1)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(min(max(value / top, 0), 1))))
        }
    }
}
