@preconcurrency import AVFoundation
import IslandDesign
import SwiftUI

struct MirrorExpandedView: View {
    let module: MirrorModule

    @State private var token = UUID()
    @Environment(\.islandTheme) private var theme

    var body: some View {
        HStack(spacing: theme.padding) {
            preview
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.fill, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text("Mirror").font(theme.headlineFont).foregroundStyle(theme.primary)
                Text(statusText)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { module.viewAppeared(token) }
        .onDisappear { module.viewDisappeared(token) }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(theme.fill)
            if module.owner == token, case .running = module.state {
                CameraPreview(session: module.camera.session)
                    .scaleEffect(x: module.settings.mirrorImage ? -1 : 1, y: 1)
                    .transition(.opacity)
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 26))
                    .foregroundStyle(theme.tertiary)
                if module.state == .starting, module.owner == token {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 4) {
            if module.authorization == .denied || module.authorization == .restricted {
                IslandPillButton("Allow Camera…", symbol: "lock") { MirrorModule.openPrivacySettings() }
            } else if module.owner != token {
                EmptyView()
            } else if module.isRunning {
                IslandPillButton("Stop", symbol: "stop.fill") { module.stop() }
                IslandIconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", size: 11, help: "Flip horizontally") {
                    module.toggleMirroring()
                }
                if module.cameras.count > 1 {
                    IslandIconButton("arrow.triangle.2.circlepath.camera", size: 11, help: "Switch camera") { module.switchCamera() }
                }
            } else {
                IslandPillButton("Turn On Camera", symbol: "video.fill") { module.start(for: token) }
            }
        }
    }

    private var placeholderSymbol: String {
        module.authorization == .denied || module.authorization == .restricted ? "video.slash" : "person.crop.square"
    }

    private var statusText: String {
        if module.owner != token { return "Mirror is open on another display." }
        if module.authorization == .denied || module.authorization == .restricted {
            return "Camera access is off for IslandBar. Allow it in System Settings › Privacy & Security › Camera."
        }
        switch module.state {
        case .off:
            return module.authorization == .notDetermined
                ? "macOS will ask for camera access the first time."
                : "The camera is off. It turns off again when the island closes."
        case .starting: return "Starting camera…"
        case .running(let name): return name
        case .failed(let message): return message
        }
    }
}

/// Hosts an `AVCaptureVideoPreviewLayer` for the shared session.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }

    static func dismantleNSView(_ view: PreviewView, coordinator: ()) {
        view.previewLayer.session = nil
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer = previewLayer
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }
    }
}
