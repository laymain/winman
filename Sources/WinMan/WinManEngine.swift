import AppKit
import CoreGraphics
import Foundation
import WinManCore

/// Orchestrates a single hot-key press: reads the focused window, infers its
/// current state from real geometry, builds the transition context, runs the
/// pure state machine, then applies the result through the Accessibility API
/// and updates the remembered restore frame.
final class WinManEngine {

    private let settings = SettingsModel.shared
    private let ax = AccessibilityClient.shared
    private let store = WindowStore.shared

    /// Entry point invoked by the shortcut manager on the main thread.
    func handle(_ direction: Direction) {
        guard settings.isEnabled else { Log.write("bail: manager disabled"); return }
        guard settings.enabledArrows.isEnabled(direction) else { Log.write("bail: arrow disabled"); return }

        // Permission gate: never fight the OS when untrusted.
        guard ax.isTrusted else { Log.write("bail: not trusted"); return }

        guard let window = ax.focusedWindow() else { Log.write("bail: no focused window"); return }

        // Native full-screen windows are not addressable by frame; bail out
        // gracefully rather than doing something destructive.
        if ax.isFullScreen(window) { Log.write("bail: full screen"); return }

        let minimized = ax.isMinimized(window)
        // A minimized window may report a stale frame; fall back to the stored
        // normal frame so we can still reason about its display.
        let currentFrame = ax.frame(of: window) ?? store.normalFrame(for: identity(of: window))

        let displays = currentDisplays()
        guard !displays.isEmpty else { Log.write("bail: no displays"); return }

        // Determine the display the window belongs to. For minimized windows
        // with a remembered frame, use that; otherwise use the live frame.
        let referenceFrame = currentFrame ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let display = DisplayResolver.display(containing: referenceFrame, from: displays) else {
            Log.write("bail: no display for frame \(referenceFrame)")
            return
        }

        let identity = identity(of: window)
        let record = store.record(for: identity)

        // Decide the current state. We combine the state *we* last applied with
        // the live geometry:
        //   • If we previously snapped/maximized this window and it hasn't been
        //     moved since (frame still matches what we last saw), trust our own
        //     state. This is what makes Restore reliable even when an app
        //     adjusts the snapped geometry (min-size, aspect ratio, rounding),
        //     which would otherwise defeat exact-geometry inference.
        //   • Otherwise infer from geometry. A window moved or resized by the
        //     user or another app reads as .normal and gets a fresh restore point.
        let state: WindowLogicalState
        if minimized {
            state = .minimized
        } else if let record,
                  record.lastState != .normal,
                  let current = currentFrame,
                  WindowStateMachine.framesApproximatelyEqual(
                      current, record.lastObservedFrame, tolerance: 6) {
            state = record.lastState
        } else {
            state = WindowStateMachine.inferState(
                frame: currentFrame ?? .zero,
                minimized: false,
                display: display,
                ratio: settings.snapRatio,
                gap: settings.snapGap
            )
        }

        // Restore point. When the window is currently normal, the live frame IS
        // the restore point (the user controls it). When snapped/maximized/
        // minimized, keep the previously saved restore point — never overwrite
        // it with snapped or maximized geometry.
        var normalFrame: CGRect
        if state == .normal, let current = currentFrame {
            normalFrame = current
        } else {
            normalFrame = record?.normalFrame ?? synthesizedNormalFrame(for: display)
        }

        // Always resolve neighbours; the state machine decides whether the
        // press may actually cycle across displays (wrap-to-self mirror when
        // there is no adjacent display).
        let left = DisplayResolver.leftNeighbour(of: display, in: displays)
        let right = DisplayResolver.rightNeighbour(of: display, in: displays)

        let context = TransitionContext(
            state: state,
            currentFrame: currentFrame ?? normalFrame,
            normalFrame: normalFrame,
            display: display,
            leftNeighbor: left,
            rightNeighbor: right,
            cycleAcrossDisplays: settings.cycleAcrossDisplays,
            snapRatio: settings.snapRatio,
            snapGap: settings.snapGap
        )

        let result = WindowStateMachine().transition(context, key: direction)
        Log.write("handle \(direction): state=\(state) action=\(String(describing: result.action)) new=\(result.newState)")
        apply(result, to: window, identity: identity, display: display)
    }

