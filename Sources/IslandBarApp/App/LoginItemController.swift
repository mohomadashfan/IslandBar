import Observation
import ServiceManagement

/// Wraps `SMAppService.mainApp`. Login-item state is owned by macOS, not by our settings file,
/// so it is always read back from the system rather than persisted.
@MainActor
@Observable
final class LoginItemController {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastErrorMessage: String?

    init() {
        refresh()
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        guard AppInfo.isRunningFromAppBundle else {
            lastErrorMessage = "Launch at login is only available when running the bundled IslandBar.app."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
