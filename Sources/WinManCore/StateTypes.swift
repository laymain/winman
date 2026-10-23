import CoreGraphics

/// The logical window states we track, mirroring the Windows snapping model:
/// free-floating (normal), the four halves, the four quadrants, maximized, and
/// minimized.
public enum WindowLogicalState: Equatable, Codable, Sendable {
    case normal
    case snappedLeft
    case snappedRight
    case snappedUp
    case snappedDown
    case qTopLeft
    case qTopRight
    case qBottomLeft
    case qBottomRight
    case maximized
    case minimized
}

/// Directional arrow pressed by the user.
public enum Direction: CaseIterable, Equatable, Sendable {
    case left, right, up, down
}

/// A display's geometry in global screen coordinates (AppKit, bottom-left origin).
/// `frame` is the full display; `availableFrame` excludes the menu bar and Dock.
public struct DisplayGeometry: Equatable {
    public var frame: CGRect
    public var availableFrame: CGRect

    public init(frame: CGRect, availableFrame: CGRect) {
        self.frame = frame
        self.availableFrame = availableFrame
    }
}

/// Everything the pure state machine needs to decide a transition.
public struct TransitionContext {
    public var state: WindowLogicalState
    public var currentFrame: CGRect
    /// Geometry to restore to (pre-snap / pre-maximize / pre-minimize). Only
    /// meaningful when `state != .normal`.
    public var normalFrame: CGRect
    /// The display the window currently sits on.
    public var display: DisplayGeometry
    /// Every connected display; cycle targets (adjacent, wrap-around at the
    /// row ends) and restore re-homing are resolved from it.
    public var displays: [DisplayGeometry]
    /// Whether pressing "outward" horizontally may move the window to another
    /// display (adjacent neighbour, wrapping to the far end of the row; a
    /// single display mirrors in place). When false the same-side press is a
    /// no-op.
    public var cycleAcrossDisplays: Bool
    /// When true, restoring after the window crossed displays jumps back to
    /// the original monitor's geometry; when false (default) the restore point
    /// is re-homed onto the display the window is on now.
    public var restorePreservesMonitor: Bool
    /// Maximize fills the usable area, menu bar and Dock excluded (true), or
    /// the display's whole frame (false).
    public var maximizeUsesAvailableFrame: Bool
    /// Fraction of usable width used by a snapped half (default 0.5).
    public var snapRatio: Double
    /// Optional gap in points between snapped regions.
    public var snapGap: Double

    public init(
        state: WindowLogicalState,
        currentFrame: CGRect,
        normalFrame: CGRect,
        display: DisplayGeometry,
        displays: [DisplayGeometry],
        cycleAcrossDisplays: Bool = true,
        restorePreservesMonitor: Bool = false,
        maximizeUsesAvailableFrame: Bool = true,
        snapRatio: Double = 0.5,
        snapGap: Double = 0
    ) {
        self.state = state
        self.currentFrame = currentFrame
        self.normalFrame = normalFrame
        self.display = display
        self.displays = displays
        self.cycleAcrossDisplays = cycleAcrossDisplays
        self.restorePreservesMonitor = restorePreservesMonitor
        self.maximizeUsesAvailableFrame = maximizeUsesAvailableFrame
        self.snapRatio = snapRatio
        self.snapGap = snapGap
    }
}

/// The concrete effect the engine should apply to the window.
public enum WindowAction: Equatable {
    /// Set position/size; the window is assumed visible and un-minimized.
    case applyFrame(CGRect)
    /// Un-minimize (and raise) the window, then set its frame.
    case unminimizeThenApplyFrame(CGRect)
    /// Minimize the window to the Dock.
    case minimize
    /// Do nothing (e.g. Up pressed while already at the top edge).
    case noop
}

/// The outcome of a transition: the action to apply, the resulting logical
/// state, and the normal frame to remember going forward.
public struct TransitionResult: Equatable {
    public var action: WindowAction
    public var newState: WindowLogicalState
    public var newNormalFrame: CGRect

    public init(action: WindowAction, newState: WindowLogicalState, newNormalFrame: CGRect) {
        self.action = action
        self.newState = newState
        self.newNormalFrame = newNormalFrame
    }
}
