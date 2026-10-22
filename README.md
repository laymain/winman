# WinMan

A macOS menu-bar utility that reproduces the Windows `Win + Arrow`
window-management model with `⌘ + <modifier> + Arrow`, where the modifier is
configurable (Option, Control, or Shift; Option by default).

What each arrow does depends on the focused window's current state (normal,
snapped left, snapped right, maximized, minimized) and its saved geometry —
not just on the pressed shortcut, like Windows.

Swift, SwiftUI, AppKit. Carbon hot-key API for global shortcuts, Accessibility
API for window control. No third-party dependencies. Bundle ID:
`com.laymain.winman`.

## Behaviour

Default shortcuts (Option as modifier):

| Shortcut | Normal | Snapped left | Snapped right | Maximized | Minimized |
|---|---|---|---|---|---|
| `⌘⌥←` | Snap left | Move to left display + snap left, else stay | Restore | Restore, then snap left | Un-minimize + snap left |
| `⌘⌥→` | Snap right | Restore | Move to right display + snap right, else stay | Restore, then snap right | Un-minimize + snap right |
| `⌘⌥↑` | Maximize | Maximize | Maximize | Remain maximized | Un-minimize + maximize |
| `⌘⌥↓` | Minimize | Restore | Restore | Restore | Un-minimize (restore) |

- **Snap**: fills ~50% of the usable display width (menu bar and Dock
  excluded), flush to the edge. Ratio and gap are configurable.
- **Maximize**: fills the usable desktop area. Does *not* enter native
  full-screen mode.
- **Restore**: returns to the exact saved position and size. Snapped and
  maximized geometry never overwrites the saved restore point.
- **Multi-monitor**: a snapped window cycles to the adjacent display in the
  pressed direction, preserving its snapped side; with no adjacent display it
  stays put. Horizontal, vertical, and mixed arrangements are supported.

Window state is re-inferred from actual geometry on every press, so windows
moved or resized manually between shortcuts are handled correctly (they become
"normal" again).

## Requirements

- macOS 14.0 or later (developed and verified on macOS 27 / Apple Silicon).
- Full **Xcode** to build the app target (SwiftUI macros are not in the
  Command Line Tools).
- Accessibility permission to control other apps' windows.

## Building

### Xcode

```sh
open Package.swift      # Xcode opens the Swift package directly
```

Select the **WinMan** scheme and Run.

### Command line

Requires an Xcode toolchain (the Command Line Tools alone are not sufficient):

```sh
./Scripts/make-app.sh      # builds release + assembles build/WinMan.app
open build/WinMan.app
```

`make-app.sh` signs the app with the stable local certificate created by
`./Scripts/setup-signing.sh` (run once). This matters: ad-hoc signatures
change on every rebuild, which silently revokes the Accessibility grant. If
the certificate is missing the script falls back to ad-hoc and warns.

## Permissions

WinMan requires **Accessibility** access to read and move other applications'
windows.

1. On first launch the app prompts for access. If you dismissed it, open
   **System Settings → Privacy & Security → Accessibility**.
2. Find **WinMan** in the list and enable it. If it is not listed, drag
   `build/WinMan.app` from Finder into the list.
3. If the app was already running when permission was granted, quit and
   relaunch it.

To revoke: turn the toggle off, or press **−**. The Settings → System tab
shows the current status and can open the pane directly.

## Usage

The app lives entirely in the menu bar (no Dock icon, no main window). Its
menu contains an **Enabled** toggle, the current shortcuts, **Settings…**,
**Accessibility Permissions…**, and **Quit**.

### Settings

- **Keyboard Shortcuts** — enable/disable the manager, choose the modifier,
  see the full combination in native symbols (e.g. `⌘⌥`), and enable/disable
  each arrow individually. Changes apply immediately.
- **Window Behavior** — snap width (25–90%, default 50%), optional gap,
  maximize/restore behaviour, and whether snapped windows cycle across
  displays.
- **System** — Accessibility permission status, a button to open the relevant
  pane, and grant/revoke instructions.

Settings persist across restarts (UserDefaults).

## Project structure

```
Package.swift
Sources/
  WinManCore/             Pure logic — no SwiftUI, testable anywhere
    StateTypes.swift        States, directions, display geometry, actions
    WindowStateMachine.swift  Transition table + geometry + state inference
    DisplayResolver.swift   Display adjacency and containment (pure geometry)
  WinMan/                 The app — needs full Xcode to build
    AccessibilityClient.swift  AXUIElement read/write, trust, focus, raise
    ShortcutManager.swift      Carbon RegisterEventHotKey global hot keys
    WindowStore.swift          Per-window restore-point cache
    WinManEngine.swift         Orchestrates one key press
    SettingsModel.swift        Settings + persistence
    SettingsView.swift         Settings window (3 tabs)
    MenuBarContentView.swift   Menu-bar dropdown
    WinManApp.swift            @main App + AppDelegate wiring
  WinManCoreTests/        Swift Testing suite for the state machine
Support/Info.plist        Bundle metadata (LSUIElement, AX usage description)
Scripts/make-app.sh       Builds and assembles build/WinMan.app
Scripts/setup-signing.sh  Creates the stable local signing certificate
ARCHITECTURE.md           Design notes, Windows-behaviour validation, limits
```

The shortcut manager, engine, state machine, settings, and UI are separate
modules. The state machine is deliberately free of macOS APIs so every
transition is unit-tested in isolation.

## Testing

```sh
swift test
```

Swift Testing suite (40 tests): every transition in the behaviour table,
snap/maximize geometry, snap gap, state inference (including a manually moved
snapped window), multi-monitor cycling with and without an adjacent display,
repeated presses, and round-trip restoration of the original frame.

`swift test` builds the whole package and needs the full Xcode toolchain. The
core library alone builds with the Command Line Tools:
`swift build --target WinManCore`.

## Distribution

The current signing identity is a local self-signed certificate; the app runs
only on machines that trust it. Distribution outside the Mac App Store
requires an Apple Developer Program membership, a Developer ID Application
certificate, and notarization (`notarytool` + `stapler`). The Mac App Store is
not an option: the App Sandbox blocks controlling other apps' windows.

Every user must grant Accessibility access manually regardless of signing.

## Known limitations

macOS platform constraints, not bugs. See ARCHITECTURE.md for detail.

- **Accessibility API is best-effort.** Some applications (certain Java,
  Electron, games, or apps with custom window servers) do not expose standard
  window controls and may ignore or partially honour position/size writes.
  WinMan re-asserts size after setting position and never fights an app that
  refuses a change.
- **Native full-screen windows** live in their own Space and are not
  addressable by frame. The engine detects this and does nothing.
- **Window identity** is keyed on `(process id, title)` because macOS has no
  stable public window identifier. Several windows with identical titles in
  one app may share a restore point.
- **Global shortcut conflicts.** If `⌘ + <modifier> + Arrow` is already
  claimed by macOS or another app, registration fails for that arrow (logged);
  pick a different modifier in Settings.
- **Not exact Windows compatibility.** The transition table is unit-tested and
  cross-checked against Windows 10/11 semantics, but verify interactive
  behaviour on your real multi-monitor setup before claiming full parity.
