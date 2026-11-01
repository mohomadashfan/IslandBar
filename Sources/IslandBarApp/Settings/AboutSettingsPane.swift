import AppKit
import IslandCore
import SwiftUI

struct AboutSettingsPane: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text("IslandBar").font(.title.bold())
            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .foregroundStyle(.secondary)

            Text("An open-source Dynamic Island–style utility for macOS.\nNo accounts, no telemetry, no analytics. Everything stays on this Mac.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Button("Show Data Folder in Finder") {
                let folder = AppPaths.applicationSupportDirectory()
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
            .padding(.top, 6)

            Text("Released under the MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
