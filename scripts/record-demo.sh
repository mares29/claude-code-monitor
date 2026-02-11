#!/bin/bash
# Record a demo GIF for the README
#
# Usage:
#   ./scripts/record-demo.sh          # records full screen
#   ./scripts/record-demo.sh window   # lets you click a window to capture
#
# Steps:
#   1. Start ClaudeMonitor and at least one `claude` CLI session
#   2. Run this script
#   3. Interact with the app for 12-15 seconds:
#      - Show the menu bar dropdown
#      - Click an instance to show the session feed
#      - Scroll through some turns/tool calls
#   4. Press Ctrl+C to stop recording
#   5. The script converts the recording to an optimized GIF

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/docs/assets"
VIDEO_FILE="$OUTPUT_DIR/demo-raw.mov"
GIF_FILE="$OUTPUT_DIR/demo.gif"
PALETTE_FILE="/tmp/claude-monitor-palette.png"

# Clean up previous recordings
rm -f "$VIDEO_FILE" "$GIF_FILE" "$PALETTE_FILE"

echo "╔══════════════════════════════════════════╗"
echo "║       Claude Monitor Demo Recorder       ║"
echo "╠══════════════════════════════════════════╣"
echo "║  1. Make sure ClaudeMonitor is running   ║"
echo "║  2. Have at least one claude session up  ║"
echo "║  3. Press Ctrl+C to stop recording       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

if [[ "${1:-}" == "window" ]]; then
    echo "→ Click on the window you want to capture..."
    screencapture -v -W "$VIDEO_FILE"
else
    echo "→ Recording will start in 3 seconds..."
    echo "  (Position your windows now)"
    sleep 3
    echo "→ Recording... Press Ctrl+C to stop."
    # -v = video mode, -V = timed (seconds), remove -V for manual stop
    screencapture -v "$VIDEO_FILE" &
    RECORD_PID=$!

    # Wait for user to press Ctrl+C
    trap "kill $RECORD_PID 2>/dev/null; wait $RECORD_PID 2>/dev/null" INT
    wait $RECORD_PID 2>/dev/null || true
    trap - INT
fi

if [[ ! -f "$VIDEO_FILE" ]]; then
    echo "✗ No recording found. Did you cancel too early?"
    exit 1
fi

echo ""
echo "→ Converting to GIF..."

# Two-pass encoding for best quality/size ratio:
# Pass 1: Generate optimal color palette from the video
ffmpeg -y -i "$VIDEO_FILE" \
    -vf "fps=12,scale=800:-1:flags=lanczos,palettegen=max_colors=128:stats_mode=diff" \
    "$PALETTE_FILE" 2>/dev/null

# Pass 2: Encode GIF using that palette
ffmpeg -y -i "$VIDEO_FILE" -i "$PALETTE_FILE" \
    -lavfi "fps=12,scale=800:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=3" \
    "$GIF_FILE" 2>/dev/null

# Clean up intermediates
rm -f "$VIDEO_FILE" "$PALETTE_FILE"

# Report
GIF_SIZE=$(du -h "$GIF_FILE" | cut -f1)
echo ""
echo "✓ Demo GIF saved: $GIF_FILE ($GIF_SIZE)"
echo ""
echo "If the file is too large (>5MB for GitHub), re-record a shorter clip"
echo "or reduce quality with: fps=8,scale=640:-1"
