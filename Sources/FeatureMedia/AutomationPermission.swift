import AppKit
import CoreServices

/// State of macOS's per-app Automation (Apple Events) permission.
public enum AutomationPermission: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
    /// The target is not running, so macOS cannot report a status yet.
    case targetNotRunning
    case unknown(Int32)

    public var displayName: String {
        switch self {
        case .granted: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not requested"
        case .targetNotRunning: "App not running"
        case .unknown(let code): "Unknown (\(code))"
        }
    }

    /// Queries (and optionally prompts for) permission to send Apple Events to `bundleIdentifier`.
    ///
    /// `AEDeterminePermissionToAutomateTarget` may block while the consent dialog is shown, so
    /// this runs off the main actor.
    public static func determine(for bundleIdentifier: String, askUserIfNeeded: Bool) async -> AutomationPermission {
        await Task.detached(priority: .userInitiated) {
            check(bundleIdentifier, ask: askUserIfNeeded)
        }.value
    }

    private static func check(_ bundleIdentifier: String, ask: Bool) -> AutomationPermission {
        var address = AEAddressDesc()
        let bytes = Array(bundleIdentifier.utf8)
        let created = bytes.withUnsafeBytes {
            AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count, &address)
        }
        guard created == noErr else { return .unknown(Int32(created)) }
        defer { AEDisposeDesc(&address) }

        let status = AEDeterminePermissionToAutomateTarget(
            &address, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask
        )
        switch Int(status) {
        case Int(noErr): return .granted
        case errAEEventNotPermitted: return .denied
        case -1744: return .notDetermined  // errAEEventWouldRequireUserConsent
        case procNotFound: return .targetNotRunning
        default: return .unknown(status)
        }
    }

    public static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
