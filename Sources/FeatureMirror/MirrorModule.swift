@preconcurrency import AVFoundation
import AppKit
import IslandCore
import IslandDesign
import Observation
import SwiftUI

/// A quick front-camera preview ("mirror"), for checking yourself before a call.
///
/// The camera only runs while the Mirror page is on screen and the user has started it (or
/// opted into starting it automatically). Collapsing the island always turns it off.
@MainActor
@Observable
public final class MirrorModule: IslandModule {
    public let id = FeatureID.mirror
    public let displayName = "Mirror"
    public let symbolName = "person.crop.square"

    public enum State: Equatable {
        case off
        case starting
        case running(cameraName: String)
        case failed(String)
    }

    public private(set) var state = State.off
    public private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    public private(set) var cameras: [CameraInfo] = []
    public private(set) var settings = MirrorSettings()
    /// The view (one per display) that currently owns the preview.
    public private(set) var owner: UUID?

    @ObservationIgnored let camera = CameraSession()
    @ObservationIgnored private var settingsStore: SettingsStore?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var visibleViews: Set<UUID> = []

    public init(settings: SettingsStore? = nil) {
        self.settingsStore = settings
    }

    /// Camera use needs `NSCameraUsageDescription`, which only the bundled app has.
    public static var isAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }

    // MARK: IslandModule

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.mirror.isEnabled
    }

    public func apply(_ settings: AppSettings) {
        let previousCamera = self.settings.cameraID
        self.settings = settings.mirror
        if previousCamera != settings.mirror.cameraID, isRunning, let owner {
            start(for: owner)
        }
    }

    public func activate() {
        refreshCameras()
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.camerasChanged() }
            })
        }
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: camera.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.camera.stop()
                self?.state = .failed("The camera stopped unexpectedly.")
            }
        })
    }

    public func deactivate() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        stop()
        visibleViews.removeAll()
        owner = nil
    }

    public func makeExpandedView() -> AnyView { AnyView(MirrorExpandedView(module: self)) }

    // MARK: Control

    public var isRunning: Bool {
        if case .running = state { return true }
        return state == .starting
    }

    func viewAppeared(_ token: UUID) {
        visibleViews.insert(token)
        if owner == nil {
            owner = token
        }
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if settings.startAutomatically, authorization == .authorized, owner == token, !isRunning {
            start(for: token)
        }
    }

    func viewDisappeared(_ token: UUID) {
        visibleViews.remove(token)
        guard owner == token else { return }
        stop()
        owner = visibleViews.first
    }

    /// Starts the preview in the view identified by `token`, asking for camera access first if
    /// it has not been decided yet.
    func start(for token: UUID) {
        guard Self.isAvailable else {
            state = .failed("The camera is only available in the bundled IslandBar.app.")
            return
        }
        owner = token
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            state = .starting
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                self.authorization = AVCaptureDevice.authorizationStatus(for: .video)
                // The page may have closed while the prompt was up.
                guard granted, self.owner == token, self.visibleViews.contains(token) else {
                    if self.state == .starting { self.state = .off }
                    return
                }
                self.startSession()
            }
        case .denied, .restricted:
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
            state = .off
        @unknown default:
            state = .off
        }
    }

    public func stop() {
        guard state != .off else { return }
        camera.stop()
        state = .off
    }

    func toggleMirroring() {
        settingsStore?.update { $0.mirror.mirrorImage.toggle() }
    }

    func switchCamera() {
        guard cameras.count > 1 else { return }
        let currentIndex = cameras.firstIndex { $0.id == settings.cameraID } ?? 0
        let next = cameras[(currentIndex + 1) % cameras.count]
        settingsStore?.update { $0.mirror.cameraID = next.id }
    }

    public static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    private func startSession() {
        state = .starting
        camera.start(cameraID: settings.cameraID) { result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Stopped (or page closed) while the camera was starting up.
                guard self.state == .starting else {
                    self.camera.stop()
                    return
                }
                switch result {
                case .success(let name): self.state = .running(cameraName: name)
                case .failure(.noCamera): self.state = .failed("No camera found.")
                case .failure(.cannotUseCamera(let message)): self.state = .failed(message)
                }
            }
        }
    }

    private func refreshCameras() {
        cameras = CameraSession.availableCameras()
    }

    private func camerasChanged() {
        refreshCameras()
        if isRunning, let id = settings.cameraID, !cameras.contains(where: { $0.id == id }) {
            stop()
            state = .failed("The selected camera was disconnected.")
        }
    }
}
