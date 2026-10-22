# WinMan — Architecture & Design Notes

A native macOS menu-bar utility that reproduces the Windows `Win + Arrow`
window-management model using `⌘ + <configurable modifier> + Arrow`.

## Goals

1. Reproduce the Windows **window-state transitions**, not just map each arrow
   to a fixed position. The behaviour depends on the focused window's current
   state and its saved geometry.
2. Lightweight, menu-bar-only, no permanently open main window.
3. Reliable and predictable over visual complexity.

## Module layout

The package is split so that the **decision logic is independent of macOS** and
can be tested without the full Xcode toolchain.

```
WinManCore        (pure, no SwiftUI/AppKit-dependent logic)
├── StateTypes.swift        WindowLogicalState, Direction, DisplayGeometry,
│                           TransitionContext, WindowAction, TransitionResult
├── WindowStateMachine.swift  Pure transition table + geometry + state inference
└── DisplayResolver.swift     Display adjacency / containment (pure geometry)

WinMan                 (the app; needs full Xcode to build — SwiftUI macros)
├── AccessibilityClient.swift  AXUIElement read/write, trust, focus
├── ShortcutManager.swift      Carbon RegisterEventHotKey global hot keys
├── WindowStore.swift          Per-window restore-point cache
├── WinManEngine.swift  Orchestrates one key press (read→infer→decide→apply)
├── SettingsModel.swift        Published settings + UserDefaults persistence
├── SettingsView.swift         Settings window (3 tabs)
├── MenuBarContentView.swift   Menu-bar dropdown
└── WinManApp.swift     @main App + AppDelegate (wiring)

WinManCoreTests   (Swift Testing suite for the state machine)
```

### Data flow for one key press

```
Carbon hot key → AppDelegate → WinManEngine.handle(direction)
  1. Read focused window + geometry + minimized/fullscreen via AccessibilityClient
  2. Resolve displays (AppKit NSScreen) → DisplayGeometry values
  3. DisplayResolver: which display is the window on? left/right neighbours?
  4. WindowStateMachine.inferState: normal / snappedLeft / snappedRight /
     maximized / minimized, from the *actual* geometry (not our own history)
  5. Build TransitionContext (state, currentFrame, restore frame, display,
     neighbours, snap ratio, gap)
  6. WindowStateMachine.transition → TransitionResult (action, newState,
     newNormalFrame)
  7. Apply the action via AccessibilityClient; persist the restore frame
```

Because state is **inferred from live geometry** on every press, the app does
not depend on its own shortcut history, and correctly handles windows that were
moved or resized manually after snapping (they re-infer as `.normal`).

## The state machine

States: `normal`, `snappedLeft`, `snappedRight`, `maximized`, `minimized`.

`transition(context, key) -> TransitionResult` is a pure `switch` over
`(state, direction)`. `TransitionResult` carries:

- `action`: `applyFrame(rect)` | `unminimizeThenApplyFrame(rect)` | `minimize` | `noop`
- `newState`: the resulting logical state
- `newNormalFrame`: the restore point to remember. Crucially, transitions from
  a snapped/maximized state **preserve** the previously saved normal frame, so
  the original geometry is never overwritten by snapped/maximized geometry.

Geometry helpers (`leftSnapFrame`, `rightSnapFrame`, `maximizeFrame`) compute
frames from a display's `availableFrame` (the usable area that excludes the
menu bar and Dock), honouring the snap ratio and optional gap.

## Validation against real Windows behaviour

The behaviour table in the requirements was cross-checked against Windows 10/11
`Win + Arrow` semantics. Confirmations and the one deliberate choice:

