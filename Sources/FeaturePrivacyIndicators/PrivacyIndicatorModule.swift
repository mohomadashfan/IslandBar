import AppKit
import IslandCore
import IslandDesign
import IslandPlatform
import Observation
import SwiftUI

/// Shows when a camera or microphone is in use, by any app.
@MainActor
@Observable
public final class PrivacyIndicatorModule: IslandModule {
    public let id = FeatureID.privacyIndicators
    public let displayName = "Camera & Mic"
    public let symbolName = "video"

    public private(set) var usage = CaptureUsage()
    public private(set) var settings = PrivacyIndicatorSettings()

    @ObservationIgnored private let activity: ActivityCenter
    @ObservationIgnored private let audio = AudioInputMonitor()
    @ObservationIgnored private let cameras = CameraMonitor()
    @ObservationIgnored private var evaluateTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = false

    public init(activity: ActivityCenter) {
        self.activity = activity
    }

    // MARK: IslandModule

    public var liveActivityPriority: Int? {
        guard settings.showLiveActivity, isVisiblyInUse else { return nil }
        return LiveActivityPriority.privacy
    }

    var showsCamera: Bool { settings.showCamera && usage.cameraInUse }
    var showsMicrophone: Bool { settings.showMicrophone && usage.microphoneInUse }
    var isVisiblyInUse: Bool { showsCamera || showsMicrophone }

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.privacyIndicators.isEnabled
            && (settings.privacyIndicators.showCamera || settings.privacyIndicators.showMicrophone)
    }

    public func apply(_ settings: AppSettings) {
        self.settings = settings.privacyIndicators
    }

    public func activate() {
        isActive = true
        audio.onChange = { [weak self] in self?.scheduleEvaluation() }
        cameras.onChange = { [weak self] in self?.scheduleEvaluation() }
        audio.start()
        cameras.start()
        // The state at launch is not news, so record it without announcing.
        usage = currentUsage()
    }

    public func deactivate() {
        isActive = false
        evaluateTask?.cancel()
        evaluateTask = nil
        audio.stop()
        cameras.stop()
        usage = CaptureUsage()
    }

    public func makeCompactLeading() -> AnyView { AnyView(PrivacyCompactLeading(module: self)) }
    public func makeCompactTrailing() -> AnyView { AnyView(PrivacyCompactTrailing(module: self)) }
    public func makeExpandedView() -> AnyView { AnyView(PrivacyExpandedView(module: self)) }

    // MARK: Evaluation

    /// Listener callbacks arrive in bursts (a call app starts several streams), so coalesce them.
    private func scheduleEvaluation() {
        evaluateTask?.cancel()
        evaluateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.isActive else { return }
            self.evaluate()
        }
    }

    private func evaluate() {
        let previous = usage
        let current = currentUsage()
        guard current != previous else { return }
        usage = current

        if settings.showCamera, current.cameraInUse, !previous.cameraInUse {
            activity.post(ActivityEvent(
                source: .privacy, style: .success, title: "Camera turned on",
                subtitle: current.activeCameras.joined(separator: ", "), symbolName: "video.fill"
            ))
        }
        let newApps = current.microphoneApps.filter { !previous.microphoneApps.contains($0) }
        if settings.showMicrophone, current.microphoneInUse, !previous.microphoneInUse || !newApps.isEmpty {
            activity.post(ActivityEvent(
                source: .privacy, style: .warning, title: "Microphone in use",
                subtitle: (newApps.isEmpty ? current.microphoneApps : newApps).joined(separator: ", ").nilIfEmpty,
                symbolName: "mic.fill"
            ))
        }
    }

    private func currentUsage() -> CaptureUsage {
        var usage = CaptureUsage()
        usage.activeCameras = cameras.activeCameraNames()
        usage.cameraInUse = !usage.activeCameras.isEmpty

        if let clients = audio.clients() {
            let capturing = CaptureAttribution.microphoneClients(clients, ownPID: ProcessInfo.processInfo.processIdentifier)
            usage.microphoneInUse = !capturing.isEmpty
            usage.microphoneApps = CaptureAttribution.displayNames(
                for: capturing,
                apps: RunningAppInfo.current(),
                nameForPID: { NSRunningApplication(processIdentifier: $0)?.localizedName }
            )
        } else {
            usage.canAttributeMicrophone = false
            usage.microphoneInUse = audio.anyInputDeviceRunning()
        }
        return usage
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Views

private let cameraColor = Color(red: 0.2, green: 0.85, blue: 0.4)
private let microphoneColor = Color(red: 1.0, green: 0.62, blue: 0.1)

struct PrivacyCompactLeading: View {
    let module: PrivacyIndicatorModule

    var body: some View {
        HStack(spacing: 5) {
            if module.showsCamera {
                Image(systemName: "video.fill").foregroundStyle(cameraColor)
            }
            if module.showsMicrophone {
                Image(systemName: "mic.fill").foregroundStyle(microphoneColor)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch (module.showsCamera, module.showsMicrophone) {
        case (true, true): "Camera and microphone in use"
        case (true, false): "Camera in use"
        default: "Microphone in use"
        }
    }
}

struct PrivacyCompactTrailing: View {
    let module: PrivacyIndicatorModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        Text(CaptureAttribution.summary(module.usage, showCamera: module.settings.showCamera, showMicrophone: module.settings.showMicrophone))
            .font(theme.font(11, weight: .semibold))
            .foregroundStyle(module.showsMicrophone ? microphoneColor : cameraColor)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

struct PrivacyExpandedView: View {
    let module: PrivacyIndicatorModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.settings.showCamera {
                row(symbol: "video.fill", color: cameraColor, title: "Camera",
                    inUse: module.usage.cameraInUse,
                    detail: module.usage.cameraInUse ? module.usage.activeCameras.joined(separator: ", ") : "Not in use")
            }
            if module.settings.showMicrophone {
                row(symbol: "mic.fill", color: microphoneColor, title: "Microphone",
                    inUse: module.usage.microphoneInUse,
                    detail: microphoneDetail)
            }
            Spacer(minLength: 0)
            Text("macOS does not reveal which app is using the camera.")
                .font(theme.font(10))
                .foregroundStyle(theme.tertiary)
        }
    }

    private var microphoneDetail: String {
        guard module.usage.microphoneInUse else { return "Not in use" }
        if !module.usage.canAttributeMicrophone { return "In use (app details need macOS 14.2 or later)" }
        return module.usage.microphoneApps.isEmpty ? "In use" : module.usage.microphoneApps.joined(separator: ", ")
    }

    private func row(symbol: String, color: Color, title: String, inUse: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(inUse ? color.opacity(0.22) : theme.fill)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(inUse ? color : theme.tertiary)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(theme.headlineFont).foregroundStyle(theme.primary)
                Text(detail).font(theme.captionFont).foregroundStyle(inUse ? theme.primary : theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if inUse {
                Circle().fill(color).frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
