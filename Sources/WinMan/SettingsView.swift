import AppKit
import SwiftUI

/// Native macOS Settings window with three sections: keyboard shortcuts,
/// window behavior, and system (Accessibility permission status).
struct SettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @State private var trusted = AccessibilityClient.shared.isTrusted

    var body: some View {
        TabView {
            shortcutsTab
                .tabItem { Label("Keyboard Shortcuts", systemImage: "keyboard") }
            behaviorTab
                .tabItem { Label("Window Behavior", systemImage: "macwindow") }
            systemTab
                .tabItem { Label("System", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 420)
        .onAppear { refreshTrust() }
    }

    // MARK: - Keyboard shortcuts

    private var shortcutsTab: some View {
        Form {
            Section {
                Toggle("Enable window manager", isOn: $settings.isEnabled)

                Picker("Additional modifier", selection: $settings.modifier) {
                    ForEach(ExtraModifier.allCases) { mod in
                        Text(mod.displayName).tag(mod)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Complete combination: \(settings.shortcutDisplay) + Arrow")
                    .foregroundStyle(.secondary)
            }

            Section("Enable individual shortcuts") {
                Toggle("Snap Left   \(settings.shortcutDisplay)←", isOn: $settings.enabledArrows.left)
                Toggle("Snap Right  \(settings.shortcutDisplay)→", isOn: $settings.enabledArrows.right)
                Toggle("Maximize    \(settings.shortcutDisplay)↑", isOn: $settings.enabledArrows.up)
                Toggle("Minimize    \(settings.shortcutDisplay)↓", isOn: $settings.enabledArrows.down)
            }

            Section {
                Text("Shortcuts work globally while any application is focused. If a combination is already claimed by macOS or another app, it may not fire — try a different modifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Window behavior

    private var behaviorTab: some View {
        Form {
            Section("Snapping") {
                VStack(alignment: .leading) {
                    Text("Default snap width: \(Int(settings.snapRatio * 100))%")
                    Slider(value: $settings.snapRatio, in: 0.25...0.9, step: 0.05)
                }

                Stepper(value: $settings.snapGap, in: 0...40, step: 4) {
                    Text("Gap between snapped windows: \(Int(settings.snapGap)) pt")
                }
            }

            Section("Maximize & Restore") {
                Toggle("Maximize fills usable area (keeps menu bar & Dock accessible)",
                       isOn: $settings.maximizeUsesAvailableFrame)
                Toggle("Restore returns to original monitor when available",
                       isOn: $settings.restorePreservesMonitor)
            }

            Section("Multi-monitor") {
                Toggle("Cycle snapped windows across adjacent displays",
                       isOn: $settings.cycleAcrossDisplays)
                Text("When enabled, pressing the same direction again on a snapped window moves it to the adjacent display in that direction, preserving the snapped side.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - System

    private var systemTab: some View {
        Form {
            Section("Accessibility Permission") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(trusted ? .green : .red)
                    Text(trusted ? "Accessibility access granted" : "Accessibility access required")
                    Spacer()
                    Button("Refresh") { refreshTrust() }
                }

                Button("Open Privacy & Security Settings…") {
                    AccessibilityClient.shared.openAccessibilitySettings()
                }

                Group {
                    Text("How to grant access:")
                        .fontWeight(.semibold)
                    Text("1. Click the button above to open System Settings → Privacy & Security → Accessibility.")
                    Text("2. Find “WinMan” in the list and turn it on. If it is not listed, drag the app from Finder into the list.")
                    Text("3. Return here and click Refresh. If the app was running when permission changed, quit and relaunch it.")
                    Text("How to revoke: turn the toggle off in the same list, or click “−” to remove the app.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func refreshTrust() {
        trusted = AccessibilityClient.shared.isTrusted
    }
}
