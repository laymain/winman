import CoreGraphics

/// The five logical window states we track, mirroring the Windows snapping model.
public enum WindowLogicalState: Equatable, Codable {
    case normal
    case snappedLeft
    case snappedRight
    case maximized
    case minimized
}

/// Directional arrow pressed by the user.
public enum Direction: CaseIterable, Equatable {
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
    public var display: DisplayGeometry
    public var leftNeighbor: DisplayGeometry?
    public var rightNeighbor: DisplayGeometry?
    /// Fraction of usable width used by a snapped half (default 0.5).
    public var snapRatio: Double
    /// Optional gap in points between the two snapped halves.
    public var snapGap: Double

    public init(
        state: WindowLogicalState,
        currentFrame: CGRect,
        normalFrame: CGRect,
        display: DisplayGeometry,
        leftNeighbor: DisplayGeometry?,
        rightNeighbor: DisplayGeometry?,
        snapRatio: Double = 0.5,
        snapGap: Double = 0
    ) {
        self.state = state
        self.currentFrame = currentFrame
        self.normalFrame = normalFrame
        self.display = display
        self.leftNeighbor = leftNeighbor
        self.rightNeighbor = rightNeighbor
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
    /// Do nothing (e.g. maximize pressed while already maximized).
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
