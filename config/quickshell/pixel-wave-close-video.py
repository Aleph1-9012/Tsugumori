#!/usr/bin/env python3
"""
Pixel Wave Video Generator — HIDE PHASE
═══════════════════════════════════════════════════════════════

Generates an MP4 for the pixel-wave hide phase:
all sepia pixels start visible (a filled screen),
then fade out progressively in a wave from the center.

Usage:
    python pixel_wave_close.py
    python pixel_wave_close.py -w 2560 -H 1440
    python pixel_wave_close.py -d 1.8 -o wave_out.mp4

Dependencies (Arch):
    sudo pacman -S python-pillow python-numpy ffmpeg
═══════════════════════════════════════════════════════════════
"""

import argparse
import math
import os
import random
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import numpy as np
except ImportError:
    sys.exit("❌ numpy is missing: sudo pacman -S python-numpy")

try:
    from PIL import Image  # noqa: F401
except ImportError:
    sys.exit("❌ Pillow is missing: sudo pacman -S python-pillow")

if not shutil.which("ffmpeg"):
    sys.exit("❌ ffmpeg is missing: sudo pacman -S ffmpeg")


# ═══════════════════════════════════════════════════════════════
# PARAMETERS (matching the HTML lockscreen)
# ═══════════════════════════════════════════════════════════════
CELL = 7
STEP = 8
FRONT_W = 1.2
LIFT_MAX = 7.0
SPRING_K = 0.28
SPRING_D = 0.62
WAVE_SPEED = 7.2

BG_R, BG_G, BG_B = 11, 9, 6           # Dark background #0b0906.
SEPIA_R, SEPIA_G, SEPIA_B = 230, 215, 180


# ═══════════════════════════════════════════════════════════════
# DEFAULT OUTPUT DIRECTORY
# ═══════════════════════════════════════════════════════════════
def default_output() -> Path:
    """~/.config/quickshell/videos/wave_close.mp4 (respects XDG_CONFIG_HOME)."""
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "quickshell" / "videos" / "wave_close.mp4"


# ═══════════════════════════════════════════════════════════════
# SIMULATION
# ═══════════════════════════════════════════════════════════════
def build_grid(width: int, height: int):
    cols = width // STEP
    rows = height // STEP
    off_x = (width - cols * STEP) // 2
    off_y = (height - rows * STEP) // 2
    n = cols * rows

    rng = random.Random(42)  # Same seed as reveal for visual consistency.

    target_color = np.array(
        [0.78 + rng.random() * 0.14 for _ in range(n)], dtype=np.float32
    )
    jitter = np.array(
        [(rng.random() - 0.5) * 4.0 for _ in range(n)], dtype=np.float32
    )

    # IMPORTANT: start fully filled (all pixels visible).
    progress = np.ones(n, dtype=np.float32)
    lift = np.zeros(n, dtype=np.float32)
    lift_vel = np.zeros(n, dtype=np.float32)

    return {
        "cols": cols, "rows": rows,
        "off_x": off_x, "off_y": off_y,
        "n": n,
        "target_color": target_color,
        "jitter": jitter,
        "progress": progress,
        "lift": lift,
        "lift_vel": lift_vel,
    }


def max_dist(cx, cy, cols, rows):
    return max(
        math.hypot(cx - c, cy - r)
        for c, r in [(0, 0), (cols - 1, 0), (0, rows - 1), (cols - 1, rows - 1)]
    )


