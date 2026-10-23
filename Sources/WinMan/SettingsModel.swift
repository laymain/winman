import Combine
import Foundation
import WinManCore

/// The configurable modifier used together with ⌘ and an arrow key.
public enum ExtraModifier: String, CaseIterable, Identifiable, Codable {
    case option
    case control
    case shift

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .option: return "Option (⌥)"
        case .control: return "Control (⌃)"
        case .shift: return "Shift (⇧)"
        }
    }
}

/// A single enabled/disabled flag for one of the four arrows.
public struct ShortcutAvailability: Equatable, Codable {
    public var left: Bool
    public var right: Bool
    public var up: Bool
    public var down: Bool

    public init(left: Bool = true, right: Bool = true, up: Bool = true, down: Bool = true) {
        self.left = left
        self.right = right
        self.up = up
        self.down = down
    }

    func isEnabled(_ direction: Direction) -> Bool {
        switch direction {
        case .left: return left
        case .right: return right
        case .up: return up
        case .down: return down
        }
    }
}

/// User-configurable settings, persisted to UserDefaults.
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    @Published var isEnabled: Bool { didSet { persist() } }
    @Published var modifier: ExtraModifier { didSet { persist() } }
    @Published var enabledArrows: ShortcutAvailability { didSet { persist() } }
    @Published var snapRatio: Double { didSet { persist() } }     // 0.25 ... 0.9, default 0.5
    @Published var snapGap: Double { didSet { persist() } }       // points, default 0
    @Published var maximizeUsesAvailableFrame: Bool { didSet { persist() } }
    @Published var restorePreservesMonitor: Bool { didSet { persist() } }
    @Published var cycleAcrossDisplays: Bool { didSet { persist() } }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let enabled = "wm.enabled"
        static let modifier = "wm.modifier"
        static let arrows = "wm.arrows"
        static let snapRatio = "wm.snapRatio"
        static let snapGap = "wm.snapGap"
        static let maximizeAvailable = "wm.maximizeUsesAvailableFrame"
        static let restorePreservesMonitor = "wm.restorePreservesMonitor"
        static let cycleAcrossDisplays = "wm.cycleAcrossDisplays"
    }

    private init() {
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.modifier: ExtraModifier.option.rawValue,
            Keys.snapRatio: 0.5,
            Keys.snapGap: 0.0,
            Keys.maximizeAvailable: true,
            Keys.restorePreservesMonitor: false,
            Keys.cycleAcrossDisplays: true,
        ])
        isEnabled = defaults.bool(forKey: Keys.enabled)
        modifier = ExtraModifier(rawValue: defaults.string(forKey: Keys.modifier) ?? "") ?? .option
        if let data = defaults.data(forKey: Keys.arrows),
           let decoded = try? JSONDecoder().decode(ShortcutAvailability.self, from: data) {
            enabledArrows = decoded
        } else {
            enabledArrows = ShortcutAvailability()
        }
        snapRatio = defaults.double(forKey: Keys.snapRatio)
        snapGap = defaults.double(forKey: Keys.snapGap)
        maximizeUsesAvailableFrame = defaults.bool(forKey: Keys.maximizeAvailable)
        restorePreservesMonitor = defaults.bool(forKey: Keys.restorePreservesMonitor)
        cycleAcrossDisplays = defaults.bool(forKey: Keys.cycleAcrossDisplays)
    }

    private func persist() {
        defaults.set(isEnabled, forKey: Keys.enabled)
        defaults.set(modifier.rawValue, forKey: Keys.modifier)
        if let data = try? JSONEncoder().encode(enabledArrows) {
            defaults.set(data, forKey: Keys.arrows)
        }
        defaults.set(snapRatio, forKey: Keys.snapRatio)
        defaults.set(snapGap, forKey: Keys.snapGap)
        defaults.set(maximizeUsesAvailableFrame, forKey: Keys.maximizeAvailable)
        defaults.set(restorePreservesMonitor, forKey: Keys.restorePreservesMonitor)
        defaults.set(cycleAcrossDisplays, forKey: Keys.cycleAcrossDisplays)
    }

    /// The human-readable shortcut string, e.g. "⌘⌥" for arrows.
    var shortcutDisplay: String {
        switch modifier {
        case .option: return "⌘⌥"
        case .control: return "⌃⌘"
        case .shift: return "⇧⌘"
        }
    }
}
