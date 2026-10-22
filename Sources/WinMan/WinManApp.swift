import AppKit
import Combine
import SwiftUI

/// Menu-bar-only application. There is intentionally no main window; the app
/// lives in the menu bar and exposes a Settings scene on demand.
@main
struct WinManApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
        } label: {
            Image(systemName: "rectangle.3.group")
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = WinManEngine()
    private let shortcuts = ShortcutManager()
    private var settingsObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Live entirely in the menu bar: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        let trusted = AccessibilityClient.shared.isTrusted
        Log.write("launched trusted=\(trusted) pid=\(ProcessInfo.processInfo.processIdentifier)")

        // Route hot-key presses to the engine on the main thread.
        shortcuts.onHotKey = { [weak self] direction in
            Log.write("hotkey received: \(direction)")
            self?.engine.handle(direction)
        }

        registerShortcuts()

        // Re-register immediately whenever the modifier or per-arrow toggles
        // change, so new shortcuts take effect without relaunching.
        settingsObserver = SettingsModel.shared.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the change; defer to read new values.
            DispatchQueue.main.async { self?.registerShortcuts() }
        }

        // Prompt for Accessibility on first launch (no-ops if already trusted).
        if !trusted {
            AccessibilityClient.shared.requestTrust()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcuts.unregisterAll()
    }

    private func registerShortcuts() {
        let s = SettingsModel.shared
        guard s.isEnabled else {
            shortcuts.unregisterAll()
            Log.write("shortcuts unregistered (manager disabled)")
            return
        }
        let failed = shortcuts.register(modifier: s.modifier, enabledArrows: s.enabledArrows)
        Log.write("registered=\(shortcuts.registered) failed=\(failed) modifier=\(s.modifier.rawValue)")
        if !failed.isEmpty {
            NSLog("WinMan: failed to register shortcuts (conflict): \(failed)")
        }
    }
}

/// Tiny file logger so we can diagnose "inputs do nothing" without a debugger.
enum Log {
    static let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("winman.log")

    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
        NSLog("[winman] %@", message)
    }
}