def step_simulation(state, waves, speed_scale: float):
    cols = state["cols"]
    n = state["n"]
    progress = state["progress"]
    lift = state["lift"]
    lift_vel = state["lift_vel"]
    jitter = state["jitter"]

    # 1. Damped spring for lift.
    lift_vel *= SPRING_D
    lift_vel -= SPRING_K * lift * SPRING_D
    lift += lift_vel
    mask = (np.abs(lift) < 0.001) & (np.abs(lift_vel) < 0.001)
    lift[mask] = 0
    lift_vel[mask] = 0

    # Cell coordinates.
    c_idx = np.arange(n) % cols
    r_idx = np.arange(n) // cols

    # 2. Propagation
    for w in waves:
        if w["done"]:
            continue
        w["r"] += WAVE_SPEED * speed_scale
        if w["r"] >= w["max_r"] + FRONT_W * 4:
            w["done"] = True
            continue

        d = np.sqrt((c_idx - w["cx"]) ** 2 + (r_idx - w["cy"]) ** 2)
        df = w["r"] - (d + jitter)
        active = df >= -FRONT_W
        if not np.any(active):
            continue

        t = np.clip((df + FRONT_W) / (FRONT_W * 2), 0.0, 1.0)
        ease = t * t * (3.0 - 2.0 * t)

        if w["dir"] == 1:
            # REVEAL: progress takes the maximum reached value.
            np.maximum(progress, ease * active, out=progress)
        else:
            # HIDE: progress takes the minimum value (1 - ease).
            inv = 1.0 - ease
            np.minimum(progress, np.where(active, inv, progress), out=progress)

        # Lift as the wavefront passes precisely.
        in_front = (df >= -FRONT_W) & (df < FRONT_W)
        can_lift = lift < 0.1
        if w["dir"] == 1:
            ok = progress < 0.6
        else:
            ok = progress > 0.35
        lift_mask = in_front & can_lift & ok
        lift_vel[lift_mask] = LIFT_MAX * 0.55

    return [w for w in waves if not w["done"]]


# ═══════════════════════════════════════════════════════════════
# RENDU
# ═══════════════════════════════════════════════════════════════
def render_frame(state, width: int, height: int) -> np.ndarray:
    img = np.full((height, width, 3), (BG_R, BG_G, BG_B), dtype=np.uint8)

    cols = state["cols"]
    rows = state["rows"]
    off_x = state["off_x"]
    off_y = state["off_y"]
    progress = state["progress"]
    lift = state["lift"]
    target_color = state["target_color"]

    v = np.minimum(1.0, progress * target_color)

    # Two passes: settled pixels, then lifted pixels (z-index order).
    for pass_idx in range(2):
        for r in range(rows):
            for c in range(cols):
                i = r * cols + c
                p = progress[i]
                lv = max(0.0, lift[i])

                if pass_idx == 0 and lv > 0.3:
                    continue
                if pass_idx == 1 and lv <= 0.3:
                    continue
                if p < 0.004 and lv < 0.01:
                    continue

                vi = v[i]
                rr = int(min(255, vi * SEPIA_R))
                gg = int(min(255, vi * SEPIA_G))
                bb = int(min(255, vi * SEPIA_B))

                size = int(CELL + lv + 0.5)
                half = lv / 2.0
                px = off_x + c * STEP - int(half)
                py = off_y + r * STEP - int(half)

                x1 = max(0, px)
                y1 = max(0, py)
                x2 = min(width, px + size)
                y2 = min(height, py + size)
                if x2 > x1 and y2 > y1:
                    img[y1:y2, x1:x2] = (rr, gg, bb)

    return img


