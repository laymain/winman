import CoreGraphics
import Testing
import WinManCore

/// Exhaustive tests for the pure window-state machine: all 44 (state × key)
/// transitions, geometry, state inference, and display cycling.
@Suite("Window state machine")
struct WindowStateMachineTests {

    private let machine = WindowStateMachine()

    /// A single 1920x1080 display at origin, menu bar 25pt, Dock excluded.
    private let display = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        availableFrame: CGRect(x: 0, y: 0, width: 1920, height: 1010)
    )

    /// A second display to the right.
    private let rightDisplay = DisplayGeometry(
        frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        availableFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1010)
    )

    /// A display to the left.
    private let leftDisplay = DisplayGeometry(
        frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        availableFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1010)
    )

    /// An arbitrary "normal" (restorable) frame.
    private let normalFrame = CGRect(x: 200, y: 150, width: 800, height: 600)

    // MARK: - Helpers

    /// A context for a window in `state` on the main display, with the given
    /// restore point and (optionally) neighbouring displays.
    private func context(
        state: WindowLogicalState,
        currentFrame: CGRect? = nil,
        normal: CGRect? = nil,
        left: DisplayGeometry? = nil,
        right: DisplayGeometry? = nil,
        cycle: Bool = true,
        ratio: Double = 0.5,
        gap: Double = 0
    ) -> TransitionContext {
        TransitionContext(
            state: state,
            currentFrame: currentFrame ?? expectedFrame(for: state, on: display, ratio: ratio, gap: gap),
            normalFrame: normal ?? normalFrame,
            display: display,
            leftNeighbor: left,
            rightNeighbor: right,
            cycleAcrossDisplays: cycle,
            snapRatio: ratio,
            snapGap: gap
        )
    }

    /// The canonical frame of a state on a display.
    private func expectedFrame(
        for state: WindowLogicalState,
        on d: DisplayGeometry,
        ratio: Double = 0.5,
        gap: Double = 0
    ) -> CGRect {
        switch state {
        case .normal, .minimized:
            return normalFrame
        case .snappedLeft:
            return WindowStateMachine.leftSnapFrame(d, ratio: ratio, gap: gap)
        case .snappedRight:
            return WindowStateMachine.rightSnapFrame(d, ratio: ratio, gap: gap)
        case .snappedUp:
            return WindowStateMachine.topSnapFrame(d, gap: gap)
        case .snappedDown:
            return WindowStateMachine.bottomSnapFrame(d, gap: gap)
        case .qTopLeft:
            return WindowStateMachine.quadrantFrame(d, left: true, top: true, ratio: ratio, gap: gap)
        case .qTopRight:
            return WindowStateMachine.quadrantFrame(d, left: false, top: true, ratio: ratio, gap: gap)
        case .qBottomLeft:
            return WindowStateMachine.quadrantFrame(d, left: true, top: false, ratio: ratio, gap: gap)
        case .qBottomRight:
            return WindowStateMachine.quadrantFrame(d, left: false, top: false, ratio: ratio, gap: gap)
        case .maximized:
            return WindowStateMachine.maximizeFrame(d)
        }
    }

    // MARK: - Full transition matrix (44 cells)

    @Test func normalTransitions() {
        let cases: [(Direction, WindowLogicalState)] = [
            (.up, .maximized), (.down, .snappedDown),
            (.left, .snappedLeft), (.right, .snappedRight),
        ]
        for (key, expected) in cases {
            let result = machine.transition(context(state: .normal), key: key)
            #expect(result.newState == expected, "normal + \(key)")
            #expect(result.action == .applyFrame(expectedFrame(for: expected, on: display)),
                    "normal + \(key)")
            #expect(result.newNormalFrame == normalFrame, "normal + \(key)")
        }
    }

    @Test func minimizedOnlyRespondsToUp() {
        for key in [Direction.left, .right, .down] {
            let result = machine.transition(context(state: .minimized), key: key)
            #expect(result.action == .noop, "minimized + \(key)")
            #expect(result.newState == .minimized, "minimized + \(key)")
        }
        let up = machine.transition(context(state: .minimized), key: .up)
        #expect(up.action == .unminimizeThenApplyFrame(normalFrame))
        #expect(up.newState == .normal)
    }

    @Test func maximizedTransitions() {
        let expected: [(Direction, WindowLogicalState)] = [
            (.up, .snappedUp), (.down, .normal),
            (.left, .snappedLeft), (.right, .snappedRight),
        ]
        for (key, state) in expected {
            let result = machine.transition(context(state: .maximized), key: key)
            #expect(result.newState == state, "maximized + \(key)")
            if state == .normal {
                #expect(result.action == .applyFrame(normalFrame), "maximized + \(key)")
            } else {
                #expect(result.action == .applyFrame(expectedFrame(for: state, on: display)),
                        "maximized + \(key)")
            }
        }
    }

    @Test func snappedUpTransitions() {
        let expected: [(Direction, WindowLogicalState)] = [
            (.up, .snappedUp), (.down, .normal),
            (.left, .qTopLeft), (.right, .qTopRight),
        ]
        for (key, state) in expected {
            let result = machine.transition(context(state: .snappedUp), key: key)
            #expect(result.newState == state, "snappedUp + \(key)")
            if key == .up {
                #expect(result.action == .noop, "snappedUp + up")
            } else if state == .normal {
                #expect(result.action == .applyFrame(normalFrame), "snappedUp + down")
            } else {
                #expect(result.action == .applyFrame(expectedFrame(for: state, on: display)),
                        "snappedUp + \(key)")
            }
        }
    }

    @Test func snappedDownTransitions() {
        let expected: [(Direction, WindowLogicalState)] = [
            (.up, .normal), (.down, .minimized),
            (.left, .qBottomLeft), (.right, .qBottomRight),
        ]
        for (key, state) in expected {
            let result = machine.transition(context(state: .snappedDown), key: key)
            #expect(result.newState == state, "snappedDown + \(key)")
            if state == .minimized {
                #expect(result.action == .minimize, "snappedDown + down")
            } else if state == .normal {
                #expect(result.action == .applyFrame(normalFrame), "snappedDown + up")
            } else {
                #expect(result.action == .applyFrame(expectedFrame(for: state, on: display)),
                        "snappedDown + \(key)")
            }
        }
    }

    @Test func snappedLeftTransitions() {
        // Up/Down refine to quadrants; Right restores; Left cycles displays.
        let up = machine.transition(context(state: .snappedLeft), key: .up)
        #expect(up.newState == .qTopLeft)
        #expect(up.action == .applyFrame(expectedFrame(for: .qTopLeft, on: display)))
        #expect(up.newNormalFrame == normalFrame)

        let down = machine.transition(context(state: .snappedLeft), key: .down)
        #expect(down.newState == .qBottomLeft)
        #expect(down.action == .applyFrame(expectedFrame(for: .qBottomLeft, on: display)))

        let right = machine.transition(context(state: .snappedLeft), key: .right)
        #expect(right.newState == .normal)
        #expect(right.action == .applyFrame(normalFrame))
    }

    @Test func snappedRightTransitions() {
        let up = machine.transition(context(state: .snappedRight), key: .up)
        #expect(up.newState == .qTopRight)
        #expect(up.action == .applyFrame(expectedFrame(for: .qTopRight, on: display)))

        let down = machine.transition(context(state: .snappedRight), key: .down)
        #expect(down.newState == .qBottomRight)
        #expect(down.action == .applyFrame(expectedFrame(for: .qBottomRight, on: display)))

        let left = machine.transition(context(state: .snappedRight), key: .left)
        #expect(left.newState == .normal)
        #expect(left.action == .applyFrame(normalFrame))
    }

    @Test func qTopLeftTransitions() {
        let up = machine.transition(context(state: .qTopLeft), key: .up)
        #expect(up.newState == .maximized)
        #expect(up.action == .applyFrame(display.availableFrame))

        let down = machine.transition(context(state: .qTopLeft), key: .down)
        #expect(down.newState == .snappedLeft)
        #expect(down.action == .applyFrame(expectedFrame(for: .snappedLeft, on: display)))

        let right = machine.transition(context(state: .qTopLeft), key: .right)
        #expect(right.newState == .qTopRight)
        #expect(right.action == .applyFrame(expectedFrame(for: .qTopRight, on: display)))
        #expect(right.newNormalFrame == normalFrame)
    }

    @Test func qTopRightTransitions() {
        let up = machine.transition(context(state: .qTopRight), key: .up)
        #expect(up.newState == .maximized)
        #expect(up.action == .applyFrame(display.availableFrame))

        let down = machine.transition(context(state: .qTopRight), key: .down)
        #expect(down.newState == .snappedRight)
        #expect(down.action == .applyFrame(expectedFrame(for: .snappedRight, on: display)))

        let left = machine.transition(context(state: .qTopRight), key: .left)
        #expect(left.newState == .qTopLeft)
        #expect(left.action == .applyFrame(expectedFrame(for: .qTopLeft, on: display)))
    }

    @Test func qBottomLeftTransitions() {
        let up = machine.transition(context(state: .qBottomLeft), key: .up)
        #expect(up.newState == .snappedLeft)
        #expect(up.action == .applyFrame(expectedFrame(for: .snappedLeft, on: display)))

        let down = machine.transition(context(state: .qBottomLeft), key: .down)
        #expect(down.newState == .minimized)
        #expect(down.action == .minimize)

        let right = machine.transition(context(state: .qBottomLeft), key: .right)
        #expect(right.newState == .qBottomRight)
        #expect(right.action == .applyFrame(expectedFrame(for: .qBottomRight, on: display)))
        #expect(right.newNormalFrame == normalFrame)
    }

    @Test func qBottomRightTransitions() {
        let up = machine.transition(context(state: .qBottomRight), key: .up)
        #expect(up.newState == .snappedRight)
        #expect(up.action == .applyFrame(expectedFrame(for: .snappedRight, on: display)))

        let down = machine.transition(context(state: .qBottomRight), key: .down)
        #expect(down.newState == .minimized)
        #expect(down.action == .minimize)

        let left = machine.transition(context(state: .qBottomRight), key: .left)
        #expect(left.newState == .qBottomLeft)
        #expect(left.action == .applyFrame(expectedFrame(for: .qBottomLeft, on: display)))
    }

    // MARK: - Display cycling (same-side press)

    /// Pressing outward from a left-edge state lands on the *adjacent* side of
    /// the target display — the horizontal mirror of where it started.
    @Test func leftSideCycleMirrorsAcrossDisplays() {
        let cases: [(WindowLogicalState, WindowLogicalState)] = [
            (.snappedLeft, .snappedRight),
            (.qTopLeft, .qTopRight),
            (.qBottomLeft, .qBottomRight),
        ]
        for (from, to) in cases {
            let ctx = context(state: from, left: leftDisplay)
            let result = machine.transition(ctx, key: .left)
            #expect(result.newState == to, "\(from) + left")
            #expect(result.action == .applyFrame(expectedFrame(for: to, on: leftDisplay)),
                    "\(from) + left")
            #expect(result.newNormalFrame == normalFrame, "\(from) + left")
        }
    }

    @Test func rightSideCycleMirrorsAcrossDisplays() {
        let cases: [(WindowLogicalState, WindowLogicalState)] = [
            (.snappedRight, .snappedLeft),
            (.qTopRight, .qTopLeft),
            (.qBottomRight, .qBottomLeft),
        ]
        for (from, to) in cases {
            let ctx = context(state: from, right: rightDisplay)
            let result = machine.transition(ctx, key: .right)
            #expect(result.newState == to, "\(from) + right")
            #expect(result.action == .applyFrame(expectedFrame(for: to, on: rightDisplay)),
                    "\(from) + right")
        }
    }

    /// With no adjacent display the cycle wraps to the same display and lands
    /// on the mirrored side there.
    @Test func cycleWithoutNeighborWrapsToMirroredSideOnSameDisplay() {
        let cases: [(WindowLogicalState, Direction, WindowLogicalState)] = [
            (.snappedLeft, .left, .snappedRight),
            (.snappedRight, .right, .snappedLeft),
            (.qTopLeft, .left, .qTopRight),
            (.qTopRight, .right, .qTopLeft),
            (.qBottomLeft, .left, .qBottomRight),
            (.qBottomRight, .right, .qBottomLeft),
        ]
        for (from, key, to) in cases {
            let result = machine.transition(context(state: from), key: key)
            #expect(result.newState == to, "\(from) + \(key)")
            #expect(result.action == .applyFrame(expectedFrame(for: to, on: display)),
                    "\(from) + \(key)")
        }
    }

    /// When the user disabled cross-display cycling, same-side presses are a
    /// no-op even if a neighbour exists.
    @Test func cycleDisabledIsNoOp() {
        let ctx = context(state: .snappedLeft, left: leftDisplay, cycle: false)
        let result = machine.transition(ctx, key: .left)
        #expect(result.action == .noop)
        #expect(result.newState == .snappedLeft)
    }

    // MARK: - Geometry

    @Test func leftSnapFrameIsLeftHalfOfAvailableArea() {
        let frame = WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 0)
        #expect(abs(frame.minX - display.availableFrame.minX) < 0.001)
        #expect(abs(frame.width - display.availableFrame.width / 2) < 0.001)
        #expect(abs(frame.height - display.availableFrame.height) < 0.001)
        #expect(abs(frame.minY - display.availableFrame.minY) < 0.001)
    }

    @Test func rightSnapFrameIsRightHalfOfAvailableArea() {
        let frame = WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 0)
        #expect(abs(frame.maxX - display.availableFrame.maxX) < 0.001)
        #expect(abs(frame.width - display.availableFrame.width / 2) < 0.001)
    }

    @Test func topAndBottomSnapFramesSplitVertically() {
        let top = WindowStateMachine.topSnapFrame(display, gap: 0)
        let bottom = WindowStateMachine.bottomSnapFrame(display, gap: 0)
        #expect(abs(top.maxY - display.availableFrame.maxY) < 0.001)
        #expect(abs(bottom.minY - display.availableFrame.minY) < 0.001)
        #expect(abs(top.height - display.availableFrame.height / 2) < 0.001)
        #expect(abs(bottom.height - display.availableFrame.height / 2) < 0.001)
        // Together they tile the usable area.
        #expect(abs(bottom.maxY - top.minY) < 0.001)
        #expect(abs(top.width - display.availableFrame.width) < 0.001)
    }

    @Test func snapGapSeparatesAllRegions() {
        let left = WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 20)
        let right = WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 20)
        #expect(abs(left.width - (display.availableFrame.width / 2 - 10)) < 0.001)
        #expect(abs((right.minX - left.maxX) - 20) < 0.001)

        let top = WindowStateMachine.topSnapFrame(display, gap: 20)
        let bottom = WindowStateMachine.bottomSnapFrame(display, gap: 20)
        #expect(abs(top.height - (display.availableFrame.height / 2 - 10)) < 0.001)
        #expect(abs((top.minY - bottom.maxY) - 20) < 0.001)
    }

    @Test func quadrantsIntersectTheirHalves() {
        let a = display.availableFrame
        let tl = WindowStateMachine.quadrantFrame(display, left: true, top: true, ratio: 0.5, gap: 0)
        #expect(abs(tl.minX - a.minX) < 0.001)
        #expect(abs(tl.maxY - a.maxY) < 0.001)
        #expect(abs(tl.width - a.width / 2) < 0.001)
        #expect(abs(tl.height - a.height / 2) < 0.001)

        let br = WindowStateMachine.quadrantFrame(display, left: false, top: false, ratio: 0.5, gap: 0)
        #expect(abs(br.maxX - a.maxX) < 0.001)
        #expect(abs(br.minY - a.minY) < 0.001)

        // The four quadrants tile the usable area.
        let tr = WindowStateMachine.quadrantFrame(display, left: false, top: true, ratio: 0.5, gap: 0)
        let bl = WindowStateMachine.quadrantFrame(display, left: true, top: false, ratio: 0.5, gap: 0)
        #expect(abs(tl.maxX - tr.minX) < 0.001)
        #expect(abs(tl.minY - bl.maxY) < 0.001)
    }

    @Test func customRatioIsRespected() {
        let left = WindowStateMachine.leftSnapFrame(display, ratio: 0.3, gap: 0)
        #expect(abs(left.width - display.availableFrame.width * 0.3) < 0.001)
        let right = WindowStateMachine.rightSnapFrame(display, ratio: 0.3, gap: 0)
        #expect(abs(right.width - display.availableFrame.width * 0.7) < 0.001)
        #expect(abs(left.maxX - right.minX) < 0.001)
        // A quadrant's width follows the horizontal ratio too.
        let tl = WindowStateMachine.quadrantFrame(display, left: true, top: true, ratio: 0.3, gap: 0)
        #expect(abs(tl.width - display.availableFrame.width * 0.3) < 0.001)
    }

    @Test func maximizeFrameExcludesMenuBarAndDock() {
        let frame = WindowStateMachine.maximizeFrame(display)
        #expect(frame == display.availableFrame)
        #expect(frame.height < display.frame.height)
    }

    // MARK: - State inference from geometry

    @Test func inferStateDetectsEveryRegion() {
        let states: [WindowLogicalState] = [
            .maximized, .snappedLeft, .snappedRight, .snappedUp, .snappedDown,
            .qTopLeft, .qTopRight, .qBottomLeft, .qBottomRight,
        ]
        for state in states {
            let frame = expectedFrame(for: state, on: display)
            let inferred = WindowStateMachine.inferState(
                frame: frame, minimized: false, display: display, ratio: 0.5, gap: 0)
            #expect(inferred == state, "infer \(state)")
        }
    }

    @Test func inferStateDetectsNormalForArbitraryFrame() {
        let state = WindowStateMachine.inferState(
            frame: normalFrame, minimized: false, display: display, ratio: 0.5, gap: 0)
        #expect(state == .normal)
    }

    @Test func inferStateDetectsMinimized() {
        let state = WindowStateMachine.inferState(
            frame: normalFrame, minimized: true, display: display, ratio: 0.5, gap: 0)
        #expect(state == .minimized)
    }

    /// A window manually moved away from its snapped position must be treated
    /// as normal again, so the next action saves a fresh restore point.
    @Test func manuallyMovedSnappedWindowIsInferredNormal() {
        let moved = CGRect(x: 500, y: 300, width: 700, height: 500)
        let state = WindowStateMachine.inferState(
            frame: moved, minimized: false, display: display, ratio: 0.5, gap: 0)
        #expect(state == .normal)
    }

    // MARK: - Round trips and repeated presses

    @Test func snapThenRestoreRoundTripPreservesOriginalFrame() {
        let snap = machine.transition(context(state: .normal), key: .left)
        let restore = machine.transition(
            context(state: .snappedLeft, normal: snap.newNormalFrame),
            key: .right
        )
        #expect(restore.action == .applyFrame(snap.newNormalFrame))
        #expect(restore.newState == .normal)
    }

    @Test func maximizeThenRestoreRoundTripPreservesOriginalFrame() {
        let max = machine.transition(context(state: .normal), key: .up)
        let restore = machine.transition(
            context(state: .maximized, normal: max.newNormalFrame),
            key: .down
        )
        #expect(restore.action == .applyFrame(max.newNormalFrame))
    }

    @Test func snapDownChainReachesMinimizeAndBack() {
        let bottom = machine.transition(context(state: .normal), key: .down)
        #expect(bottom.newState == .snappedDown)
        #expect(bottom.newNormalFrame == normalFrame)

        let minimized = machine.transition(
            context(state: .snappedDown, normal: bottom.newNormalFrame),
            key: .down
        )
        #expect(minimized.newState == .minimized)
        #expect(minimized.action == .minimize)
        #expect(minimized.newNormalFrame == normalFrame)

        let restored = machine.transition(
            context(state: .minimized, normal: minimized.newNormalFrame),
            key: .up
        )
        #expect(restored.newState == .normal)
        #expect(restored.action == .unminimizeThenApplyFrame(normalFrame))
    }

    @Test func snapUpChainReachesTopHalfAndRestores() {
        let maximized = machine.transition(context(state: .normal), key: .up)
        #expect(maximized.newState == .maximized)

        let top = machine.transition(
            context(state: .maximized, normal: maximized.newNormalFrame),
            key: .up
        )
        #expect(top.newState == .snappedUp)
        #expect(top.action == .applyFrame(expectedFrame(for: .snappedUp, on: display)))
        #expect(top.newNormalFrame == normalFrame)

        let stay = machine.transition(
            context(state: .snappedUp, normal: top.newNormalFrame),
            key: .up
        )
        #expect(stay.action == .noop)

        let restored = machine.transition(
            context(state: .snappedUp, normal: top.newNormalFrame),
            key: .down
        )
        #expect(restored.newState == .normal)
        #expect(restored.action == .applyFrame(normalFrame))
    }

    @Test func quadrantRefinementRoundTripPreservesRestorePoint() {
        let snap = machine.transition(context(state: .normal), key: .left)
        let quad = machine.transition(
            context(state: .snappedLeft, normal: snap.newNormalFrame),
            key: .up
        )
        #expect(quad.newState == .qTopLeft)
        #expect(quad.newNormalFrame == normalFrame)

        let back = machine.transition(
            context(state: .qTopLeft, normal: quad.newNormalFrame),
            key: .down
        )
        #expect(back.newState == .snappedLeft)
        #expect(back.newNormalFrame == normalFrame)

        let restore = machine.transition(
            context(state: .snappedLeft, normal: back.newNormalFrame),
            key: .right
        )
        #expect(restore.newState == .normal)
        #expect(restore.action == .applyFrame(normalFrame))
    }

    @Test func repeatedSnapDoesNotChangeNormalFrame() {
        let first = machine.transition(context(state: .normal), key: .left)
        let second = machine.transition(
            context(state: .snappedLeft, normal: first.newNormalFrame, left: leftDisplay),
            key: .left
        )
        #expect(second.newNormalFrame == first.newNormalFrame)
        #expect(second.newState == .snappedRight)
        let third = machine.transition(
            context(state: .snappedRight, normal: second.newNormalFrame, right: rightDisplay),
            key: .right
        )
        #expect(third.newNormalFrame == first.newNormalFrame)
        #expect(third.newState == .snappedLeft)
    }
}