| Transition | Windows | This app | Notes |
|---|---|---|---|
| Normal → Left/Right | Snap to half | Snap left/right | ✓ |
| Normal → Up | Maximize | Maximize (usable area, not full-screen) | ✓ |
| Normal → Down | Minimize | Minimize | ✓ |
| Snapped(L) → Left | Move to left monitor, keep side; else stay | Same | ✓ |
| Snapped(L) → Right | Opposite direction restores to pre-snap size | Restore | ✓ |
| Snapped(L/R) → Up | Maximize | Maximize | ✓ |
| Snapped(L/R) → Down | Restore to normal size | Restore | ✓ |
| Maximized → Left/Right | Restore, then snap | Snap on current display | Equivalent end state |
| Maximized → Up | Remain maximized | `noop` | ✓ |
| Maximized → Down | Restore to pre-maximize size | Restore | ✓ |
| Minimized → any | Un-minimize then apply direction | `unminimizeThenApplyFrame` | ✓ |

Multi-monitor cycling preserves the snapped side and uses the *adjacent*
display only (never jumps to a non-adjacent one). With no adjacent display in
the requested direction, the transition is a `noop` (the window stays put).

**Not claimed as exact Windows compatibility** until the transitions are
exercised interactively on a real multi-monitor macOS setup; the unit tests
cover the transition table exhaustively, but display topology and third-party
app AX behaviour cannot be fully simulated.

## macOS API choices and their limitations

### Accessibility (AXUIElement) for window control

There is **no universal public API** to position other apps' windows. The
supported mechanism is the Accessibility API, which is best-effort:

- `AXUIElementCreateApplication(pid)` → `kAXFocusedWindowAttribute` gives the
  focused window.
- `kAXPositionAttribute` / `kAXSizeAttribute` (AXValue of CGPoint/CGSize) are
  read and written to move/resize.
- `kAXMinimizedAttribute` minimizes/restores; `AXRaiseAction` + `activate()`
  raises a minimized window.
- `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions` gate and request the
  required permission.

**Limitations:**

- Some applications (certain Java, Electron, games, or apps with custom window
  servers) do not expose standard window controls and may ignore or partially
  honour writes. We re-assert size after setting position and never "fight" an
  app that refuses — there is no retry loop.
- Native **full-screen** windows live in their own `Space` and are not
  addressable by frame; the engine detects `AXFullScreen` and bails out.
- Windows cannot be reliably identified by a stable public id, so the restore
  cache keys on `(pid, title)`. This is imperfect if an app has several windows
  with identical titles.
- The Accessibility permission must be granted by the user and can be revoked at
  any time; the app checks trust on every press and does nothing when untrusted.

### Global shortcuts (Carbon RegisterEventHotKey)

`RegisterEventHotKey` is used rather than `NSEvent.addGlobalMonitorForEvents`
because the monitor API can only *observe* — not consume — events, so the
shortcut would also reach the focused app. Carbon hot keys:

- Work globally even when the app is not focused.
- Are consumed by the system before reaching other apps.
- Support modifier + arrow combinations.
- Must be unregistered before re-registering to avoid duplicates (done on every
  settings change and on terminate).

**Limitations:** a chosen combination may already be claimed by macOS or
another app (`RegisterEventHotKey` then returns an error, e.g. conflict). We log
the failure and surface that a different modifier may be needed; we do not
silently steal shortcuts.

### Menu-bar-only lifecycle

`NSApp.setActivationPolicy(.accessory)` removes the Dock icon and main window.
The UI is a SwiftUI `MenuBarExtra` plus a `Settings` scene (opened on demand).
No permanently open window is required.

## Deliberate deviations / choices

- **Maximize** fills the *usable* area (`visibleFrame`), keeping the menu bar
  and Dock accessible; it does **not** enter native full-screen mode. This
  matches the requirement and is more predictable than full-screen Spaces.
- **Restore** returns to the exact saved normal frame (original position and
  size), including the original display when possible. After a restore, a
  clamp-to-nearest-display guard repositions the frame if the target display
  was disconnected.
- State is re-inferred from geometry on every press, so a window moved manually
  while snapped becomes `.normal` and the moved position becomes the new restore
  point.

## Testing

`WinManCoreTests` is a Swift Testing suite covering every transition in
the table, snap/maximize geometry, snap gap, state inference (including a
manually moved snapped window), multi-monitor cycling with and without an
adjacent display, repeated presses, and round-trip restoration of the original
frame. The suite builds and runs with only the Command Line Tools.
