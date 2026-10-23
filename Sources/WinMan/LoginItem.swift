import ServiceManagement

/// "Launch at login" through `SMAppService`.
///
/// The system is the source of truth: Settings mirrors
/// `SMAppService.mainApp.status` rather than persisting its own flag, so an
/// entry removed in System Settings shows up as off here as well.
enum LoginItem {

    /// Whether macOS will launch the app at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True while macOS is waiting for the user to approve the item in
    /// System Settings → General → Login Items.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters the app as a login item.
    /// Returns false on failure so the toggle can snap back to reality.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.write("login item \(enabled ? "registered" : "unregistered")")
            return true
        } catch {
            Log.write("login item \(enabled ? "register" : "unregister") failed: \(error)")
            return false
        }
    }
}
