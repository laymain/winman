import CoreGraphics

/// Pure, side-effect-free state machine that reproduces the Win + Arrow
/// window-management transitions. It has no dependency on AppKit, the
/// Accessibility API, or any global state, so it can be unit-tested
/// exhaustively in isolation.
public struct WindowStateMachine {
    public init() {}

    // MARK: - Model

    /// Where on a display a snapped window sits. Every outcome that moves the
    /// window targets one of these; `.normal` and `.minimized` are carried by
    /// `WindowLogicalState` instead because they have no display-relative frame.
    private enum Zone: Equatable {
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
        case maximized

        var state: WindowLogicalState {
            switch self {
            case .left: return .snappedLeft
            case .right: return .snappedRight
            case .top: return .snappedUp
            case .bottom: return .snappedDown
            case .topLeft: return .qTopLeft
            case .topRight: return .qTopRight
            case .bottomLeft: return .qBottomLeft
            case .bottomRight: return .qBottomRight
            case .maximized: return .maximized
            }
        }
    }

    /// What one key press asks for, decided without touching geometry.
    private enum Outcome: Equatable {
        /// Move into `zone` on the current display.
        case to(Zone)
        /// Return to the saved normal frame.
        case restore
        case minimize
        /// Pressing outward from a side edge: hop to the adjacent display in
        /// that direction (wrapping to the current display when there is none),
        /// landing on `zone` — the position mirrored across the pressed edge.
        case cycle(Zone)
        /// Keep the current state; do nothing.
        case stay
    }

    // MARK: - The transition table

    /// All 44 (state × key) transitions in one exhaustive switch — the
    /// compiler fails the build if a cell is missing.
    private static func outcome(of state: WindowLogicalState, key: Direction) -> Outcome {
        switch (state, key) {
        //               Up                     Down                   Left                     Right
        case (.normal, .up):              return .to(.maximized)
        case (.normal, .down):            return .to(.bottom)
        case (.normal, .left):            return .to(.left)
        case (.normal, .right):           return .to(.right)

        case (.minimized, .up):           return .restore
        case (.minimized, _):             return .stay

        case (.maximized, .up):           return .to(.top)
        case (.maximized, .down):         return .restore
        case (.maximized, .left):         return .to(.left)
        case (.maximized, .right):        return .to(.right)

        case (.snappedUp, .up):           return .stay
        case (.snappedUp, .down):         return .restore
        case (.snappedUp, .left):         return .to(.topLeft)
        case (.snappedUp, .right):        return .to(.topRight)

        case (.snappedDown, .up):         return .restore
        case (.snappedDown, .down):       return .minimize
        case (.snappedDown, .left):       return .to(.bottomLeft)
        case (.snappedDown, .right):      return .to(.bottomRight)

        case (.snappedLeft, .up):         return .to(.topLeft)
        case (.snappedLeft, .down):       return .to(.bottomLeft)
        case (.snappedLeft, .left):       return .cycle(.right)
        case (.snappedLeft, .right):      return .restore

        case (.snappedRight, .up):        return .to(.topRight)
        case (.snappedRight, .down):      return .to(.bottomRight)
        case (.snappedRight, .left):      return .restore
        case (.snappedRight, .right):     return .cycle(.left)

        case (.qTopLeft, .up):            return .to(.maximized)
        case (.qTopLeft, .down):          return .to(.left)
        case (.qTopLeft, .left):          return .cycle(.topRight)
        case (.qTopLeft, .right):         return .to(.topRight)

        case (.qTopRight, .up):           return .to(.maximized)
        case (.qTopRight, .down):         return .to(.right)
        case (.qTopRight, .left):         return .to(.topLeft)
        case (.qTopRight, .right):        return .cycle(.topLeft)

        case (.qBottomLeft, .up):         return .to(.left)
        case (.qBottomLeft, .down):       return .minimize
        case (.qBottomLeft, .left):       return .cycle(.bottomRight)
        case (.qBottomLeft, .right):      return .to(.bottomRight)

        case (.qBottomRight, .up):        return .to(.right)
        case (.qBottomRight, .down):      return .minimize
        case (.qBottomRight, .left):      return .to(.bottomLeft)
        case (.qBottomRight, .right):     return .cycle(.bottomLeft)
        }
    }

