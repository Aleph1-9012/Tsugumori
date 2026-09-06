# Controls and keybindings

## Desktop shortcuts

| Shortcut | Action |
|---|---|
| `SUPER` | Open the application menu |
| `SUPER + Tab` | Open the Control Center |
| `SUPER + N` | Open or close quick notes on the focused monitor |
| `SUPER + L` | Lock the session |
| `SUPER + T` | Open Kitty |
| `SUPER + Return` | Show or hide the player |
| `SUPER + R` | Restart only the desktop shell |
| `SUPER + P` | Open the wallpaper picker |
| `SUPER + Q` | Close the active window |
| `SUPER + F` | Toggle fullscreen |
| `ALT + Tab` | Cycle through windows |
| `ALT + 1`, `2`, `3`... | Switch workspace |
| `Print` | Take a screenshot |
| `ALT + SHIFT + S` | Select an area for a screenshot |

## Control Center

Open the Control Center with `SUPER + Tab`. Its four areas provide:

- **Connection:** Wi-Fi and Bluetooth
- **Audio and display:** output selection, volume, mute, and per-monitor brightness
- **Quickshare:** send or receive files using HTTP and QR codes
- **Notifications:** history, actions, Do Not Disturb, and Clear All

See the [Quickshare guide](quickshare.md) for transfer steps, limits, and
network-safety information.

Use `W`, `A`, `S`, `D` or the arrow keys to move. Press `Enter` or `Space` to
open the selected item, and press `Esc` to go back or close the menu.

From the center, press a direction to open that side. Inside a panel, use the
same keys to move through its controls.

Choose Brightness to adjust the monitor where the Control Center opened. Drag
or scroll over the slider, or use the left and right keys. Each monitor keeps
its own level for the current login session.

## Quick notes

`SUPER + N` opens the standalone drawer on the focused monitor. Pressing it
again closes it. From another monitor it moves the same drawer
there without changing your note. Escape, the ESC button, or clicking outside
the drawer closes it.

Opening and closing use the Menu's pale curtain wipe and slide transition.
The red hover and selection animations inside the note list are independent.

Choose `+ NEW NOTE`, then type a title and body. Rows use `01// title`
numbering. The selected row stays red; choosing another row lets the previous
row's fill retract. Use the separate X to delete a note and `UNDO` to restore
the last deletion. Undo survives closing the drawer, but ends when the shell
restarts.

Edits save automatically. `SAVING` means a write is pending; `SAVED` means the
latest edit has been acknowledged by storage. `SAVE FAILED` keeps your draft
in memory and offers Retry. Wait for `SAVED` before restarting the shell.

Notes are stored as private, unencrypted text at
`$XDG_DATA_HOME/tsugumori/notes.json`, or
`~/.local/share/tsugumori/notes.json` when that variable is unset. Notes do not
belong to the installed config or the Git repository.

The drawer uses the existing `Settings.scale`. Set
`TSUGUMORI_REDUCED_MOTION=1` in the desktop shell's launch environment to make
the drawer and row/button fill changes immediate. No new Settings fields are
required.
