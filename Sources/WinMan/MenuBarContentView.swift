import AppKit
import SwiftUI
import WinManCore

/// The dropdown shown when the menu-bar icon is clicked. Mirrors the layout
/// described in the requirements.
struct MenuBarContentView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Enabled toggle with a checkmark, matching the reference menu.
        Toggle(isOn: $settings.isEnabled) {
            Text("Enabled")
        }
        .toggleStyle(.checkbox)

        Divider()

        Text("Shortcuts: \(settings.shortcutDisplay) Arrow")
            .font(.caption)
            .foregroundStyle(.secondary)

        shortcutRow(label: "Snap Left", arrow: .left)
        shortcutRow(label: "Snap Right", arrow: .right)
        shortcutRow(label: "Maximize", arrow: .up)
        shortcutRow(label: "Minimize", arrow: .down)

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }

        Button("Accessibility Permissions…") {
            AccessibilityClient.shared.openAccessibilitySettings()
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// A single shortcut row. Uses a real key equivalent (like the Quit item),
    /// so macOS renders the combination natively, right-aligned, and updates it
    /// when the modifier changes in Settings.
    private func shortcutRow(label: String, arrow: Direction) -> some View {
        Button {
            // Informational row; the global hot keys are handled by Carbon.
        } label: {
            Text(label)
        }
        .keyboardShortcut(keyEquivalent(for: arrow), modifiers: shortcutModifiers)
        .disabled(!settings.enabledArrows.isEnabled(arrow))
    }

    private var shortcutModifiers: EventModifiers {
        var modifiers: EventModifiers = [.command]
        switch settings.modifier {
        case .option: modifiers.insert(.option)
        case .control: modifiers.insert(.control)
        case .shift: modifiers.insert(.shift)
        }
        return modifiers
    }

    private func keyEquivalent(for arrow: Direction) -> KeyEquivalent {
        switch arrow {
        case .left: return .leftArrow
        case .right: return .rightArrow
        case .up: return .upArrow
        case .down: return .downArrow
        }
    }
}