    // MARK: - Applying results

    private func apply(_ result: TransitionResult,
                       to window: AXUIElement,
                       identity: WindowIdentity,
                       display: DisplayGeometry) {
        switch result.action {
        case .noop:
            break

        case .minimize:
            ax.setMinimized(true, of: window)

        case .applyFrame(let frame):
            let clamped = clampToVisibleDisplays(frame, displays: currentDisplays())
            ax.setFrame(clamped, of: window)

        case .unminimizeThenApplyFrame(let frame):
            ax.raise(window: window)
            ax.setMinimized(false, of: window)
            let clamped = clampToVisibleDisplays(frame, displays: currentDisplays())
            ax.setFrame(clamped, of: window)
        }

        // Persist the outcome. The state machine already preserves the previous
        // normal frame across snapped/maximized transitions, so `newNormalFrame`
        // is always the correct restore point. We also record the frame we
        // actually observe after applying (apps may adjust the request), so the
        // next keypress can tell "still where we left it" from "moved externally".
        let observed = ax.frame(of: window) ?? frameFallback(for: result.action)
        store.setRecord(
            normalFrame: result.newNormalFrame,
            lastState: result.newState,
            lastObservedFrame: observed,
            for: identity)
    }

    /// Some actions (minimize / noop) don't move the window; fall back to the
    /// action's target frame so the observation stays stable.
    private func frameFallback(for action: WindowAction) -> CGRect {
        switch action {
        case .applyFrame(let f), .unminimizeThenApplyFrame(let f):
            return f
        case .minimize, .noop:
            return .zero
        }
    }

    // MARK: - Helpers

    private func identity(of window: AXUIElement) -> WindowIdentity {
        let pid = ax.pid(of: window) ?? 0
        var titleValue: CFTypeRef?
        var title = ""
        if AXUIElementCopyAttributeValue(
            window, kAXTitleAttribute as CFString, &titleValue) == .success,
           let t = titleValue as? String {
            title = t
        }
        return WindowIdentity(pid: pid, title: title)
    }

    /// Builds a fallback restore frame (~60% of the display, centered) when no
    /// normal frame is known for a window that is already snapped/maximized.
    private func synthesizedNormalFrame(for display: DisplayGeometry) -> CGRect {
        let a = display.availableFrame
        let w = a.width * 0.6
        let h = a.height * 0.6
        let x = a.minX + (a.width - w) / 2
        let y = a.minY + (a.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Keeps a frame reachable after displays are connected/disconnected or
    /// rearranged. If the frame lies entirely outside every display, slide it
    /// onto the nearest display while preserving its size.
    private func clampToVisibleDisplays(_ frame: CGRect,
                                        displays: [DisplayGeometry]) -> CGRect {
        guard !displays.isEmpty else { return frame }
        if DisplayResolver.display(containing: frame, from: displays) != nil {
            return frame
        }
        // Find the display whose centre is nearest and reposition the frame
        // inside its available area, preserving size where possible.
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        guard let nearest = displays.min(by: { d1, d2 in
            dist(d1.frame, centre) < dist(d2.frame, centre)
        }) else { return frame }

        let a = nearest.availableFrame
        let w = min(frame.width, a.width)
        let h = min(frame.height, a.height)
        let x = min(max(frame.minX, a.minX), a.maxX - w)
        let y = min(max(frame.minY, a.minY), a.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = r.midX - p.x
        let dy = r.midY - p.y
        return dx * dx + dy * dy
    }

    /// Reads the current displays from AppKit into `DisplayGeometry` values.
    /// (The AppKit step lives here so `WinManCore` stays pure.)
    private func currentDisplays() -> [DisplayGeometry] {
        NSScreen.screens.map { screen in
            DisplayGeometry(frame: screen.frame, availableFrame: screen.visibleFrame)
        }
    }
}
