import AppKit
import ApplicationServices
import CoreGraphics
import WinManCore

/// Wrapper around the macOS Accessibility (AX) API for reading and writing
/// window geometry, minimized state, and full-screen state.
///
/// macOS provides no universal public API for managing other apps' windows;
/// the Accessibility API is the supported mechanism, but it is best-effort:
/// some applications (e.g. certain Java, Electron, or game apps) do not expose
/// standard window controls and may ignore or partially honour requests.
final class AccessibilityClient {

    static let shared = AccessibilityClient()
    private init() {}

    // MARK: - Permission

    /// True when the process is trusted for Accessibility (can control windows).
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user (once per install) to grant Accessibility permission.
    /// Returns the current trust state after the prompt.
    @discardableResult
    func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Privacy & Security > Accessibility pane in System Settings.
    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Focused window

    /// The AX element for the currently focused window of the frontmost app,
    /// or nil when unavailable (no trusted process, non-standard app, dialog).
    ///
    /// Minimizing a window usually strips the app of its key window entirely,
    /// which would make "restore from minimized" unreachable. So when the
    /// focused-window attribute comes up empty, fall back to the app's
    /// minimized window — the only window a frontmost, key-less app is
    /// meaningfully pointing at. Every other key is a no-op for minimized
    /// windows, so this fallback can never act on a window behind your back.
    func focusedWindow() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let app = AXUIElementCreateApplication(pid)

        if let element = windowAttribute(kAXFocusedWindowAttribute, of: app),
           isWindowLike(element) {
            return element
        }

        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
            let windows = windowsValue as? [AXUIElement]
        else { return nil }
        return windows.first(where: isMinimized)
    }

    /// Reads a window element off an application element, if present.
    private func windowAttribute(_ name: String, of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
    }

    /// Whether an element has a window-like role (window, dialog, or sheet).
    /// Unreadable roles are accepted, mirroring AX's best-effort nature.
    private func isWindowLike(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleValue) == .success,
            let role = roleValue as? String
        else { return true }
        return ["AXWindow", "AXDialog", "AXSheet"].contains(role)
    }

    /// Whether the given window is currently minimized.
    func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, kAXMinimizedAttribute as CFString, &value) == .success,
            let value else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }

    /// Whether the given window is in native full-screen mode.
    func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, "AXFullScreen" as CFString, &value) == .success,
            let value else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }

    // MARK: - Geometry

    /// Height of the primary display. AppKit and CoreGraphics share the same
    /// global space except that Y is mirrored about this height: AX reads and
    /// writes top-left origin, everything above the AX layer uses bottom-left.
    private var primaryHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
    }

    /// Reads the window's frame in AppKit global coordinates (bottom-left
    /// origin), converting from the AX top-left origin space.
    func frame(of window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                window, kAXPositionAttribute as CFString, &posValue) == .success,
            AXUIElementCopyAttributeValue(
                window, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let posValue, let sizeValue
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        let axFrame = CGRect(origin: point, size: size)
        return ScreenSpace.flip(axFrame, primaryHeight: primaryHeight)
    }

    /// Writes the window's frame, given in AppKit global coordinates
    /// (bottom-left origin; flipped to the AX space here). Sets size first,
    /// then position, and re-asserts size to work around apps that adjust one
    /// attribute when the other changes.
    /// Returns true when both attributes accepted the new values.
    @discardableResult
    func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        let axFrame = ScreenSpace.flip(frame, primaryHeight: primaryHeight)
        var size = axFrame.size
        var point = axFrame.origin
        guard
            let sizeAX = AXValueCreate(.cgSize, &size),
            let posAX = AXValueCreate(.cgPoint, &point)
        else { return false }

        let sizeOK = AXUIElementSetAttributeValue(
            window, kAXSizeAttribute as CFString, sizeAX) == .success
        let posOK = AXUIElementSetAttributeValue(
            window, kAXPositionAttribute as CFString, posAX) == .success

        // Re-assert size: some apps clamp position and change size in response.
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeAX)
        return sizeOK && posOK
    }

    /// Minimizes or un-minimizes the window.
    @discardableResult
    func setMinimized(_ minimized: Bool, of window: AXUIElement) -> Bool {
        let value = NSNumber(value: minimized)
        return AXUIElementSetAttributeValue(
            window, kAXMinimizedAttribute as CFString, value) == .success
    }

    /// Raises the window and makes its app active (needed before restoring a
    /// minimized window so the frame write is honoured).
    func raise(window: AXUIElement) {
        AXUIElementSetAttributeValue(
            window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if let pid = pid(of: window) {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    /// Best-effort process id for a window element.
    func pid(of window: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return pid
    }
}
