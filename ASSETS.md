# Generated lock assets

The files below are generated outputs of Tsugumori's pixel-wave scripts and
are bundled so the compositor-enforced lock can render on the first login,
before any background repair job runs.

| Asset | Dimensions / duration | SHA-256 |
|---|---|---|
| `config/quickshell/videos/wave_reveal.mp4` | 2560x1600, 60 fps, 2.5 s | `27aa916ecf517f9ae8fd81b01cd2d98540bd871f0157ea8638401ce6f3ed2ac0` |
| `config/quickshell/videos/wave_hide.mp4` | 2560x1600, 60 fps, 1.8 s | `2de71962d6617f1610e1da422a97b31316826cc76d56f2246b013130dc089f09` |
| `config/quickshell/videos/wave_last_frame.png` | 2560x1600 | `b2da90aa03b3600887732977cab6b918ede7e3af58b24bc3e91150f6a9fea3f1` |

They can be regenerated from the repository root with:

```bash
python3 config/quickshell/pixel_wave.py -w 2560 -H 1600 --fps 60 -d 2.5 -q high -o config/quickshell/videos/wave_reveal.mp4
python3 config/quickshell/pixel-wave-close-video.py -w 2560 -H 1600 --fps 60 -d 1.8 -q high -o config/quickshell/videos/wave_hide.mp4
XDG_CONFIG_HOME="$PWD/config" python3 config/quickshell/ext_last_fr.py config/quickshell/videos/wave_reveal.mp4
```

Encoder versions can change MP4 hashes. The table records the binaries tested
with the secure lock on 2026-08-13. These generated assets are distributed
under the repository's MIT license and retain the project's Unit-3 credit in
the README.
