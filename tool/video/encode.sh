#!/usr/bin/env bash
# Encode frames recorded by make_video_test.dart into an MP4.
#   tool/video/encode.sh <frames dir> <output.mp4>
set -euo pipefail
frames="$1"; out="$2"
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$frames/frames.txt" \
  -vf "fps=30,format=yuv420p" -c:v libx264 -preset slow -crf 22 -tune stillimage \
  -movflags +faststart "$out"
ffprobe -v error -show_entries format=duration,size -of default=nw=1 "$out"
