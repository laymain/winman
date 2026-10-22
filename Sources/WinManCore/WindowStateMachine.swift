import CoreGraphics

/// Pure, side-effect-free state machine that reproduces the Windows
/// Win + Arrow window-management transitions. It has no dependency on AppKit,
/// the Accessibility API, or any global state, so it can be unit-tested
/// exhaustively in isolation.
public struct WindowStateMachine {
    public init() {}

    // MARK: - Geometry helpers

    /// Frame of the left half of a display's usable area, honouring the snap
    /// ratio and optional gap.
    public static func leftSnapFrame(_ display: DisplayGeometry, ratio: Double, gap: Double) -> CGRect {
        let a = display.availableFrame
        let g = max(0, gap)
        let w = (a.width * ratio) - (g / 2)
        return CGRect(x: a.minX, y: a.minY, width: max(1, w), height: a.height)
    }

    /// Frame of the right half of a display's usable area.
    public static func rightSnapFrame(_ display: DisplayGeometry, ratio: Double, gap: Double) -> CGRect {
        let a = display.availableFrame
        let g = max(0, gap)
        let w = (a.width * (1 - ratio)) - (g / 2)
        let x = a.minX + (a.width * ratio) + (g / 2)
        return CGRect(x: x, y: a.minY, width: max(1, w), height: a.height)
    }

    /// Frame that fills the usable area (menu bar and Dock excluded). This is
    /// "maximize" in our model and deliberately does NOT enter native full screen.
    public static func maximizeFrame(_ display: DisplayGeometry) -> CGRect {
        display.availableFrame
    }

    // MARK: - State inference from geometry

    /// Best-effort inference of a window's logical state by comparing its
    /// current frame with the expected snap / maximize frames for the display
    /// it currently occupies. Returns `.normal` when nothing matches.
    public static func inferState(
        frame: CGRect,
        minimized: Bool,
        display: DisplayGeometry,
        ratio: Double,
        gap: Double,
        tolerance: CGFloat = 4
    ) -> WindowLogicalState {
        if minimized { return .minimized }
        if Self.framesApproximatelyEqual(frame, maximizeFrame(display), tolerance: tolerance) {
            return .maximized
        }
        if Self.framesApproximatelyEqual(frame, leftSnapFrame(display, ratio: ratio, gap: gap), tolerance: tolerance) {
            return .snappedLeft
        }
        if Self.framesApproximatelyEqual(frame, rightSnapFrame(display, ratio: ratio, gap: gap), tolerance: tolerance) {
            return .snappedRight
        }
        return .normal
    }

