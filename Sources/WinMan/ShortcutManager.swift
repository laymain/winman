import AppKit
import Carbon
import CoreGraphics
import WinManCore

/// Registers global ⌘ + modifier + arrow hot keys using the Carbon
/// `RegisterEventHotKey` API.
///
/// This is the most reliable way to receive global shortcuts on macOS without
/// an event tap: the system consumes matching key events before they reach the
/// focused app, and registration is cheap and dependency-free. The alternative
/// (`NSEvent.addGlobalMonitorForEvents`) can only observe — not consume — events
/// and therefore would let the shortcut leak through to the frontmost app.
///
/// Note: Carbon modifier masks differ from `NSEvent.ModifierFlags`:
///   cmdKey = 0x100, shiftKey = 0x200, optionKey = 0x800, controlKey = 0x1000.
final class ShortcutManager {

    /// Invoked on the main thread when a registered hot key is pressed.
    var onHotKey: ((Direction) -> Void)?

    /// Hot keys currently registered successfully, keyed by direction.
    private(set) var registered: Set<Direction> = []

    private var hotKeyRefs: [Direction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var handlerInstalled = false

    /// Identifies our hot keys in the Carbon event. 'WINM'.
    private let signature: OSType = 0x57494E4D

    /// Stable numeric id per direction for the hot key ID.
    private func hotKeyId(for direction: Direction) -> UInt32 {
        switch direction {
        case .left: return 1
        case .right: return 2
        case .up: return 3
        case .down: return 4
        }
    }

    private func direction(for hotKeyId: UInt32) -> Direction? {
        switch hotKeyId {
        case 1: return .left
        case 2: return .right
        case 3: return .up
        case 4: return .down
        default: return nil
        }
    }

    // MARK: - Registration

    /// (Re)registers the four arrows for the given modifier.
    /// Unregisters any existing keys first to prevent duplicate registrations.
    /// Returns the set of directions that failed to register (conflicts).
    @discardableResult
    func register(modifier: ExtraModifier, enabledArrows: ShortcutAvailability) -> Set<Direction> {
        unregisterAll()
        installHandlerIfNeeded()

        var failed: Set<Direction> = []
        let modifiers = modifier.carbonMask | UInt32(cmdKey)

        for direction in Direction.allCases {
            guard enabledArrows.isEnabled(direction) else { continue }
            let keyCode = Self.keyCode(for: direction)
            var hotKeyRef: EventHotKeyRef?
            let hotKeyId = EventHotKeyID(signature: signature, id: hotKeyId(for: direction))
            let status = RegisterEventHotKey(
                keyCode, modifiers, hotKeyId,
                GetApplicationEventTarget(), 0, &hotKeyRef)

            if status == noErr, let ref = hotKeyRef {
                hotKeyRefs[direction] = ref
                registered.insert(direction)
            } else {
                // errHotKeyConflict (-9868) or other failure.
                failed.insert(direction)
            }
        }
        return failed
    }

    /// Removes all registered hot keys.
    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registered.removeAll()
    }

    // MARK: - Event handling

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyId = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotKeyId)

            if status == noErr, let direction = manager.direction(for: hotKeyId.id) {
                DispatchQueue.main.async {
                    manager.onHotKey?(direction)
                }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType,
            userData, &eventHandlerRef)
        handlerInstalled = (status == noErr)
    }

    private static func keyCode(for direction: Direction) -> UInt32 {
        switch direction {
        case .left: return UInt32(kVK_LeftArrow)
        case .right: return UInt32(kVK_RightArrow)
        case .up: return UInt32(kVK_UpArrow)
        case .down: return UInt32(kVK_DownArrow)
        }
    }
}

extension ExtraModifier {
    /// Carbon modifier mask for this modifier (cmd is added separately).
    var carbonMask: UInt32 {
        switch self {
        case .option: return UInt32(optionKey)
        case .control: return UInt32(controlKey)
        case .shift: return UInt32(shiftKey)
        }
    }
}
