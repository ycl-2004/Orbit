#!/bin/bash
# Build the README hero animation at photos/demo.gif.
#
# Two modes:
#   scripts/make_demo_gif.sh recording.mov [--start 0] [--duration 8]
#       Convert a real screen recording into an optimized GIF.
#   scripts/make_demo_gif.sh --from-screenshots
#       Rebuild the cross-faded tour from the product screenshots in photos/.
#
# Recording tips for the .mov mode:
#   - Record a 1280x720 region with QuickTime Player (File > New Screen
#     Recording) or `screencapture -v -R x,y,1280,720 demo.mov`.
#   - Keep it under 8 seconds and show one path only: hold Option, the ring
#     appears, move to a card, release to switch.
#   - Slow the cursor down. A GIF at 20fps drops fast pointer movement.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHOTOS_DIR="$PROJECT_DIR/photos"
OUTPUT="$PHOTOS_DIR/demo.gif"
WIDTH=720
FPS=15
COLORS=128

# Screenshot tour: one story line from switching to window picking to file
# actions to settings. Each frame holds HOLD seconds and cross-fades over XFADE.
FRAMES=(
    01-orbit-ring.png
    07-window-preview.png
    08-window-selection.png
    02-file-share.png
    03-file-delete.png
    04-app-exit.png
    05-settings.png
)
HOLD=1.25
XFADE=0.35

usage() {
    cat >&2 <<'EOF'
Usage:
  scripts/make_demo_gif.sh <recording.mov> [--start SECONDS] [--duration SECONDS]
  scripts/make_demo_gif.sh --from-screenshots
EOF
    exit 2
}

require_ffmpeg() {
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "ffmpeg is required. Install it with: brew install ffmpeg" >&2
        exit 1
    fi
}

report_size() {
    local bytes
    bytes=$(stat -f%z "$OUTPUT")
    echo "Wrote $OUTPUT ($(echo "$bytes" | awk '{printf "%.1f MB", $1/1048576}'))"
    if (( bytes > 8388608 )); then
        echo "Warning: over 8 MB. GitHub renders it, but it will load slowly." >&2
        echo "Re-run with a shorter clip, or lower WIDTH/FPS in this script." >&2
    fi
}

# $1 = filter chain producing the final frames.
# $2 = number of -i inputs in the remaining arguments (the palette is appended
#      as the next input, so its stream index equals that count).
# Runs the two-pass palettegen/paletteuse encode into $OUTPUT.
encode_gif() {
    local chain="$1" input_count="$2"
    shift 2
    local palette
    palette="$(mktemp -t orbit-palette).png"

    echo "Pass 1/2: generating color palette..."
    ffmpeg -y -v error "$@" \
        -filter_complex "${chain},palettegen=max_colors=${COLORS}:stats_mode=diff" \
        -frames:v 1 "$palette"

    echo "Pass 2/2: encoding GIF..."
    ffmpeg -y -v error "$@" -i "$palette" \
        -filter_complex "${chain}[x];[x][${input_count}:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
        -loop 0 "$OUTPUT"

    rm -f "$palette"
}

from_screenshots() {
    local inputs=() missing=()
    for frame in "${FRAMES[@]}"; do
        if [[ ! -f "$PHOTOS_DIR/$frame" ]]; then
            missing+=("$frame")
            continue
        fi
        inputs+=(-loop 1 -t "$HOLD" -i "$PHOTOS_DIR/$frame")
    done

    if (( ${#missing[@]} > 0 )); then
        echo "Missing screenshots in photos/: ${missing[*]}" >&2
        exit 1
    fi

    local count=${#FRAMES[@]}
    local chain="" step
    step=$(awk -v h="$HOLD" -v x="$XFADE" 'BEGIN{printf "%.4f", h-x}')

    # Normalize every still to the target width and frame rate first.
    for ((i = 0; i < count; i++)); do
        chain+="[$i:v]scale=${WIDTH}:-2:flags=lanczos,fps=${FPS},format=rgba,setsar=1[v$i];"
    done

    # Chain the cross-fades. Frame k starts fading in at k*(HOLD-XFADE).
    local prev="[v0]" offset
    for ((i = 1; i < count; i++)); do
        offset=$(awk -v s="$step" -v i="$i" 'BEGIN{printf "%.4f", s*i}')
        if (( i == count - 1 )); then
            chain+="${prev}[v$i]xfade=transition=fade:duration=${XFADE}:offset=${offset}"
        else
            chain+="${prev}[v$i]xfade=transition=fade:duration=${XFADE}:offset=${offset}[x$i];"
            prev="[x$i]"
        fi
    done

    local total
    total=$(awk -v h="$HOLD" -v x="$XFADE" -v n="$count" 'BEGIN{printf "%.2f", n*h-(n-1)*x}')
    echo "Building a ${total}s tour from ${count} screenshots at ${WIDTH}px / ${FPS}fps..."
    encode_gif "$chain" "$count" "${inputs[@]}"
    report_size
}

from_recording() {
    local source="$1" start="" duration=""
    shift
    while (( $# > 0 )); do
        case "$1" in
            --start) start="${2:-}"; shift 2 ;;
            --duration) duration="${2:-}"; shift 2 ;;
            *) usage ;;
        esac
    done

    if [[ ! -f "$source" ]]; then
        echo "No such recording: $source" >&2
        exit 1
    fi

    local inputs=()
    [[ -n "$start" ]] && inputs+=(-ss "$start")
    [[ -n "$duration" ]] && inputs+=(-t "$duration")
    inputs+=(-i "$source")

    echo "Converting $source at ${WIDTH}px / ${FPS}fps..."
    encode_gif "[0:v]fps=${FPS},scale=${WIDTH}:-2:flags=lanczos" 1 "${inputs[@]}"
    report_size
}

require_ffmpeg
mkdir -p "$PHOTOS_DIR"

case "${1:-}" in
    "" | -h | --help) usage ;;
    --from-screenshots) from_screenshots ;;
    *) from_recording "$@" ;;
esac
