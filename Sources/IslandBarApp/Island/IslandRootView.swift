import IslandCore
import IslandDesign
import IslandWindows
import SwiftUI
import UniformTypeIdentifiers

/// Root of each island panel. The island hangs from the top centre of the panel; the panel itself
/// is resized around it by `IslandWindowController`.
struct IslandRootView: View {
    let model: IslandViewModel
    let presenter: IslandPresenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: FeatureID?

    var body: some View {
        let settings = presenter.settings.settings
        let layout = settings.appearance.layout
        let mode = presenter.contentMode(for: model)
        let request = presenter.frameRequest(for: model)
        let anchor = IslandGeometry.anchor(for: model.display, settings: settings.displays)
        let theme = IslandTheme(settings.appearance)
        let animations = IslandAnimations(settings: settings.animation, reduceMotion: reduceMotion)
        let shape = Self.shape(mode: mode, height: request.size.height, attached: anchor.isAttachedToTop, layout: layout)
        let metrics = IslandMetrics(
            notchWidth: model.display.notchRect?.width ?? 0,
            compactHeight: model.display.notchRect?.height ?? CGFloat(layout.virtualHeight),
            earInset: anchor.isAttachedToTop ? Self.earRadius : 0,
            wingWidth: CGFloat(layout.wingWidth),
            islandWidth: request.size.width
        )
        let hidden = mode == .idle && !model.display.hasNotch && settings.displays.hideVirtualIslandWhenIdle

        ZStack(alignment: .top) {
            IslandSurface(shape: shape, showsShadow: mode == .expanded || mode == .banner)
            IslandContentView(mode: mode, presenter: presenter, selection: $selection, metrics: metrics)
                .clipShape(shape)
        }
        .frame(width: request.size.width, height: request.size.height)
        .contentShape(shape)
        .opacity(hidden ? 0 : 1)
        .simultaneousGesture(TapGesture().onEnded { handleTap(mode: mode) })
        .padding(.top, anchor.isAttachedToTop ? 0 : request.shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.islandTheme, theme)
        .environment(\.islandAnimations, animations)
        .environment(\.islandIsDropTargeted, model.isDragTargeted)
        .environment(\.colorScheme, theme.colorScheme)
        .animation(Self.animation(for: mode, animations), value: mode)
        .onDrop(of: [.fileURL], isTargeted: dropTargetBinding, perform: handleDrop)
        .onChange(of: presenter.pageRequest?.token) { _, _ in
            if let id = presenter.pageRequest?.id { selection = id }
        }
        .onChange(of: model.isDragTargeted) { _, targeted in
            if targeted { selection = .shelf }
        }
        .onChange(of: model.presentation) { old, new in
            if new.isExpanded, !old.isExpanded, selection == nil || !isVisible(selection) {
                selection = presenter.liveModule?.id ?? presenter.visibleModules.first?.id
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("IslandBar")
    }

    static let earRadius: CGFloat = 6

    static func shape(mode: IslandContentMode, height: CGFloat, attached: Bool, layout: LayoutSettings) -> IslandShape {
        let large = mode == .expanded || mode == .banner
        if attached {
            let radius = CGFloat(large ? layout.cornerRadius : layout.compactCornerRadius)
            return IslandShape(bottomRadius: radius, earRadius: earRadius)
        }
        let radius = large ? CGFloat(layout.cornerRadius) : height / 2
        return IslandShape(bottomRadius: radius, earRadius: 0, topRadius: radius)
    }

    static func animation(for mode: IslandContentMode, _ animations: IslandAnimations) -> Animation {
        switch mode {
        case .expanded: animations.expand
        case .banner: animations.notificationArrival
        case .idle, .liveActivity: animations.collapse
        }
    }

    private func isVisible(_ id: FeatureID?) -> Bool {
        presenter.visibleModules.contains { $0.id == id }
    }

    private func handleTap(mode: IslandContentMode) {
        if mode == .banner, let source = presenter.activity.current?.source {
            selection = presenter.featureID(for: source)
            presenter.activity.dismissCurrent()
        }
        model.send(.clicked)
    }

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { model.isDragTargeted },
            set: { model.setDragTargeted($0 && presenter.dropTarget != nil) }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let target = presenter.dropTarget else { return false }
        let accepted = target.acceptDrop(of: providers)
        model.send(.dropCompleted)
        return accepted
    }
}

struct IslandMetrics {
    var notchWidth: CGFloat
    var compactHeight: CGFloat
    var earInset: CGFloat
    var wingWidth: CGFloat
    var islandWidth: CGFloat
}