    // MARK: - Transition

    /// Compute the next state and action for a directional key press, given the
    /// current window state and geometry.
    public func transition(_ context: TransitionContext, key: Direction) -> TransitionResult {
        // The restore point: a free-floating window's live frame is what the
        // user wants back; for every other state it is the frame saved on the
        // way in — snapped/maximized geometry never overwrites it.
        let restorePoint = context.state == .normal ? context.currentFrame : context.normalFrame

        switch Self.outcome(of: context.state, key: key) {
        case .stay:
            return TransitionResult(action: .noop,
                                    newState: context.state,
                                    newNormalFrame: restorePoint)

        case .restore:
            let point = Self.restoreFrame(context)
            let action: WindowAction = context.state == .minimized
                ? .unminimizeThenApplyFrame(point)
                : .applyFrame(point)
            return TransitionResult(action: action,
                                    newState: .normal,
                                    newNormalFrame: restorePoint)

        case .minimize:
            return TransitionResult(action: .minimize,
                                    newState: .minimized,
                                    newNormalFrame: restorePoint)

        case .to(let zone):
            let frame = Self.frame(for: zone, on: context.display, context: context)
            return TransitionResult(action: .applyFrame(frame),
                                    newState: zone.state,
                                    newNormalFrame: restorePoint)

        case .cycle(let zone):
            guard context.cycleAcrossDisplays else {
                return TransitionResult(action: .noop,
                                        newState: context.state,
                                        newNormalFrame: restorePoint)
            }
            let target = Self.cycleTarget(context, key: key)
            let frame = Self.frame(for: zone, on: target, context: context)
            return TransitionResult(action: .applyFrame(frame),
                                    newState: zone.state,
                                    newNormalFrame: restorePoint)
        }
    }

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

    /// Frame of the top half of a display's usable area (always an even
    /// vertical split).
    public static func topSnapFrame(_ display: DisplayGeometry, gap: Double) -> CGRect {
        let a = display.availableFrame
        let g = max(0, gap)
        let h = (a.height * 0.5) - (g / 2)
        return CGRect(x: a.minX, y: a.minY + (a.height * 0.5) + (g / 2),
                      width: a.width, height: max(1, h))
    }

    /// Frame of the bottom half of a display's usable area.
    public static func bottomSnapFrame(_ display: DisplayGeometry, gap: Double) -> CGRect {
        let a = display.availableFrame
        let g = max(0, gap)
        let h = (a.height * 0.5) - (g / 2)
        return CGRect(x: a.minX, y: a.minY, width: a.width, height: max(1, h))
    }

    /// Frame of a quadrant: the intersection of one horizontal half (which
    /// honours the snap ratio) and one vertical half.
    public static func quadrantFrame(_ display: DisplayGeometry,
                                     left: Bool, top: Bool,
                                     ratio: Double, gap: Double) -> CGRect {
        let h = left
            ? leftSnapFrame(display, ratio: ratio, gap: gap)
            : rightSnapFrame(display, ratio: ratio, gap: gap)
        let v = top
            ? topSnapFrame(display, gap: gap)
            : bottomSnapFrame(display, gap: gap)
        return CGRect(x: h.minX, y: v.minY, width: h.width, height: v.height)
    }

    /// Frame that fills the display: the usable area (menu bar and Dock
    /// excluded) by default, or the whole frame when the matching setting is
    /// off. This is "maximize" in our model and deliberately does NOT enter
    /// native full screen.
    public static func maximizeFrame(_ display: DisplayGeometry,
                                     usesAvailableFrame: Bool = true) -> CGRect {
        usesAvailableFrame ? display.availableFrame : display.frame
    }

