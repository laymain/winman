import CoreGraphics
import Testing
import WinManCore

/// Exhaustive tests for the pure window-state machine. These encode the
/// behaviour table from the requirements and verify each transition.
@Suite("Window state machine")
struct WindowStateMachineTests {

    private let machine = WindowStateMachine()

    /// A single 1920x1080 display at origin, menu bar 25pt, Dock excluded.
    private let display = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        availableFrame: CGRect(x: 0, y: 0, width: 1920, height: 1010)
    )

    /// A second display to the right, for multi-monitor tests.
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

    private func context(
        state: WindowLogicalState,
        currentFrame: CGRect? = nil,
        normal: CGRect? = nil,
        left: DisplayGeometry? = nil,
        right: DisplayGeometry? = nil,
        ratio: Double = 0.5,
        gap: Double = 0
    ) -> TransitionContext {
        TransitionContext(
            state: state,
            currentFrame: currentFrame ?? normalFrame,
            normalFrame: normal ?? normalFrame,
            display: display,
            leftNeighbor: left,
            rightNeighbor: right,
            snapRatio: ratio,
            snapGap: gap
        )
    }

    // MARK: - Normal transitions

    @Test func normalToLeftSnapsLeft() {
        let result = machine.transition(context(state: .normal), key: .left)
        #expect(result.newState == .snappedLeft)
        #expect(result.action == .applyFrame(
            WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 0)))
        #expect(result.newNormalFrame == normalFrame)
    }

    @Test func normalToRightSnapsRight() {
        let result = machine.transition(context(state: .normal), key: .right)
        #expect(result.newState == .snappedRight)
        #expect(result.action == .applyFrame(
            WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 0)))
        #expect(result.newNormalFrame == normalFrame)
    }

    @Test func normalToUpMaximizes() {
        let result = machine.transition(context(state: .normal), key: .up)
        #expect(result.newState == .maximized)
        #expect(result.action == .applyFrame(display.availableFrame))
        #expect(result.newNormalFrame == normalFrame)
    }

    @Test func normalToDownMinimizes() {
        let result = machine.transition(context(state: .normal), key: .down)
        #expect(result.newState == .minimized)
        #expect(result.action == .minimize)
        #expect(result.newNormalFrame == normalFrame)
    }

    // MARK: - Snap geometry

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

    @Test func snapGapReducesHalfWidths() {
        let left = WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 20)
        let right = WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 20)
        #expect(abs(left.width - (display.availableFrame.width / 2 - 10)) < 0.001)
        #expect(abs(right.width - (display.availableFrame.width / 2 - 10)) < 0.001)
        // Gap of 20 separates the two halves.
        #expect(abs((right.minX - left.maxX) - 20) < 0.001)
    }

    @Test func maximizeFrameExcludesMenuBarAndDock() {
        let frame = WindowStateMachine.maximizeFrame(display)
        #expect(frame == display.availableFrame)
        #expect(frame.height < display.frame.height)
    }

    // MARK: - Snapped left transitions

    @Test func snappedLeftToRightRestores() {
        let result = machine.transition(context(state: .snappedLeft), key: .right)
        #expect(result.newState == .normal)
        #expect(result.action == .applyFrame(normalFrame))
        #expect(result.newNormalFrame == normalFrame)
    }

    @Test func snappedLeftToDownRestores() {
        let result = machine.transition(context(state: .snappedLeft), key: .down)
        #expect(result.newState == .normal)
        #expect(result.action == .applyFrame(normalFrame))
    }

    @Test func snappedLeftToUpMaximizes() {
        let result = machine.transition(context(state: .snappedLeft), key: .up)
        #expect(result.newState == .maximized)
        #expect(result.action == .applyFrame(display.availableFrame))
        #expect(result.newNormalFrame == normalFrame)
    }

    @Test func snappedLeftToLeftMovesToLeftDisplay() {
        let snapped = WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 0)
        let ctx = context(state: .snappedLeft, currentFrame: snapped, left: leftDisplay)
        let result = machine.transition(ctx, key: .left)
        #expect(result.newState == .snappedLeft)
        #expect(result.action == .applyFrame(
            WindowStateMachine.leftSnapFrame(leftDisplay, ratio: 0.5, gap: 0)))
        #expect(result.newNormalFrame == normalFrame)
    }

    @Test func snappedLeftToLeftWithNoLeftDisplayStays() {
        let snapped = WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 0)
        let ctx = context(state: .snappedLeft, currentFrame: snapped, left: nil)
        let result = machine.transition(ctx, key: .left)
        #expect(result.newState == .snappedLeft)
        #expect(result.action == .noop)
    }

    // MARK: - Snapped right transitions

    @Test func snappedRightToLeftRestores() {
        let result = machine.transition(context(state: .snappedRight), key: .left)
        #expect(result.newState == .normal)
        #expect(result.action == .applyFrame(normalFrame))
        #expect(result.newNormalFrame == normalFrame)
    }

    @Test func snappedRightToDownRestores() {
        let result = machine.transition(context(state: .snappedRight), key: .down)
        #expect(result.newState == .normal)
        #expect(result.action == .applyFrame(normalFrame))
    }

    @Test func snappedRightToUpMaximizes() {
        let result = machine.transition(context(state: .snappedRight), key: .up)
        #expect(result.newState == .maximized)
        #expect(result.action == .applyFrame(display.availableFrame))
    }

    @Test func snappedRightToRightMovesToRightDisplay() {
        let snapped = WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 0)
        let ctx = context(state: .snappedRight, currentFrame: snapped, right: rightDisplay)
        let result = machine.transition(ctx, key: .right)
        #expect(result.newState == .snappedRight)
        #expect(result.action == .applyFrame(
            WindowStateMachine.rightSnapFrame(rightDisplay, ratio: 0.5, gap: 0)))
    }

    @Test func snappedRightToRightWithNoRightDisplayStays() {
        let snapped = WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 0)
        let ctx = context(state: .snappedRight, currentFrame: snapped, right: nil)
        let result = machine.transition(ctx, key: .right)
        #expect(result.newState == .snappedRight)
        #expect(result.action == .noop)
    }

    // MARK: - Maximized transitions

    @Test func maximizedToLeftSnapsLeft() {
        let result = machine.transition(context(state: .maximized), key: .left)
        #expect(result.newState == .snappedLeft)
        #expect(result.action == .applyFrame(
            WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 0)))
        #expect(result.newNormalFrame == normalFrame)
    }

    @Test func maximizedToRightSnapsRight() {
        let result = machine.transition(context(state: .maximized), key: .right)
        #expect(result.newState == .snappedRight)
        #expect(result.action == .applyFrame(
            WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 0)))
    }

    @Test func maximizedToUpStaysMaximized() {
        let result = machine.transition(context(state: .maximized), key: .up)
        #expect(result.newState == .maximized)
        #expect(result.action == .noop)
    }

    @Test func maximizedToDownRestores() {
        let result = machine.transition(context(state: .maximized), key: .down)
        #expect(result.newState == .normal)
        #expect(result.action == .applyFrame(normalFrame))
        #expect(result.newNormalFrame == normalFrame)
    }

    // MARK: - Minimized transitions

    @Test func minimizedToDownRestoresToNormal() {
        let result = machine.transition(context(state: .minimized), key: .down)
        #expect(result.newState == .normal)
        #expect(result.action == .unminimizeThenApplyFrame(normalFrame))
        #expect(result.newNormalFrame == normalFrame)
    }

    @Test func minimizedToLeftUnminimizesAndSnapsLeft() {
        let result = machine.transition(context(state: .minimized), key: .left)
        #expect(result.newState == .snappedLeft)
        #expect(result.action == .unminimizeThenApplyFrame(
            WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 0)))
    }

    @Test func minimizedToRightUnminimizesAndSnapsRight() {
        let result = machine.transition(context(state: .minimized), key: .right)
        #expect(result.newState == .snappedRight)
        #expect(result.action == .unminimizeThenApplyFrame(
            WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 0)))
    }

    @Test func minimizedToUpUnminimizesAndMaximizes() {
        let result = machine.transition(context(state: .minimized), key: .up)
        #expect(result.newState == .maximized)
        #expect(result.action == .unminimizeThenApplyFrame(display.availableFrame))
    }

    // MARK: - Repeated presses / round trips

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

    @Test func repeatedSnapLeftDoesNotChangeNormalFrame() {
        let first = machine.transition(context(state: .normal), key: .left)
        let second = machine.transition(
            context(state: .snappedLeft, normal: first.newNormalFrame, left: leftDisplay),
            key: .left
        )
        #expect(second.newNormalFrame == first.newNormalFrame)
        #expect(second.newState == .snappedLeft)
    }

    @Test func maximizeRepeatedIsIdempotent() {
        let first = machine.transition(context(state: .normal), key: .up)
        let second = machine.transition(
            context(state: .maximized, normal: first.newNormalFrame),
            key: .up
        )
        #expect(second.action == .noop)
        #expect(second.newNormalFrame == first.newNormalFrame)
    }

    // MARK: - State inference from geometry

    @Test func inferStateDetectsSnappedLeft() {
        let frame = WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 0)
        let state = WindowStateMachine.inferState(
            frame: frame, minimized: false, display: display, ratio: 0.5, gap: 0)
        #expect(state == .snappedLeft)
    }

    @Test func inferStateDetectsSnappedRight() {
        let frame = WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 0)
        let state = WindowStateMachine.inferState(
            frame: frame, minimized: false, display: display, ratio: 0.5, gap: 0)
        #expect(state == .snappedRight)
    }

    @Test func inferStateDetectsMaximized() {
        let state = WindowStateMachine.inferState(
            frame: display.availableFrame, minimized: false,
            display: display, ratio: 0.5, gap: 0)
        #expect(state == .maximized)
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

    // MARK: - Multi-monitor cycling

    @Test func cyclingSnappedLeftAcrossDisplaysPreservesSide() {
        let snapped = WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 0)
        let ctx = context(state: .snappedLeft, currentFrame: snapped, left: leftDisplay)
        let result = machine.transition(ctx, key: .left)
        #expect(result.newState == .snappedLeft)
        #expect(result.action == .applyFrame(
            WindowStateMachine.leftSnapFrame(leftDisplay, ratio: 0.5, gap: 0)))
    }

    @Test func cyclingSnappedRightAcrossDisplaysPreservesSide() {
        let snapped = WindowStateMachine.rightSnapFrame(display, ratio: 0.5, gap: 0)
        let ctx = context(state: .snappedRight, currentFrame: snapped, right: rightDisplay)
        let result = machine.transition(ctx, key: .right)
        #expect(result.newState == .snappedRight)
        #expect(result.action == .applyFrame(
            WindowStateMachine.rightSnapFrame(rightDisplay, ratio: 0.5, gap: 0)))
    }

    @Test func noAdjacentDisplayIsANoOp() {
        let snapped = WindowStateMachine.leftSnapFrame(display, ratio: 0.5, gap: 0)
        let ctx = context(state: .snappedLeft, currentFrame: snapped, left: nil)
        let result = machine.transition(ctx, key: .left)
        #expect(result.action == .noop)
        #expect(result.newState == .snappedLeft)
    }

    // MARK: - Different snap ratios

    @Test func customRatioIsRespected() {
        let left = WindowStateMachine.leftSnapFrame(display, ratio: 0.3, gap: 0)
        #expect(abs(left.width - display.availableFrame.width * 0.3) < 0.001)
        let right = WindowStateMachine.rightSnapFrame(display, ratio: 0.3, gap: 0)
        #expect(abs(right.width - display.availableFrame.width * 0.7) < 0.001)
        // Together they still tile the display with ratio 0.3.
        #expect(abs(left.maxX - right.minX) < 0.001)
    }
}
