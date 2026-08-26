# Project maintenance

Normal Tsugumori users can ignore this folder. Nothing here is copied into the
live desktop configuration.

| Path | Purpose |
|---|---|
| `validate.sh` | Runs repository syntax, unit, configuration, and asset checks |
| `update-pins.sh` | Records reviewed package versions for pinned installs |
| `tests/` | Automated tests for the installer and runtime helpers |
| `wave-assets/` | Regenerates the bundled lock-screen animations |

Run validation from the repository root:

```bash
bash maintenance/validate.sh
```

The GitHub Actions workflow runs the same command with the required Arch Linux
integration tools installed.