# ═══════════════════════════════════════════════════════════════
# VIDEO PIPELINE
# ═══════════════════════════════════════════════════════════════
def generate_video(
    width: int,
    height: int,
    fps: int,
    duration: float,
    output: Path,
    quality: str = "high",
    hold_frames: int = 0,
):
    # Create the output directory if needed.
    output.parent.mkdir(parents=True, exist_ok=True)

    print(f"▸ Mode       : HIDE")
    print(f"▸ Resolution : {width}×{height} @ {fps}fps")
    print(f"▸ Duration   : {duration:.2f}s")
    if hold_frames:
        print(f"▸ Hold init  : {hold_frames} frames")
    print(f"▸ Sortie     : {output}")
    print()

    speed_scale = 60.0 / fps

    state = build_grid(width, height)
    cols = state["cols"]
    rows = state["rows"]

    cx = 0.5 * cols
    cy = 0.5 * rows
    waves = [
        {
            "cx": cx,
            "cy": cy,
            "r": 0.0,
            "max_r": max_dist(cx, cy, cols, rows),
            "dir": -1,           # HIDE
            "done": False,
        }
    ]

    total_frames = int(duration * fps)

    profiles = {
        "high":   ["-crf", "16", "-preset", "slow"],
        "medium": ["-crf", "20", "-preset", "medium"],
        "low":    ["-crf", "26", "-preset", "fast"],
    }

    ffmpeg_cmd = [
        "ffmpeg", "-y",
        "-f", "rawvideo",
        "-vcodec", "rawvideo",
        "-s", f"{width}x{height}",
        "-pix_fmt", "rgb24",
        "-r", str(fps),
        "-i", "-",
        "-an",
        "-vcodec", "libx264",
        "-pix_fmt", "yuv420p",
        *profiles.get(quality, profiles["high"]),
        "-movflags", "+faststart",
        str(output),
    ]

    print("▸ Lancement ffmpeg...")
    proc = subprocess.Popen(
        ffmpeg_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        last_pct = -1

        # Optional: hold a few full frames before triggering the wave.
        for _ in range(hold_frames):
            frame = render_frame(state, width, height)
            proc.stdin.write(frame.tobytes())

        for frame_idx in range(total_frames):
            waves = step_simulation(state, waves, speed_scale)
            frame = render_frame(state, width, height)
            proc.stdin.write(frame.tobytes())

            pct = int(100 * (frame_idx + 1) / total_frames)
            if pct != last_pct:
                bar = "█" * (pct // 2) + "░" * (50 - pct // 2)
                sys.stdout.write(
                    f"\r  [{bar}] {pct:3d}%  ({frame_idx+1}/{total_frames})"
                )
                sys.stdout.flush()
                last_pct = pct

        print()
        proc.stdin.close()
        rc = proc.wait()
        if rc != 0:
            sys.exit(f"\n❌ ffmpeg failed (code {rc})")
    except BrokenPipeError:
        sys.exit("\n❌ ffmpeg closed the pipe prematurely")
    except KeyboardInterrupt:
        proc.terminate()
        sys.exit("\n⚠ Interrupted by the user")

    print()
    print(f"✓ Video generated: {output.resolve()}")
    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"✓ Size          : {size_mb:.2f} MB")


# ═══════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════
def main():
    p = argparse.ArgumentParser(
        description="Generate a Tsugumori pixel-wave video (hide phase).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                            # 1920x1080 60fps 1.8s → ~/.config/quickshell/videos/wave_close.mp4
  %(prog)s -w 2560 -H 1440            # 1440p resolution
  %(prog)s -d 2.2 --fps 60            # 2.2s duration
  %(prog)s --hold 20                  # 20 full-screen frames before the wave
  %(prog)s -q medium -o logout.mp4    # medium quality
        """,
    )
    p.add_argument("-w", "--width", type=int, default=1920, help="width (px)")
    p.add_argument("-H", "--height", type=int, default=1080, help="height (px)")
    p.add_argument("--fps", type=int, default=60, help="frames per second")
    p.add_argument(
        "-d", "--duration", type=float, default=1.8,
        help="hide duration in seconds (default 1.8)",
    )
    p.add_argument(
        "--hold", type=int, default=0,
        help="full frames to hold before triggering the wave (default 0)",
    )
    p.add_argument(
        "-o", "--output", type=Path, default=default_output(),
        help="output file (.mp4) — default: ~/.config/quickshell/videos/wave_close.mp4",
    )
    p.add_argument(
        "-q", "--quality", choices=["low", "medium", "high"], default="high",
        help="encoding quality",
    )
    args = p.parse_args()

    if args.width % STEP != 0 or args.height % STEP != 0:
        print(
            f"⚠ Dimensions {args.width}×{args.height} are not multiples of {STEP} — "
            "minor off-centering is harmless."
        )

    generate_video(
        width=args.width,
        height=args.height,
        fps=args.fps,
        duration=args.duration,
        output=args.output,
        quality=args.quality,
        hold_frames=max(0, args.hold),
    )


if __name__ == "__main__":
    main()
