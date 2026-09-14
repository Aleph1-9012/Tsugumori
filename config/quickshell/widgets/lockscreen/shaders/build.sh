#!/usr/bin/env bash
set -eu
shader_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
shader_baker="${QSB:-/usr/lib/qt6/bin/qsb}"
for stage in vert frag; do
    "$shader_baker" --glsl '300 es,330' --hlsl 50 --msl 12 \
        -o "$shader_dir/lines.$stage.qsb" "$shader_dir/lines.$stage"
done
