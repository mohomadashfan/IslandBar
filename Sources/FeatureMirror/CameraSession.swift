@preconcurrency import AVFoundation
import Foundation

public struct CameraInfo: Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
}

enum MirrorError: Error, Equatable {
    case noCamera
    case cannotUseCamera(String)
}

/// Owns the `AVCaptureSession`. All configuration and start/stop calls run on a private serial
/// queue, as AVFoundation recommends, so starting the camera never blocks the UI.
final class CameraSession: @unchecked Sendable {
    // Accessed from the main thread only to attach a preview layer; mutated on `queue`.
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.github.islandbar.mirror.session")

    static func availableCameras() -> [CameraInfo] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.map { CameraInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Starts capturing from `cameraID` (or the default camera). Calls back with the camera name.
    func start(cameraID: String?, completion: @escaping @Sendable (Result<String, MirrorError>) -> Void) {
        queue.async { [session] in
            let device = cameraID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
            guard let device else {
                completion(.failure(.noCamera))
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                for existing in session.inputs {
                    session.removeInput(existing)
                }
                // A small preview does not need full resolution; this keeps CPU use low.
                if session.canSetSessionPreset(.medium) {
                    session.sessionPreset = .medium
                }
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    completion(.failure(.cannotUseCamera("The camera is not available.")))
                    return
                }
                session.addInput(input)
                session.commitConfiguration()
                if !session.isRunning {
                    session.startRunning()
                }
                completion(.success(device.localizedName))
            } catch {
                completion(.failure(.cannotUseCamera(error.localizedDescription)))
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            session.commitConfiguration()
        }
    }
}
