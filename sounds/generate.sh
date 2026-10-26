#!/usr/bin/env bash
# Hello Lock sound pack generator.
# Recreates every sound in this directory from pure synthesis (ffmpeg aevalsrc
# + filters). No sampled or downloaded audio is used.
#
# Sound design (v3): quick, low-register mallet chimes -- soft marimba /
# kalimba / felt-piano style plucks. Fundamentals ~165-440 Hz, a little upper
# partial content for definition (all below ~2.5 kHz), 2-5 ms soft attacks and
# fast natural exponential decays (each note rings ~0.15-0.6 s). Intervals are
# fifths, fourths, octaves and minor-pentatonic colour. No sustained tones,
# drones, pads, swells, sweeps or noise whooshes: every sound is 1-4 discrete
# notes that land on the visual hit and get out of the way.
#
# Output: 48 kHz stereo 16-bit WAV, peak-normalized to -6 dBFS, with a 5 ms
# fade-in and a per-sound fade-out so nothing clicks. A final balancing pass
# matches integrated loudness (EBU R128) across the pack without ever raising
# any sound above the -6 dBFS peak cap.
#
# Usage: ./generate.sh            (regenerates all sounds next to this script)
#        ONLY="unlock-pixels" ./generate.sh
#                                 (only the named sounds, balanced to the median
#                                  loudness of the WAVs already here)
set -euo pipefail

OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SR=48000
TARGET_PEAK=-6

# ---------------------------------------------------------------- helpers ---
# Each helper prints an ffmpeg expression fragment (uses variable t).
# max(0,t-START) keeps exp() finite before a note starts.

mul() { awk "BEGIN{print $1*$2}"; }

# mallet FREQ START AMP [DECAY] [WOOD]
# One plucked/struck note: fundamental + soft octave + a faint marimba-like
# 3.93x partial; the higher a partial, the faster it decays. ~2 ms rise
# (95 % at ~6 ms) then exponential decay (DECAY 1/s; -40 dB after 4.6/DECAY s).
# A tiny noise tick (low-passed later in the graph) gives the mallet strike.
# WOOD (0-1, default 0.3) scales the upper partials and the strike.
mallet() {
  local f=$1 s=$2 a=$3 d=${4:-9} w=${5:-0.3}
  local u="max(0,t-$s)"
  printf '(%s*gte(t,%s)*((1-exp(-%s*500))*exp(-%s*%s)*(sin(2*PI*%s*%s)+%s*exp(-%s*%s)*sin(2*PI*%s*%s)+%s*exp(-%s*%s)*sin(2*PI*%s*%s))+%s*exp(-%s*450)*(random(0)*2-1)))' \
    "$a" "$s" "$u" "$u" "$d" "$f" "$u" \
    "$(mul "$w" 0.8)" "$u" "$(mul "$d" 1.6)" "$(mul "$f" 2)" "$u" \
    "$(mul "$w" 0.4)" "$u" "$(mul "$d" 3.5)" "$(mul "$f" 3.93)" "$u" \
    "$(mul "$w" 0.12)" "$u"
}

# notes "FREQ START AMP DECAY PAN [WOOD]; ..." -> "EXPR_L|EXPR_R"
# PAN -1 (left) .. 0 (centre) .. 1 (right), equal-power-ish.
notes() {
  local l="0" r="0" item f s a d p w gl gr
  IFS=';' read -ra items <<< "$1"
  for item in "${items[@]}"; do
    read -r f s a d p w <<< "$item"
    [[ -z ${f:-} ]] && continue
    gl=$(awk "BEGIN{print $a*sqrt((1-($p))/2)*1.41421}")
    gr=$(awk "BEGIN{print $a*sqrt((1+($p))/2)*1.41421}")
    # right channel a hair sharp for a little width (not a beating hum)
    l+="+$(mallet "$f" "$s" "$gl" "$d" "${w:-0.3}")"
    r+="+$(mallet "$(mul "$f" 1.0012)" "$s" "$gr" "$d" "${w:-0.3}")"
  done
  printf '(%s)|(%s)' "$l" "$r"
}

# Final low-pass on every sound (four cascaded 2-pole filters = 48 dB/oct).
LOWPASS_HZ=${LOWPASS_HZ:-7000}

NAMES=()

