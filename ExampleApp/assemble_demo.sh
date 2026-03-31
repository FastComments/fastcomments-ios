#!/bin/bash
set -euo pipefail

# FastComments iOS Demo Video Assembly Script
# Requires: brew install ffmpeg
#
# Takes raw segment recordings from segments/ and produces demo_final.mp4
# Adjust trim values after reviewing raw recordings.
#
# NOTE: Text overlays (title cards, labels) require ffmpeg built with libfreetype.
# If drawtext is unavailable, the script skips text-based steps and produces
# a video without title cards or labels. Add these in a video editor.

SEGMENTS_DIR="segments"
TRIMMED_DIR="trimmed"
CARDS_DIR="cards"
OUTPUT="demo_final.mp4"

BG_COLOR="#1a1a2e"
DEFAULT_TRIM_START=3.0
DEFAULT_TRIM_END=1.0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

check_deps() {
    if ! command -v ffmpeg &>/dev/null; then
        echo "ERROR: ffmpeg not found. Install with: brew install ffmpeg"
        exit 1
    fi
}

has_drawtext() {
    ffmpeg -filters 2>/dev/null | grep -q "drawtext"
}

get_duration() {
    ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null | head -1
}

trim_segment() {
    local input="$1" output="$2" name="$3"
    local start="${4:-$DEFAULT_TRIM_START}"
    local end_trim="${5:-$DEFAULT_TRIM_END}"

    local duration
    duration=$(get_duration "$input")
    if [ -z "$duration" ]; then
        echo "  [warn] Could not get duration for $input, copying as-is"
        cp "$input" "$output"
        return
    fi

    local end_time
    end_time=$(echo "$duration - $end_trim" | bc)
    local seg_duration
    seg_duration=$(echo "$end_time - $start" | bc)

    echo "  Trimming $name: ${start}s to ${end_time}s (${seg_duration}s from ${duration}s)"
    # Two-pass: first re-encode .mov with timestamp reset (simctl .mov files
    # have non-monotonic PTS that break seeking), then trim.
    local tmp_fixed="/tmp/fc-trim-${name}.mp4"
    ffmpeg -y -i "$input" -vf "setpts=PTS-STARTPTS" -r 30 \
        -c:v libx264 -pix_fmt yuv420p -crf 20 -preset fast \
        "$tmp_fixed" 2>/dev/null
    ffmpeg -y -ss "$start" -i "$tmp_fixed" -t "$seg_duration" \
        -c:v libx264 -pix_fmt yuv420p -crf 18 \
        "$output" 2>/dev/null
    rm -f "$tmp_fixed"
}

# ---------------------------------------------------------------------------
# Step 0: Setup
# ---------------------------------------------------------------------------
check_deps
mkdir -p "$TRIMMED_DIR" "$CARDS_DIR"

HAS_TEXT=false
if has_drawtext; then
    HAS_TEXT=true
    echo "drawtext filter available — will generate title cards and labels"
else
    echo "NOTE: drawtext filter not available (ffmpeg built without libfreetype)."
    echo "      Skipping title cards and text labels. Add these in a video editor."
    echo "      To get drawtext: brew install ffmpeg (full version with freetype)"
fi

echo ""
echo "=== FastComments Demo Video Assembly ==="
echo ""

# ---------------------------------------------------------------------------
# Step 1: Trim all segments
# ---------------------------------------------------------------------------
echo "--- Step 1: Trimming segments ---"

# Per-segment trim points: trim_segment <input> <output> <name> <trim_start> <trim_end>
# Trim start skips past: xcodebuild overhead, API seeding, app launch, springboard.
# Tune these after reviewing raw recordings.
trim_if_exists() {
    local seg="$1" start="$2" end="$3"
    if [ -f "$SEGMENTS_DIR/${seg}.mov" ]; then
        trim_segment "$SEGMENTS_DIR/${seg}.mov" "$TRIMMED_DIR/${seg}.mp4" "$seg" "$start" "$end"
    else
        echo "  [skip] $seg (not found)"
    fi
}

