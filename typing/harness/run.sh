#!/usr/bin/env bash
# Usage: run.sh <effect-name> [logo-path] [--reduced] [--no-tint]
# Records the harness into a new private folder and prints where the video,
# the contact sheet and the log are. Nothing is written to a fixed name in a
# shared folder: another user could have put a folder or a symlink there first.
set -u
here=$(cd "$(dirname "$0")" && pwd)
# A name is a file in typing/; it never starts with a dash (an option).
if [[ $# -lt 1 || ! $1 =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "usage: run.sh <effect-name> [logo-path] [--reduced] [--no-tint]" >&2
  exit 2
fi
name=$1; shift
logo=/usr/share/omarchy/logo.svg; reduced=0; tint=1
for a in "$@"; do
  case $a in --reduced) reduced=1 ;; --no-tint) tint=0 ;; *) logo=$a ;; esac
done
tag=$name$([ $reduced = 1 ] && echo -reduced)

# One harness at a time (agents share the screen). Every run has to find the
# same lock, so it can't be in the per-run folder: it lives in this user's
# private runtime folder, and is opened without truncating anything.
runtime=${XDG_RUNTIME_DIR:-}
if [[ $runtime != /* || -L $runtime || ! -d $runtime || ! -O $runtime ]] ||
   [[ ! $(stat -c %a -- "$runtime") =~ ^[0-7]?[0-7][01][01]$ ]]; then
  echo "run.sh: XDG_RUNTIME_DIR must be your own folder that others can't read or write" >&2
  exit 1
fi
exec 9>>"$runtime/hello-lock-fx-harness.lock" || exit 1
flock 9 || exit 1

# A new folder each run, mode 0700, under $TMPDIR or the system default.
dir=$(mktemp -d -t hello-lock-fx.XXXXXXXXXX) || exit 1
out=$dir/fx-$tag.mp4
log=$dir/fx-$tag.log
rec=""; show=""; keep=0
stop() {
  # $1 is a process this script started, $2 the signal that asks it to stop
  # (INT makes the recorder finish its video). A background job starts with
  # INT ignored, so a program that set no handler of its own would not hear
  # it: after 5 s it is killed. Nothing here is waited on forever.
  local pid=$1 i
  [[ -n $pid ]] || return 0
  kill -"$2" "$pid" 2>/dev/null
  for ((i = 0; i < 50; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}
cleanup() {
  # Never leave the effect or the screen recorder running, and keep no
  # half-made results.
  stop "$show" TERM; show=""
  stop "$rec" TERM; rec=""
  [[ $keep = 1 ]] || rm -rf -- "$dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Neither child gets the lock's descriptor (9>&-): a recorder or window left
# behind by a killed script must not hold the lock for every later run.
gpu-screen-recorder -w eDP-1 -f 60 -o "$out" >/dev/null 2>&1 9>&- &
rec=$!
sleep 0.8
# In the background, so Ctrl+C is handled at once: timeout runs in its own
# process group, out of the terminal's reach, and bash would hold a trap until
# a foreground command ended. A trapped signal interrupts wait right away.
HL_EFFECT="$here/../$name.qml" HL_LOGO="$logo" HL_REDUCED=$reduced HL_TINT=$tint \
  timeout 25 qs -p "$here/shell.qml" >"$log" 2>&1 9>&- &
show=$!
wait "$show"; show=""
stop "$rec" INT; rec=""
# The window is 1000x420 logical at top 120, centred; crop it out (any scale).
ffmpeg -loglevel error -y -i "$out" -vf "crop=iw*1000/1536:ih*420/960:(iw-iw*1000/1536)/2:ih*120/960,fps=4,scale=500:-1,tile=6x8" -frames:v 1 "$dir/fx-$tag-sheet.png"
ffmpeg -loglevel error -y -i "$out" -vf "crop=iw*1000/1536:ih*420/960:(iw-iw*1000/1536)/2:ih*120/960" -c:v libx264 -crf 22 "$dir/fx-$tag-crop.mp4"
keep=1
grep -iE "warn|error|qrc|\.qml" "$log" | grep -v "outside of the config folder" | head -20
echo "video: $dir/fx-$tag-crop.mp4  sheet: $dir/fx-$tag-sheet.png  log: $log"
