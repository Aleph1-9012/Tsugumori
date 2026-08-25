# Wave asset maintenance

These utilities regenerate the committed lock-animation assets. They are not
installed into a user's Quickshell configuration and are not run at login.

Maintainer dependencies on Arch Linux:

```bash
sudo pacman -S python-numpy python-opencv python-pillow ffmpeg
```

Run the tools from the repository root and write outputs explicitly:

```bash
python3 tools/wave-assets/pixel_wave.py \
  -o config/quickshell/videos/wave_reveal.mp4
python3 tools/wave-assets/pixel-wave-close-video.py \
  -o config/quickshell/videos/wave_hide.mp4
python3 tools/wave-assets/extract_last_frame.py \
  config/quickshell/videos/wave_reveal.mp4 \
  config/quickshell/videos/wave_last_frame.png
```

After regeneration, update the expected hashes in `scripts/validate.sh` only
after visually reviewing the assets and confirming their dimensions.