# Trim aggressively: skip API seeding + app launch + springboard at start,
# and cut the dead tail + teardown at end.
# After re-recording with reduced pauses, adjust these based on actual content.
trim_if_exists 01_beautiful_comments  28 3   # ~14 comments seeded + app launch
trim_if_exists 02_rich_interactions   20 3   # 5 comments seeded + app launch
trim_if_exists 04_live_chat           12 3   # 5 chat msgs seeded + app launch
trim_if_exists 05_social_feed          6 3   # 3 feed posts + app launch
trim_if_exists 06a_theme_flat          6 3
trim_if_exists 06b_theme_card          6 3
trim_if_exists 06c_theme_bubble        6 3
# Dual-sim: trim to first ~70s of content after setup.
# Full recording is ~230s due to sync coordination dead time between phases.
# Further cut dead time between phases in a video editor.
# Dual-sim: skip first 25s (setup + seeding + app launch + springboard),
# keep ~50s of phases content, cut the long coordination tail.
trim_if_exists 03_live_sync_left      25 165
trim_if_exists 03_live_sync_right     25 165

# ---------------------------------------------------------------------------
# Step 2: Composite dual-sim segment side-by-side
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 2: Compositing dual-sim segment ---"

if [ -f "$TRIMMED_DIR/03_live_sync_left.mp4" ] && [ -f "$TRIMMED_DIR/03_live_sync_right.mp4" ]; then
    # NOTE: Label x-positions are derived from scale=460 + pad=500.
    # If you change scale/pad values, update the drawtext x coords to match.
    # Crop phones to remove status bar and home indicator (top 120px, bottom 80px
    # of the original ~2600px), then scale to fill more of the frame.
    # Force both to same dimensions so hstack works across different simulators.
    # Output: two phones at 500x900 each with 40px gap = 1040x900, padded to 1080x900.
    ffmpeg -y \
        -i "$TRIMMED_DIR/03_live_sync_left.mp4" \
        -i "$TRIMMED_DIR/03_live_sync_right.mp4" \
        -filter_complex \
            "[0:v]crop=iw:ih-200:0:120,scale=500:900[l];[1:v]crop=iw:ih-200:0:120,scale=500:900[r];[l]pad=520:900:0:0:color=${BG_COLOR}[lp];[r]pad=520:900:20:0:color=${BG_COLOR}[rp];[lp][rp]hstack=inputs=2" \
        -shortest -c:v libx264 -pix_fmt yuv420p -crf 18 \
        "$TRIMMED_DIR/03_live_sync.mp4" 2>/dev/null
    echo "  Composited dual-sim segment"
else
    echo "  [skip] Dual-sim files not found"
fi

# ---------------------------------------------------------------------------
# Step 3: Title/end cards (only if drawtext available)
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 3: Title/end cards ---"

if $HAS_TEXT; then
    ffmpeg -y -f lavfi -i "color=c=${BG_COLOR}:s=1920x1080:d=3" \
        -vf "drawtext=text='FastComments':fontsize=72:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2-40,drawtext=text='Native iOS SDK':fontsize=36:fontcolor=#8b8ba7:x=(w-text_w)/2:y=(h-text_h)/2+50,fade=t=in:st=0:d=0.5,fade=t=out:st=2.5:d=0.5" \
        -c:v libx264 -pix_fmt yuv420p \
        "$CARDS_DIR/title.mp4" 2>/dev/null
    echo "  Created title card"

    ffmpeg -y -f lavfi -i "color=c=${BG_COLOR}:s=1920x1080:d=4" \
        -vf "drawtext=text='FastComments iOS':fontsize=64:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2-60,drawtext=text='github.com/FastComments/fastcomments-ios':fontsize=28:fontcolor=#6c63ff:x=(w-text_w)/2:y=(h-text_h)/2+20,drawtext=text='SwiftUI | Live Updates | Full Customization':fontsize=22:fontcolor=#8b8ba7:x=(w-text_w)/2:y=(h-text_h)/2+70,fade=t=in:st=0:d=0.5" \
        -c:v libx264 -pix_fmt yuv420p \
        "$CARDS_DIR/endcard.mp4" 2>/dev/null
    echo "  Created end card"
