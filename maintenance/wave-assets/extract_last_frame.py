#!/usr/bin/env python3
"""Extract the final frame of a video as a PNG maintainer asset."""

import argparse
from pathlib import Path

import cv2


def extract_last_frame(video_path: Path, output_path: Path) -> None:
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise SystemExit(f"Could not open video: {video_path}")

    last_frame = None
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        last_frame = frame
    capture.release()

    if last_frame is None:
        raise SystemExit(f"Video contains no readable frames: {video_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(output_path), last_frame):
        raise SystemExit(f"Could not write image: {output_path}")
    print(f"Extracted final frame: {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path, help="source video")
    parser.add_argument("output", type=Path, help="output PNG")
    args = parser.parse_args()
    extract_last_frame(args.video, args.output)


if __name__ == "__main__":
    main()
