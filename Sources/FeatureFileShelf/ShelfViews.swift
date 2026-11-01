import IslandDesign
import SwiftUI

struct ShelfExpandedView: View {
    let module: FileShelfModule

    @Environment(\.islandTheme) private var theme
    @Environment(\.islandIsDropTargeted) private var isDropTargeted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.items.isEmpty {
                IslandEmptyState(
                    symbol: "tray.and.arrow.down",
                    title: "Drop files here",
                    message: "Files stay where they are; the shelf only keeps a reference."
                )
            } else {
                header
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(module.items) { item in
                            ShelfTile(module: module, item: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.accent.opacity(0.08)))
            }
        }
        .onAppear { module.ensureThumbnails() }
    }

    private var header: some View {
        HStack {
            Text("\(module.items.count) item\(module.items.count == 1 ? "" : "s")")
                .font(theme.captionFont)
                .foregroundStyle(theme.secondary)
            if let error = module.lastError {
                Text(error).font(theme.captionFont).foregroundStyle(.orange)
            }
            Spacer()
            IslandPillButton("Copy All", symbol: "doc.on.doc") { module.copyToPasteboard(module.items) }
            IslandPillButton("Clear", symbol: "xmark") { module.removeAll() }
        }
    }
}

private struct ShelfTile: View {
    let module: FileShelfModule
    let item: ShelfItem

    @Environment(\.islandTheme) private var theme

    var body: some View {
        let isMissing = module.unavailable.contains(item.id)
        VStack(spacing: 4) {
            Image(nsImage: module.icon(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
                .opacity(isMissing ? 0.35 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if isMissing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                    }
                }
            Text(item.name)
                .font(theme.font(10))
                .foregroundStyle(theme.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 68)
        }
        .padding(6)
        .islandCard()
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) { module.open(item) }
        .onDrag { module.itemProvider(for: item) }
        .help(isMissing ? "\(item.path) is no longer available" : item.path)
        .contextMenu {
            Button("Open") { module.open(item) }.disabled(isMissing)
            Button("Show in Finder") { module.revealInFinder(item) }.disabled(isMissing)
            Button("Copy") { module.copyToPasteboard([item]) }.disabled(isMissing)
            Divider()
            Button("Remove from Shelf") { module.remove(item) }
        }
    }
}
