import ServiceManagement

enum LaunchAtLoginHelper {
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                fputs("[LaunchAtLogin] Failed to \(enabled ? "register" : "unregister"): \(error)\n", stderr)
                // Reconcile settings with actual state on failure
                reconcile()
            }
        }
    }

    /// Sync UserDefaults with actual SMAppService status
    static func reconcile() {
        if #available(macOS 13.0, *) {
            let actuallyEnabled = SMAppService.mainApp.status == .enabled
            if AppSettings.shared.launchAtLogin != actuallyEnabled {
                AppSettings.shared.launchAtLogin = actuallyEnabled
            }
        }
    }
}
