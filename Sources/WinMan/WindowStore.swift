import CoreGraphics
import Foundation
import WinManCore

/// Identifies a window using its process id and title.
///
/// macOS Accessibility elements have no stable, public unique identifier, so
/// (pid, title) is the best available heuristic. It is imperfect when an app
/// has several windows with identical titles.
struct WindowIdentity: Hashable {
    let pid: pid_t
    let title: String
}

/// Per-window bookkeeping: the restore point plus the last state we set and
/// the frame we actually observed after setting it. The latter two let the
/// engine trust its own state when an app adjusted the snapped geometry (so a
/// snapped window is still recognized as snapped and Restore works), while
/// still detecting external moves.
struct WindowRecord {
    /// Geometry Restore returns to (pre-snap / pre-maximize / pre-minimize).
    var normalFrame: CGRect
    /// The logical state we last applied to this window.
    var lastState: WindowLogicalState
    /// The frame we last observed after applying `lastState`. Used to detect
    /// whether the window has been moved externally since we touched it.
    var lastObservedFrame: CGRect
}

/// Stores per-window restore points and last-applied state, keyed by
/// `WindowIdentity`.
final class WindowStore {
    static let shared = WindowStore()
    private init() {}

    private var records: [WindowIdentity: WindowRecord] = [:]

    func record(for identity: WindowIdentity) -> WindowRecord? {
        records[identity]
    }

    func normalFrame(for identity: WindowIdentity) -> CGRect? {
        records[identity]?.normalFrame
    }

    /// Persists the outcome of an applied transition.
    func setRecord(normalFrame: CGRect,
                   lastState: WindowLogicalState,
                   lastObservedFrame: CGRect,
                   for identity: WindowIdentity) {
        records[identity] = WindowRecord(
            normalFrame: normalFrame,
            lastState: lastState,
            lastObservedFrame: lastObservedFrame)
    }

    func removeRecord(for identity: WindowIdentity) {
        records.removeValue(forKey: identity)
    }

    /// Drops cached entries for windows that no longer exist (e.g. after an
    /// app quits). Call opportunistically with the set of live identities.
    func prune(to liveIdentities: Set<WindowIdentity>) {
        for key in records.keys where !liveIdentities.contains(key) {
            records.removeValue(forKey: key)
        }
    }
}