# render NAME DURATION FADEOUT GRAPH
# GRAPH is an ffmpeg filter_complex that must end in the label [mix].
# Produces a float file peak-normalized to -6 dBFS; balance() writes the WAVs.
render() {
  local name=$1 dur=$2 fo=$3 graph=$4
  if [[ -n ${ONLY:-} && " $ONLY " != *" $name "* ]]; then return 0; fi
  local raw="$TMP/$name.raw.wav"
  local fost
  fost=$(awk "BEGIN{print $dur-$fo}")
  ffmpeg -hide_banner -loglevel error -y -filter_complex \
    "$graph;[mix]aformat=sample_fmts=fltp:sample_rates=$SR:channel_layouts=stereo,highpass=f=28,lowpass=f=$LOWPASS_HZ,lowpass=f=$LOWPASS_HZ,lowpass=f=$LOWPASS_HZ,lowpass=f=$LOWPASS_HZ,atrim=0:$dur,afade=t=in:d=0.005,afade=t=out:st=$fost:d=$fo[out]" \
    -map '[out]' -c:a pcm_f32le "$raw"
  local peak gain
  # astats is float-aware (volumedetect converts to s16 and would clip >0 dBFS)
  peak=$(peak_db "$raw")
  gain=$(awk "BEGIN{print $TARGET_PEAK-($peak)}")
  ffmpeg -hide_banner -loglevel error -y -i "$raw" \
    -af "volume=${gain}dB" -c:a pcm_f32le "$TMP/$name.pk.wav"
  NAMES+=("$name")
  printf '  %-20s %ss\n' "$name.wav" "$dur"
}

peak_db() {
  ffmpeg -hide_banner -i "$1" -af astats=measure_perchannel=none -f null - 2>&1 |
    sed -n 's/.*Peak level dB: \(-\{0,1\}[0-9.]*\).*/\1/p' | tail -n1
}

# Integrated loudness (LUFS). Short sounds are padded with silence so the
# 400 ms gating blocks can measure them; silence is gated out.
lufs() {
  ffmpeg -hide_banner -nostats -i "$1" -af apad=pad_dur=1,ebur128 -f null - 2>&1 |
    awk '/^ *I:/{v=$2} END{print v}'
}

