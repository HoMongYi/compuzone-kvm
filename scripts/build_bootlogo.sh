#!/usr/bin/env bash
# Generate boot splash raw image for ST7789V LCD (240x240 RGB565 little-endian)
# from a source image (typically compuzone.jpg).
#
# Run inside WSL Ubuntu.
#
# Usage:
#   bash scripts/build_bootlogo.sh /mnt/d/Projects/compuzone-kvm/compuzone.jpg
#
# Output:
#   resource/bootlogo.raw   (115200 bytes = 240*240*2)

set -euo pipefail

SRC="${1:-}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${PROJECT_ROOT}/resource/bootlogo.raw"

WIDTH=240
HEIGHT=240
EXPECTED_SIZE=$(( WIDTH * HEIGHT * 2 ))

color_green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
color_cyan()  { printf '\033[0;36m%s\033[0m\n' "$*"; }
fail() { printf '\033[0;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ -n "${SRC}" ]] || fail "Usage: $0 <source-image>"
[[ -f "${SRC}" ]] || fail "Source not found: ${SRC}"

# Ensure ffmpeg is available (smallest, most reliable RGB565 converter)
if ! command -v ffmpeg >/dev/null 2>&1; then
    color_cyan "==> Installing ffmpeg"
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends ffmpeg
fi

color_cyan "==> Converting ${SRC} -> ${OUT} (${WIDTH}x${HEIGHT} RGB565LE)"
mkdir -p "$(dirname "${OUT}")"

# scale to fill (cover), then center-crop to 240x240 — square logo will fit exactly
ffmpeg -y -loglevel error \
    -i "${SRC}" \
    -vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},hflip,vflip" \
    -f rawvideo -pix_fmt rgb565le \
    "${OUT}"

ACTUAL=$(stat -c%s "${OUT}")
[[ "${ACTUAL}" -eq "${EXPECTED_SIZE}" ]] || fail "Output size mismatch: got ${ACTUAL}, expected ${EXPECTED_SIZE}"

color_green "Done: ${OUT} (${ACTUAL} bytes)"
