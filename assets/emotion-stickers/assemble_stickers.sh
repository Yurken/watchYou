#!/usr/bin/env bash
set -euo pipefail

# Uses ImageMagick 6 and FFmpeg. Artwork is drawn by imagegen; this script only
# slices fixed cells, converts/encodes formats, and arranges the preview grid.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"
for command_name in convert identify ffmpeg ffprobe zip; do
  command -v "$command_name" >/dev/null || { echo "Missing dependency: $command_name" >&2; exit 1; }
done
mkdir -p gif_512 gif_256 apng_512 frames spritesheets .work
encoding_tmp="$(mktemp -d -t emotion-stickers.XXXXXX)"
trap 'rm -rf "$encoding_tmp"' EXIT

ids=(happy calm sad angry nervous sleepy)
for id in "${ids[@]}"; do
  source_file="spritesheets/$id.png"
  [[ -f "$source_file" ]] || continue
  [[ "$(identify -format '%wx%h' "$source_file")" == '1536x1024' ]] || { echo "Unexpected grid size: $source_file" >&2; exit 1; }
  case "$id" in
    happy)   delays=(50 17 25 18 20 70) ;;
    calm)    delays=(50 25 45 25 20 35) ;;
    sad)     delays=(45 30 30 35 25 35) ;;
    angry)   delays=(42 22 18 22 26 70) ;;
    nervous) delays=(50 16 16 16 22 80) ;;
    sleepy)  delays=(50 25 35 40 25 25) ;;
  esac
  # The sixth generated pose can drift. Retain it as source artwork, but close
  # the loop with the exact first pose instead: 0, 1, 2, 3, 4, 0.
  sequence=(0 1 2 3 4 0)
  mkdir -p "frames/$id" ".work/$id"
  convert "$source_file" -crop 512x512 +repage +adjoin "PNG32:frames/$id/frame_%02d.png"
  for size in 512 256; do
    args=()
    for i in "${!sequence[@]}"; do
      printf -v frame 'frames/%s/frame_%02d.png' "$id" "${sequence[$i]}"
      args+=( '(' -delay "${delays[$i]}" -dispose Background "$frame" -resize "${size}x${size}" -channel A -threshold '50%' +channel ')' )
    done
    convert -background none "${args[@]}" -dither None -colors 256 -loop 0 "gif_$size/$id.gif"
  done
  timeline_file=".work/$id/timeline.ffconcat"
  printf 'ffconcat version 1.0\n' > "$timeline_file"
  for i in "${!sequence[@]}"; do
    printf "file '../../frames/%s/frame_%02d.png'\noption framerate 100\n" "$id" "${sequence[$i]}" >> "$timeline_file"
    printf 'duration %d.%02d\n' "$((delays[i] / 100))" "$((delays[i] % 100))" >> "$timeline_file"
  done
  # APNG muxing seeks back to write the frame count; use a normal temporary
  # filesystem, then copy the finished stream for reliable workspace writes.
  ffmpeg -nostdin -hide_banner -loglevel error -xerror -y -f concat -safe 0 -i "$timeline_file" \
    -fps_mode vfr -plays 0 -final_delay "${delays[5]}/100" -f apng "$encoding_tmp/$id.png"
  [[ "$(ffprobe -v error -count_frames -show_entries stream=nb_read_frames -of default=noprint_wrappers=1:nokey=1 "$encoding_tmp/$id.png")" == 6 ]] || { echo "Invalid APNG: $id" >&2; exit 1; }
  cp "$encoding_tmp/$id.png" "apng_512/$id.png"
  echo "Encoded: $id (6 frames, 2.00 seconds)"
done

all_ready=true
for id in "${ids[@]}"; do
  [[ -f "gif_256/$id.gif" ]] || all_ready=false
done
if [[ "$all_ready" == true ]]; then
  mkdir -p .work/overview
  # Decode actual motion at 10 fps, then compose matching time slices into a
  # 3-column, 2-row preview. No new artwork or synthetic deformation is added.
  for id in "${ids[@]}"; do
    mkdir -p ".work/overview/$id"
    ffmpeg -nostdin -hide_banner -loglevel error -y -ignore_loop 1 -i "gif_256/$id.gif" \
      -vf fps=10 -frames:v 20 ".work/overview/$id/%02d.png"
  done
  for i in $(seq 1 20); do
    printf -v frame_number '%02d' "$i"
    convert \
      '(' ".work/overview/happy/$frame_number.png" ".work/overview/calm/$frame_number.png" ".work/overview/sad/$frame_number.png" +append ')' \
      '(' ".work/overview/angry/$frame_number.png" ".work/overview/nervous/$frame_number.png" ".work/overview/sleepy/$frame_number.png" +append ')' \
      -append +repage -background '#FFFDFC' -alpha remove -alpha off ".work/overview/grid_$frame_number.png"
  done
  convert -delay 10 .work/overview/grid_*.png +repage -loop 0 -layers Optimize overview.gif
  zip -q -r ../watch_you_emotion_stickers.zip gif_512 gif_256 apng_512 frames spritesheets assemble_stickers.sh README.md character_reference.png
  zip -q -u ../watch_you_emotion_stickers.zip overview.gif
  echo 'Created overview.gif and ../watch_you_emotion_stickers.zip'
fi