# balance: every sound is already at -6 dBFS peak. Bring the louder ones down
# to a common target loudness (never up, so the peak cap always holds), then
# write the final 16-bit WAVs.
balance() {
  local n l list="" target gain f
  # ONLY mode: the untouched WAVs set the pack loudness.
  if [[ -n ${ONLY:-} && -z ${LUFS_TARGET:-} ]]; then
    for f in "$OUT"/*.wav; do
      n=$(basename "$f" .wav)
      [[ " $ONLY " == *" $n "* ]] && continue
      list+="$(lufs "$f") "
    done
    LUFS_TARGET=$(printf '%s\n' $list | sort -g | awk '{a[NR]=$1} END{print (NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}')
    list=""
  fi
  for n in "${NAMES[@]}"; do
    l=$(lufs "$TMP/$n.pk.wav")
    printf '%s %s\n' "$n" "$l" >> "$TMP/lufs.txt"
    list+="$l "
  done
  # target = pack median, but never more than 1.5 LU above the quietest sound
  # (which cannot be raised without breaking the peak cap)
  target=${LUFS_TARGET:-$(printf '%s\n' $list | sort -g | awk '{a[NR]=$1} END{m=(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2; if (m>a[1]+1.5) m=a[1]+1.5; print m}')}
  echo "Balancing to ${target} LUFS (louder sounds only; peak cap ${TARGET_PEAK} dBFS)"
  while read -r n l; do
    gain=$(awk "BEGIN{g=$target-($l); if (g>0) g=0; print g}")
    ffmpeg -hide_banner -loglevel error -y -i "$TMP/$n.pk.wav" \
      -af "volume=${gain}dB" -ar $SR -ac 2 -c:a pcm_s16le "$OUT/$n.wav"
  done < "$TMP/lufs.txt"
}

src() { # src EXPR_L|EXPR_R DURATION -> aevalsrc filter
  printf "aevalsrc=exprs='%s':s=%s:d=%s:c=stereo" "$1" "$SR" "$2"
}

ROOM='aecho=0.8:0.4:37|59:0.12|0.07'   # small, short room (no long tail)
TONE='lowpass=f=2400,lowpass=f=2400,highpass=f=120'

# chime NAME DURATION FADEOUT "NOTES" -> render a mallet-note sequence
chime() {
  render "$1" "$2" "$3" "$(src "$(notes "$4")" "$2"),$TONE,$ROOM[mix]"
}

echo "Generating Hello Lock sounds into $OUT"

# Notes (Hz): E3 164.81  G3 196  A3 220  B3 246.94  C4 261.63  D4 293.66
#             E4 329.63  G4 392  A4 440
# Columns: FREQ START AMP DECAY PAN [WOOD]

# lock: muted wooden "off" knock on A3 at 0.60 s, dropping to E3 (silence before)
chime lock 0.9 0.08 "\
220 0.60 1.0 30 0 0.45;\
164.81 0.645 0.7 28 0 0.3"

# unlock-coin: E4 tap, then the coin settles on an A3+E4 fifth at 0.47 s
chime unlock-coin 1.2 0.15 "\
329.63 0.30 0.4 16 -0.3;\
220 0.47 1.0 8.5 0;\
329.63 0.47 0.45 10 0.15"

# unlock-assemble: two low wood knocks (0.04, 0.64), then A3+D4 fourth at 0.95 s
chime unlock-assemble 1.58 0.15 "\
196 0.04 0.55 30 -0.2 0.5;\
220 0.64 0.6 30 0.2 0.5;\
220 0.95 1.0 8.5 0;\
293.66 0.955 0.55 9.5 0"

# unlock-scan: quiet E4 pickup, then D4 with a soft A4 fifth on top at 0.98 s
chime unlock-scan 1.4 0.12 "\
329.63 0.84 0.3 20 -0.3;\
293.66 0.98 1.0 10.5 0;\
440 0.98 0.3 13 0.1"

# unlock-glitch: three stuttered G3 plucks with pitch/timing jitter, resolving
# to a B3+E4 fourth at 0.86 s
chime unlock-glitch 1.42 0.12 "\
196 0.13 0.42 34 -0.4 0.5;\
197.6 0.205 0.32 38 0.4 0.5;\
194.8 0.52 0.38 34 -0.1 0.5;\
246.94 0.86 1.0 8.5 0;\
329.63 0.86 0.5 10 0"

# unlock-heartbeat: soft low knock at 0.05 s, then two chime pulses
# (A3+E4 at 0.76 s, softer A3+D4 at 1.25 s)
chime unlock-heartbeat 1.72 0.12 "\
185 0.05 0.45 32 0 0.5;\
220 0.76 1.0 10 0;\
329.63 0.76 0.4 12 0;\
220 1.25 0.8 10 0;\
293.66 1.25 0.3 12 0"

# unlock-orbit: C4 (left) and D4 (centre-right) lead in, landing at 0.90 s on
# a G3+G4 octave on the right side drifting to centre
chime unlock-orbit 1.52 0.15 "\
261.63 0.62 0.38 18 -0.7;\
293.66 0.76 0.45 18 0.3;\
196 0.90 1.0 8 0.25;\
392 0.90 0.35 10 0"

# unlock-monolith: one solemn G3+D4 fifth with a quiet G4 at 1.0 s
chime unlock-monolith 1.45 0.12 "\
196 1.0 1.0 10.5 0 0.35;\
293.66 1.0 0.6 11.5 0;\
392 1.0 0.22 14 0"

# unlock-particles: tiny quiet plucks scattered L/R, main A3+E4+A4 at 1.0 s
chime unlock-particles 1.6 0.15 "\
440 0.22 0.14 26 -0.6;\
329.63 0.38 0.16 26 0.6;\
392 0.53 0.15 26 -0.4;\
293.66 0.67 0.17 26 0.5;\
261.63 0.81 0.2 24 -0.2;\
220 1.0 1.0 9 0;\
329.63 1.0 0.45 10.5 0;\
440 1.0 0.18 13 0"

# unlock-warp: a quiet G3 passing left->right, landing on a C4+G4 fifth at 0.65 s
chime unlock-warp 1.2 0.15 "\
196 0.50 0.35 22 -0.6;\
261.63 0.65 1.0 9 0.1;\
392 0.65 0.35 11 0"

# unlock-split: G3 on the left, D4 on the right, meeting on a centred G3+D4
# fifth at 0.70 s
chime unlock-split 1.28 0.15 "\
196 0.52 0.45 22 -0.85;\
293.66 0.61 0.45 22 0.85;\
196 0.70 1.0 9 0;\
293.66 0.70 0.6 10 0"

# unlock-pixels: soft wooden ticks, one per landing row of the cascade
# (0.37-0.90 s, panned L/R and slowly brightening), settling on an E3+B3 fifth
# with a quiet E4 at 1.13 s as the real symbol takes over
chime unlock-pixels 1.75 0.15 "\
196 0.37 0.12 34 -0.5 0.6;\
220 0.445 0.13 34 0.5 0.6;\
246.94 0.52 0.14 34 -0.4 0.6;\
293.66 0.595 0.15 34 0.4 0.6;\
329.63 0.67 0.16 34 -0.3 0.6;\
293.66 0.745 0.17 34 0.3 0.6;\
329.63 0.82 0.18 34 -0.2 0.6;\
392 0.895 0.2 32 0.2 0.6;\
164.81 1.13 1.0 8.5 0;\
246.94 1.13 0.55 10 0;\
329.63 1.13 0.25 12 0"

# unlock-legendary: gentle low G3 strike at 0.2 s, then a rising A-minor
# pentatonic figure A3 - D4 - E4 culminating on an A3+E4+A4 chord at 2.2 s
chime unlock-legendary 3.0 0.3 "\
196 0.20 0.5 14 0 0.4;\
220 1.60 0.55 15 -0.35;\
293.66 1.85 0.6 15 0;\
329.63 2.05 0.65 15 0.35;\
220 2.20 1.0 8 0;\
329.63 2.20 0.5 9 0;\
440 2.20 0.3 11 0"

# unlock-short: quick A3 -> D4 two-note tap
chime unlock-short 0.42 0.08 "\
220 0.0 0.8 16 0;\
293.66 0.075 0.8 14 0"

# error: gentle falling "uh-oh" C4 -> A3, short and muted
chime error 0.28 0.05 "\
261.63 0.0 0.9 24 0 0.2;\
220 0.11 1.0 22 0 0.2"

balance
echo "Done."
