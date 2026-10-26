#!/usr/bin/env bash
# Usage: run.sh <effect-name> [logo-path] [--reduced] [--no-tint]
# Records the harness to /tmp/hl/fx-<name>[-reduced].mp4 and a contact sheet.
set -u
here=$(cd "$(dirname "$0")" && pwd)
name=$1; shift
logo=/usr/share/omarchy/logo.svg; reduced=0; tint=1
for a in "$@"; do
  case $a in --reduced) reduced=1 ;; --no-tint) tint=0 ;; *) logo=$a ;; esac
done
tag=$name$([ $reduced = 1 ] && echo -reduced)
mkdir -p /tmp/hl
out=/tmp/hl/fx-$tag.mp4
log=/tmp/hl/fx-$tag.log
# One harness at a time (agents share the screen).
exec 9>/tmp/hl/fx-harness.lock
flock 9
rm -f "$out"
gpu-screen-recorder -w eDP-1 -f 60 -o "$out" >/dev/null 2>&1 &
rec=$!
sleep 0.8
HL_EFFECT="$here/../$name.qml" HL_LOGO="$logo" HL_REDUCED=$reduced HL_TINT=$tint \
  timeout 25 qs -p "$here/shell.qml" >"$log" 2>&1
kill -INT $rec; wait $rec 2>/dev/null
# The window is 1000x420 logical at top 120, centred; crop it out (any scale).
ffmpeg -loglevel error -y -i "$out" -vf "crop=iw*1000/1536:ih*420/960:(iw-iw*1000/1536)/2:ih*120/960,fps=4,scale=500:-1,tile=6x8" -frames:v 1 "/tmp/hl/fx-$tag-sheet.png"
ffmpeg -loglevel error -y -i "$out" -vf "crop=iw*1000/1536:ih*420/960:(iw-iw*1000/1536)/2:ih*120/960" -c:v libx264 -crf 22 "/tmp/hl/fx-$tag-crop.mp4"
grep -iE "warn|error|qrc|\.qml" "$log" | grep -v "outside of the config folder" | head -20
echo "video: /tmp/hl/fx-$tag-crop.mp4  sheet: /tmp/hl/fx-$tag-sheet.png  log: $log"