else
    echo "  [skip] drawtext not available — add title/end cards in video editor"
fi

# ---------------------------------------------------------------------------
# Step 4: Theme montage (cross-dissolve between 3 themes)
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 4: Creating theme montage ---"

if [ -f "$TRIMMED_DIR/06a_theme_flat.mp4" ] && \
   [ -f "$TRIMMED_DIR/06b_theme_card.mp4" ] && \
   [ -f "$TRIMMED_DIR/06c_theme_bubble.mp4" ]; then

    # Simple concatenation of theme clips (add cross-dissolves in video editor if desired)
    THEME_LIST="$TRIMMED_DIR/theme_list.txt"
    echo "file '../$TRIMMED_DIR/06a_theme_flat.mp4'" > "$THEME_LIST"
    echo "file '../$TRIMMED_DIR/06b_theme_card.mp4'" >> "$THEME_LIST"
    echo "file '../$TRIMMED_DIR/06c_theme_bubble.mp4'" >> "$THEME_LIST"

    ffmpeg -y -f concat -safe 0 -i "$THEME_LIST" \
        -c:v libx264 -pix_fmt yuv420p -crf 18 \
        "$TRIMMED_DIR/06_theming.mp4" 2>/dev/null
    echo "  Created theme montage"
else
    echo "  [skip] Theme segment files not found"
fi

# ---------------------------------------------------------------------------
# Step 5: Concatenate all segments
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 5: Concatenating final video ---"

CONCAT_LIST="$TRIMMED_DIR/concat_list.txt"
> "$CONCAT_LIST"

# Title card (if available)
[ -f "$CARDS_DIR/title.mp4" ] && echo "file '../$CARDS_DIR/title.mp4'" >> "$CONCAT_LIST"

# Segments in storyboard order
for seg in 01_beautiful_comments 02_rich_interactions 03_live_sync 04_live_chat 05_social_feed 06_theming; do
    if [ -f "$TRIMMED_DIR/${seg}.mp4" ]; then
        echo "file '../$TRIMMED_DIR/${seg}.mp4'" >> "$CONCAT_LIST"
    fi
done

# End card (if available)
[ -f "$CARDS_DIR/endcard.mp4" ] && echo "file '../$CARDS_DIR/endcard.mp4'" >> "$CONCAT_LIST"

PART_COUNT=$(wc -l < "$CONCAT_LIST" | tr -d ' ')
if [ "$PART_COUNT" -lt 2 ]; then
    echo "  Not enough segments to concatenate (found $PART_COUNT). Need at least 2."
    exit 1
fi

echo "  Concatenating $PART_COUNT parts..."
ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" \
    -c:v libx264 -crf 18 -pix_fmt yuv420p \
    -movflags +faststart \
    "$OUTPUT" 2>/dev/null

FINAL_DUR=$(get_duration "$OUTPUT")
echo "  Created: $OUTPUT (${FINAL_DUR}s)"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=== Assembly Complete ==="
echo "Output: $OUTPUT"
echo ""
if ! $HAS_TEXT; then
    echo "MISSING: Title cards, end card, and segment labels (drawtext not available)."
    echo "  Add these in a video editor, or reinstall ffmpeg with freetype support."
    echo ""
fi
echo "AUDIO NOTE: Add UI click sounds and/or background music in a video editor"
echo "(iMovie, DaVinci Resolve, etc.) for the final polished version."
echo ""
echo "To iterate on specific segments:"
echo "  1. Re-record:  python3 record_demo.py --segment 01 --skip-build"
echo "  2. Re-assemble: ./assemble_demo.sh"
