import IslandCore
import IslandDesign
import IslandWindows
import SwiftUI

struct IslandContentView: View {
    let mode: IslandContentMode
    let presenter: IslandPresenter
    @Binding var selection: FeatureID?
    let metrics: IslandMetrics

    @Environment(\.islandAnimations) private var animations

    var body: some View {
        Group {
            switch mode {
            case .idle:
                Color.clear
            case .liveActivity:
                if let module = presenter.liveModule {
                    CompactActivityView(module: module, metrics: metrics)
                        .id(module.id)
                }
            case .banner:
                if let event = presenter.activity.current {
                    BannerView(event: event, metrics: metrics)
                        .id(event.id)
                }
            case .expanded:
                ExpandedIslandView(presenter: presenter, selection: $selection, metrics: metrics)
            }
        }
        .transition(animations.contentTransition)
        .id(mode)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Live activity: leading content in the left wing, trailing content in the right wing,
/// the notch (if any) in between.
struct CompactActivityView: View {
    let module: any IslandModule
    let metrics: IslandMetrics

    var body: some View {
        let slot = max(metrics.wingWidth - 14, 20)
        HStack(spacing: 0) {
            module.makeCompactLeading()
                .frame(width: slot, alignment: .leading)
            Spacer(minLength: 0)
            module.makeCompactTrailing()
                .frame(width: slot, alignment: .trailing)
        }
        .padding(.horizontal, metrics.earInset + 10)
        .frame(height: metrics.compactHeight)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct BannerView: View {
    let event: ActivityEvent
    let metrics: IslandMetrics

    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if metrics.notchWidth > 0 {
                Color.clear.frame(height: metrics.compactHeight)
            }
            HStack(spacing: 10) {
                Image(systemName: event.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: event.id)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(theme.headlineFont)
                        .foregroundStyle(theme.primary)
                    if let subtitle = event.subtitle {
                        Text(subtitle)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18 + metrics.earInset)
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch event.style {
        case .info: theme.accent
        case .success: .green
        case .warning: .orange
        case .failure: .red
        }
    }
}

struct ExpandedIslandView: View {
    let presenter: IslandPresenter
    @Binding var selection: FeatureID?
    let metrics: IslandMetrics

    @Environment(\.islandTheme) private var theme
    @Environment(\.islandAnimations) private var animations
    @Namespace private var dockSelection

    static let dockHeight: CGFloat = 30

    var body: some View {
        let modules = presenter.visibleModules
        let current = modules.first { $0.id == selection } ?? modules.first

        VStack(spacing: 0) {
            header(current: current)
                .frame(height: max(metrics.compactHeight, 30))

            ZStack {
                if let current {
                    current.makeExpandedView()
                        .id(current.id)
                        .transition(animations.contentTransition)
                } else {
                    IslandEmptyState(symbol: "square.dashed", title: "No modules enabled", message: "Turn modules on in Settings.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, theme.padding)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .animation(animations.content, value: current?.id)

            if modules.count > 1 {
                dock(modules: modules, current: current?.id)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, metrics.earInset)
    }

    /// Page title on the left of the notch; quick actions and Settings on the right.
    private func header(current: (any IslandModule)?) -> some View {
        HStack(spacing: 2) {
            if let current {
                Label {
                    Text(current.displayName)
                } icon: {
                    Image(systemName: current.symbolName)
                }
                .font(theme.font(12, weight: .semibold))
                .foregroundStyle(theme.primary)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(animations.content, value: current.id)
                .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: metrics.notchWidth > 0 ? metrics.notchWidth + 12 : 8)
            ForEach(presenter.headerAccessories, id: \.id) { $0.view }
            IslandIconButton("gearshape", size: 11, help: "IslandBar Settings") { presenter.openSettings() }
        }
        .padding(.leading, theme.padding)
        .padding(.trailing, theme.padding - 6)
    }

    /// Page switcher along the bottom edge, clear of the notch, so every page is one click away.
    private func dock(modules: [any IslandModule], current: FeatureID?) -> some View {
        HStack(spacing: 2) {
            ForEach(modules.map(\.id), id: \.self) { id in
                if let module = modules.first(where: { $0.id == id }) {
                    dockButton(module, isSelected: id == current)
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.fill))
        .frame(height: Self.dockHeight)
        .animation(animations.content, value: current)
    }

    private func dockButton(_ module: any IslandModule, isSelected: Bool) -> some View {
        Button {
            selection = module.id
        } label: {
            Image(systemName: module.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 22)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(theme.primary.opacity(0.16))
                            .matchedGeometryEffect(id: "selection", in: dockSelection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? theme.primary : theme.secondary)
        .help(module.displayName)
        .accessibilityLabel(module.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
