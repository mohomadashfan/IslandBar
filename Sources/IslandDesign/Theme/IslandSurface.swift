import AppKit
import IslandCore
import SwiftUI

/// Background of the island: blur material or Liquid Glass, tint, border and shadow.
public struct IslandSurface: View {
    public var shape: IslandShape
    public var showsShadow: Bool

    @Environment(\.islandTheme) private var theme

    public init(shape: IslandShape, showsShadow: Bool) {
        self.shape = shape
        self.showsShadow = showsShadow
    }

    public var body: some View {
        base
            .overlay {
                // Raised states get a little light from below and a hairline edge. The top stays
                // untouched so the island still melts into the hardware notch.
                if showsShadow {
                    shape.fill(LinearGradient(colors: [.clear, theme.primary.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    if theme.values.borderWidth == 0 {
                        shape.stroke(
                            LinearGradient(colors: [.clear, theme.primary.opacity(0.14)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.75
                        )
                    }
                }
            }
            .overlay {
                if theme.values.borderWidth > 0 {
                    shape.stroke(theme.border, lineWidth: theme.values.borderWidth)
                }
            }
            .shadow(
                color: .black.opacity(showsShadow ? theme.values.shadowOpacity : 0),
                radius: showsShadow ? theme.values.shadowRadius : 0,
                y: showsShadow ? 3 : 0
            )
    }

    @ViewBuilder
    private var base: some View {
        switch theme.values.material {
        case .none:
            shape.fill(theme.background)
        case .liquidGlass:
            #if compiler(>=6.2)
            // Built with the macOS 26 SDK or newer: use system Liquid Glass where available.
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(theme.background), in: shape)
            } else {
                materialStack(.hudWindow, highlight: true)
            }
            #else
            materialStack(.hudWindow, highlight: true)
            #endif
        case .ultraThin:
            materialStack(.fullScreenUI, highlight: false)
        case .thin:
            materialStack(.hudWindow, highlight: false)
        case .regular:
            materialStack(.popover, highlight: false)
        case .thick:
            materialStack(.sidebar, highlight: false)
        }
    }

    private func materialStack(_ material: NSVisualEffectView.Material, highlight: Bool) -> some View {
        ZStack {
            VisualEffectBackground(material: material, isDark: theme.isDark)
            theme.background
            if highlight {
                LinearGradient(
                    colors: [.white.opacity(0.22), .white.opacity(0.02), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .clipShape(shape)
    }
}

/// Behind-window blur. SwiftUI materials blend within the window, which in a transparent
/// panel would blur nothing, so AppKit's view is used directly.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var isDark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}
