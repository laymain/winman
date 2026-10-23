# WinMan

Keyboard window management for macOS, in the spirit of Windows' `Win + Arrow`:
`⌘⌥ + arrows` snaps the focused window into halves and quarters, maximizes it,
restores it, or minimizes it — depending on where the window is right now.

The extra modifier is configurable (Option, Control or Shift; Option by
default).

## Behaviour

Shortcuts shown with the default modifier (⌥). "Other screen" means the
adjacent display in that direction (see the note below the table).

| State | `⌘⌥↑` | `⌘⌥↓` | `⌘⌥←` | `⌘⌥→` |
|---|---|---|---|---|
| Normal | Maximized | Bottom half | Left half | Right half |
| Maximized | Top half | Normal | Left half | Right half |
| Minimized | Normal | — | — | — |
| Top half | — | Normal | Top-left | Top-right |
| Bottom half | Normal | Minimized | Bottom-left | Bottom-right |
| Left half | Top-left | Bottom-left | Right half (other screen) | Normal |
| Right half | Top-right | Bottom-right | Normal | Left half (other screen) |
| Top-left | Maximized | Left half | Top-right (other screen) | Top-right |
| Top-right | Maximized | Right half | Top-left | Top-left (other screen) |
| Bottom-left | Left half | Minimized | Bottom-right (other screen) | Bottom-right |
| Bottom-right | Right half | Minimized | Bottom-left | Bottom-left (other screen) |

- **Snap** — halves and quarters fill the usable display area (menu bar and
  Dock excluded), flush to the edge. Width and gap are configurable.
- **Maximize** — fills the usable display area. It does not trigger macOS
  full-screen mode; the menu bar and Dock stay reachable.
- **Restore** — returns to the exact position and size the window had before
  it was snapped. Snapped geometry never overwrites the saved restore point.
- **(other screen)** — pressing an arrow while the window already sits against
  that screen edge moves it to the adjacent display in that direction, landing
  on the side facing the original window. With a single display it flips in
  place instead.

The window's state is read from its actual geometry on every key press, so
windows you drag or resize by hand behave like normal windows again.

## Requirements

- macOS 14.0 or later (developed and verified on macOS 27 / Apple Silicon).
- Full Xcode to build the app (the SwiftUI views use macros that aren't in the
  Command Line Tools).
- Accessibility permission, to control other apps' windows.

## Building

### Xcode

```sh
open Package.swift      # Xcode opens the Swift package directly
```

Select the **WinMan** scheme and Run.

### Command line

```sh
./Scripts/make-app.sh      # builds release + assembles build/WinMan.app
open build/WinMan.app
```

The script signs with the local certificate created by
`./Scripts/setup-signing.sh` (run once). Ad-hoc signatures change on every
rebuild, which revokes the Accessibility grant each time; without the
certificate the script falls back to ad-hoc and warns.

## Permissions

WinMan needs **Accessibility** access to move other applications' windows.

1. On first launch the app asks for it. If you dismissed the prompt, open
   **System Settings → Privacy & Security → Accessibility**.
2. Enable **WinMan** in the list. If it's missing, drag `build/WinMan.app`
   from Finder into the list.
3. Quit and relaunch WinMan if it was already running when you granted access.

To revoke, turn the toggle off or remove the entry. The Settings → System tab
shows the current status and opens the right pane for you.

## Usage

WinMan lives entirely in the menu bar — no Dock icon, no main window. Its menu
has an **Enabled** toggle, the current shortcuts, **Settings…**,
**Accessibility Permissions…**, and **Quit**.

### Settings

- **Keyboard Shortcuts** — turn the manager on or off, pick the modifier, and
  enable or disable individual arrows. Changes apply immediately.
- **Window Behavior** — snap width (25–90%, default 50%), optional gap,
  maximize/restore behaviour, and cross-display cycling.
- **System** — Accessibility permission status, a button to open the right
  pane, and grant/revoke instructions.

Settings persist across restarts.

## Testing

```sh
swift test
```

The Swift Testing suite (32 tests) covers all 44 state transitions, snap and
quadrant geometry, state inference (including manually moved windows),
multi-monitor cycling, and restore-point round trips.

`swift test` builds the whole package and needs the full Xcode toolchain. The
core library alone builds with the Command Line Tools:
`swift build --target WinManCore`.

## Distribution

The current signing identity is a local self-signed certificate, so the app
only runs on machines that trust it. Distributing outside the Mac App Store
requires an Apple Developer Program membership, a Developer ID Application
certificate, and notarization. The Mac App Store is not an option — the App
Sandbox blocks controlling other apps' windows.

Either way, every user grants Accessibility access themselves.

## Known limitations

- **The Accessibility API is best-effort.** Some apps (certain Java, Electron
  or games with custom window servers) don't expose standard window controls
  and may ignore position or size writes. WinMan re-asserts size after setting
  position and never fights an app that refuses a change.
- **Native full-screen windows** live in their own Space and can't be moved by
  frame. WinMan detects this and does nothing.
- **Window identity** is keyed on process id + title, because macOS has no
  stable public window id. Several identically-titled windows in one app may
  share a restore point.
- **Shortcut conflicts.** If `⌘ + <modifier> + Arrow` is already claimed by
  macOS or another app, that arrow won't fire (the failure is logged). Pick a
  different modifier in Settings.
