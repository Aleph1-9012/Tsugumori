# Project maintenance

Normal Tsugumori users can ignore this folder. Nothing here is copied into the
live desktop configuration.

| Path | Purpose |
|---|---|
| `validate.sh` | Runs repository syntax, unit, configuration, and asset checks |
| `update-pins.sh` | Records reviewed package versions for pinned installs |
| `tests/` | Automated tests for the installer and runtime helpers |
| `qmltests/` | Offscreen regression tests for lock, picker, and player animations |

Run validation from the repository root:

```bash
bash maintenance/validate.sh
```

The GitHub Actions workflow runs the same command with the required Arch Linux
integration tools installed.

To require every validation tool locally too:

```bash
TSUGUMORI_REQUIRE_INTEGRATION=1 bash maintenance/validate.sh
```

The checks need Bash, Python with Pillow and qrcode, ripgrep, Lua, ShellCheck,
Hyprland, Quickshell, mpv, Qt Declarative, and Qt Shader Tools. Normal local runs
report missing optional tools as skipped. Strict mode fails when one is missing.

The tests use temporary fixtures and offscreen Qt at 1.25 scaling. They do not
lock the live session, authenticate with real credentials, or apply wallpapers.
They cover the native asset checks and fallback, font installation, QR module
integrity, password input, panel geometry, transition reversal, and idle redraws.
The QR checks do not replace scanning the displayed result with a phone.

Player checks cover natural track completion, list wraparound, stale events,
and closing the tracks drawer before hiding the player. Playback tests use
temporary audio files, a private mpv socket, and a null audio output. They never
connect to the live player. Offscreen player tests replace only Quickshell's
environment lookup, since its plugin is embedded in the Quickshell executable.

The GPU-only render test skips on the software renderer. Run it separately in a
GPU-backed display session with `qmltestrunner` and the
`qmltests/lockscreen/tst_PhaseLines.qml` input. Offscreen timeline counts are
diagnostic, not proof of 60 fps on the user's GPU. Tests keep snapshots in memory
instead of writing shared files into `/tmp`.

The native animation shaders ship as source and compiled QSB files under
`config/quickshell/widgets/lockscreen/shaders/`. Rebuild them with the adjacent
`build.sh` after editing the shader source. This requires `qt6-shadertools`.