    private static func frame(for zone: Zone,
                              on display: DisplayGeometry,
                              context: TransitionContext) -> CGRect {
        let ratio = context.snapRatio
        let gap = context.snapGap
        switch zone {
        case .left: return leftSnapFrame(display, ratio: ratio, gap: gap)
        case .right: return rightSnapFrame(display, ratio: ratio, gap: gap)
        case .top: return topSnapFrame(display, gap: gap)
        case .bottom: return bottomSnapFrame(display, gap: gap)
        case .topLeft: return quadrantFrame(display, left: true, top: true, ratio: ratio, gap: gap)
        case .topRight: return quadrantFrame(display, left: false, top: true, ratio: ratio, gap: gap)
        case .bottomLeft: return quadrantFrame(display, left: true, top: false, ratio: ratio, gap: gap)
        case .bottomRight: return quadrantFrame(display, left: false, top: false, ratio: ratio, gap: gap)
        case .maximized: return maximizeFrame(display, usesAvailableFrame: context.maximizeUsesAvailableFrame)
        }
    }

    /// Where a same-side press continues: the adjacent display in the pressed
    /// direction, wrapping to the far end of the row when there is none (and
    /// to the display itself when it is the only one).
    private static func cycleTarget(_ context: TransitionContext, key: Direction) -> DisplayGeometry {
        let neighbour = key == .left
            ? DisplayResolver.leftNeighbour(of: context.display, in: context.displays)
            : DisplayResolver.rightNeighbour(of: context.display, in: context.displays)
        return neighbour
            ?? DisplayResolver.wraparound(in: context.displays, direction: key)
            ?? context.display
    }

    /// The geometry a restore applies: the saved point as-is when it already
    /// belongs to the current display, when the user pinned restores to the
    /// original monitor, or when nothing is known; otherwise re-homed onto the
    /// current display so a window that cycled across displays stays put.
    private static func restoreFrame(_ context: TransitionContext) -> CGRect {
        guard !context.restorePreservesMonitor else { return context.normalFrame }
        guard let origin = DisplayResolver.display(
            containing: context.normalFrame, from: context.displays)
        else { return context.normalFrame }
        return DisplayResolver.relocate(context.normalFrame, from: origin, to: context.display)
    }

    // MARK: - State inference from geometry

    /// Best-effort inference of a window's logical state by comparing its
    /// current frame with the expected frames for the display it occupies.
    /// Returns `.normal` when nothing matches.
    public static func inferState(
        frame: CGRect,
        minimized: Bool,
        display: DisplayGeometry,
        ratio: Double,
        gap: Double,
        maximizeUsesAvailableFrame: Bool = true,
        tolerance: CGFloat = 4
    ) -> WindowLogicalState {
        if minimized { return .minimized }

        let candidates: [(WindowLogicalState, CGRect)] = [
            (.maximized, maximizeFrame(display, usesAvailableFrame: maximizeUsesAvailableFrame)),
            (.snappedLeft, leftSnapFrame(display, ratio: ratio, gap: gap)),
            (.snappedRight, rightSnapFrame(display, ratio: ratio, gap: gap)),
            (.snappedUp, topSnapFrame(display, gap: gap)),
            (.snappedDown, bottomSnapFrame(display, gap: gap)),
            (.qTopLeft, quadrantFrame(display, left: true, top: true, ratio: ratio, gap: gap)),
            (.qTopRight, quadrantFrame(display, left: false, top: true, ratio: ratio, gap: gap)),
            (.qBottomLeft, quadrantFrame(display, left: true, top: false, ratio: ratio, gap: gap)),
            (.qBottomRight, quadrantFrame(display, left: false, top: false, ratio: ratio, gap: gap)),
        ]
        for (state, expected) in candidates
        where framesApproximatelyEqual(frame, expected, tolerance: tolerance) {
            return state
        }
        return .normal
    }

    public static func framesApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= tolerance &&
        abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance &&
        abs(a.height - b.height) <= tolerance
    }
}