    public static func framesApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= tolerance &&
        abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance &&
        abs(a.height - b.height) <= tolerance
    }

    // MARK: - The transition table

    /// Compute the next state and action for a directional key press, given the
    /// current window state and geometry. This mirrors the documented behaviour
    /// table; see ARCHITECTURE.md for the mapping to real Windows behaviour.
    public func transition(_ context: TransitionContext, key: Direction) -> TransitionResult {
        let d = context.display
        let ratio = context.snapRatio
        let gap = context.snapGap
        let left = WindowStateMachine.leftSnapFrame(d, ratio: ratio, gap: gap)
        let right = WindowStateMachine.rightSnapFrame(d, ratio: ratio, gap: gap)
        let max = WindowStateMachine.maximizeFrame(d)

        switch (context.state, key) {
        // Normal window
        case (.normal, .left):
            return TransitionResult(action: .applyFrame(left),
                                    newState: .snappedLeft,
                                    newNormalFrame: context.currentFrame)
        case (.normal, .right):
            return TransitionResult(action: .applyFrame(right),
                                    newState: .snappedRight,
                                    newNormalFrame: context.currentFrame)
        case (.normal, .up):
            return TransitionResult(action: .applyFrame(max),
                                    newState: .maximized,
                                    newNormalFrame: context.currentFrame)
        case (.normal, .down):
            return TransitionResult(action: .minimize,
                                    newState: .minimized,
                                    newNormalFrame: context.currentFrame)

        // Snapped left
        case (.snappedLeft, .left):
            if let leftDisplay = context.leftNeighbor {
                let target = WindowStateMachine.leftSnapFrame(leftDisplay, ratio: ratio, gap: gap)
                return TransitionResult(action: .applyFrame(target),
                                        newState: .snappedLeft,
                                        newNormalFrame: context.normalFrame)
            } else {
                // No display to the left: remain snapped left.
                return TransitionResult(action: .noop,
                                        newState: .snappedLeft,
                                        newNormalFrame: context.normalFrame)
            }
        case (.snappedLeft, .right):
            // Opposite-direction restore to previous size/position.
            return TransitionResult(action: .applyFrame(context.normalFrame),
                                    newState: .normal,
                                    newNormalFrame: context.normalFrame)
        case (.snappedLeft, .up):
            return TransitionResult(action: .applyFrame(max),
                                    newState: .maximized,
                                    newNormalFrame: context.normalFrame)
        case (.snappedLeft, .down):
            // Down from a snapped side restores to normal size.
            return TransitionResult(action: .applyFrame(context.normalFrame),
                                    newState: .normal,
                                    newNormalFrame: context.normalFrame)

        // Snapped right
        case (.snappedRight, .left):
            return TransitionResult(action: .applyFrame(context.normalFrame),
                                    newState: .normal,
                                    newNormalFrame: context.normalFrame)
        case (.snappedRight, .right):
            if let rightDisplay = context.rightNeighbor {
                let target = WindowStateMachine.rightSnapFrame(rightDisplay, ratio: ratio, gap: gap)
                return TransitionResult(action: .applyFrame(target),
                                        newState: .snappedRight,
                                        newNormalFrame: context.normalFrame)
            } else {
                return TransitionResult(action: .noop,
                                        newState: .snappedRight,
                                        newNormalFrame: context.normalFrame)
            }
        case (.snappedRight, .up):
            return TransitionResult(action: .applyFrame(max),
                                    newState: .maximized,
                                    newNormalFrame: context.normalFrame)
        case (.snappedRight, .down):
            return TransitionResult(action: .applyFrame(context.normalFrame),
                                    newState: .normal,
                                    newNormalFrame: context.normalFrame)

        // Maximized
        case (.maximized, .left):
            return TransitionResult(action: .applyFrame(left),
                                    newState: .snappedLeft,
                                    newNormalFrame: context.normalFrame)
        case (.maximized, .right):
            return TransitionResult(action: .applyFrame(right),
                                    newState: .snappedRight,
                                    newNormalFrame: context.normalFrame)
        case (.maximized, .up):
            // Already maximized: stay maximized.
            return TransitionResult(action: .noop,
                                    newState: .maximized,
                                    newNormalFrame: context.normalFrame)
        case (.maximized, .down):
            return TransitionResult(action: .applyFrame(context.normalFrame),
                                    newState: .normal,
                                    newNormalFrame: context.normalFrame)

        // Minimized
        case (.minimized, .left):
            return TransitionResult(action: .unminimizeThenApplyFrame(left),
                                    newState: .snappedLeft,
                                    newNormalFrame: context.normalFrame)
        case (.minimized, .right):
            return TransitionResult(action: .unminimizeThenApplyFrame(right),
                                    newState: .snappedRight,
                                    newNormalFrame: context.normalFrame)
        case (.minimized, .up):
            return TransitionResult(action: .unminimizeThenApplyFrame(max),
                                    newState: .maximized,
                                    newNormalFrame: context.normalFrame)
        case (.minimized, .down):
            return TransitionResult(action: .unminimizeThenApplyFrame(context.normalFrame),
                                    newState: .normal,
                                    newNormalFrame: context.normalFrame)
        }
    }
}
