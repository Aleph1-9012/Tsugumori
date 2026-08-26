# Wave asset maintenance

These utilities regenerate the committed lock-screen animations. They are not
installed into a user's Quickshell configuration and are not run at login.

## Bundled outputs

| Asset | Dimensions or duration | SHA-256 |
|---|---|---|
| `config/quickshell/videos/wave_reveal.mp4` | 2560x1600, 60 fps, 2.5 s | `27aa916ecf517f9ae8fd81b01cd2d98540bd871f0157ea8638401ce6f3ed2ac0` |
| `config/quickshell/videos/wave_hide.mp4` | 2560x1600, 60 fps, 1.8 s | `2de71962d6617f1610e1da422a97b31316826cc76d56f2246b013130dc089f09` |
| `config/quickshell/videos/wave_last_frame.png` | 2560x1600 | `b2da90aa03b3600887732977cab6b918ede7e3af58b24bc3e91150f6a9fea3f1` |

## Regenerating the files

Maintainer dependencies on Arch Linux:

```bash
sudo pacman -S python-numpy python-opencv python-pillow ffmpeg
```

Run the tools from the repository root and write outputs explicitly:

```bash
python3 maintenance/wave-assets/pixel_wave.py \
  -o config/quickshell/videos/wave_reveal.mp4
python3 maintenance/wave-assets/pixel-wave-close-video.py \
  -o config/quickshell/videos/wave_hide.mp4
python3 maintenance/wave-assets/extract_last_frame.py \
  config/quickshell/videos/wave_reveal.mp4 \
  config/quickshell/videos/wave_last_frame.png
```

After regeneration, update the expected hashes in `maintenance/validate.sh` only
after visually reviewing the assets and confirming their dimensions.

Encoder versions can change MP4 hashes. The table records the binaries tested
with the secure lock on 2026-08-13. The generated assets are distributed under
the repository's MIT license and retain the project's Unit-3 credit in the
main README.
