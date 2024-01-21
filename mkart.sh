#!/usr/bin/env bash
# cover art generator
#
# Requirements:
#   - imagemagick
#

set -ue

echo() { printf '%s\n' "$*"; }
diag() { printf >&2 '%s\n' "$*"; }
warn() { printf >&2 'warning: %s\n' "$*"; }
err() { printf >&2 'error: %s\n' "$*"; }

usage() {
  cat >&2 <<EOF
usage: mkart.sh <color1> <color2>

Generate cover art.
<color1> and <color2> are six hexadecimal digits in the form rrggbb.
EOF
}

if (( $# == 0 )); then
  color1=ff7800
  color2=ffe000
elif (( $# == 2 )); then
  color1=$1
  color2=$2
else
  usage
  exit 1
fi

if ! [[ $color1 =~ [0-9a-f]{6} ]]; then
  err "invalid color '$color1'"
  exit 1
fi

if ! [[ $color2 =~ [0-9a-f]{6} ]]; then
  err "invalid color '$color2'"
  exit 1
fi

r1=$((0x${color1:0:2}))
g1=$((0x${color1:2:2}))
b1=$((0x${color1:4:2}))
r2=$((0x${color2:0:2}))
g2=$((0x${color2:2:2}))
b2=$((0x${color2:4:2}))
pi=3.14159265358979323846

pentagon() {
  local radius="$1"
  jq -nr --argjson pi "$pi" --argjson r "$radius" \
    'def f: .*$r*1000|round|./1000; [range(5) | .*2*$pi/5 | "\(-sin|f),\(-cos|f)"] | join(" ")'
}

magick -background '#202024' mvg:- /tmp/folder.jpg <<ENDMVG
viewbox 0 0 500 500
fill white
push graphic-context
  translate 250 250
  scale 1 -1
  fill #303036
  path 'M $(pentagon 220) Z M $(pentagon 200) Z'
  scale 1 -1
  fill #38383f
  path 'M $(pentagon 220) Z M $(pentagon 200) Z'
pop graphic-context
push graphic-context
  translate 250 250
  fill rgb($((r1*3/5)),$((g1*3/5)),$((b1*3/5)))
  path 'M -80,72 -100,22 -100,72 -80,122 Z'
  fill rgb($r1,$g1,$b1)
  path 'M -100,-50 -142.069,-33.172 -100,72 -100,22 -117.931,-22.828 -100,-30 Z'
  path 'M -10,-110 -80,-110 -80,-33 -10,-61 Z'
  path 'M -10,-41 -80,-13 -80,122 -10,94 Z'
  fill rgb($((r2*3/5)),$((g2*3/5)),$((b2*3/5)))
  path 'M 80,-72 100,-22 100,-72 80,-122 Z'
  fill rgb($r2,$g2,$b2)
  path 'M 10,41 10,-94 80,-122 80,13 Z'
  path 'M 10,110 80,110 80,33 10,61 Z'
  path 'M 100,50 142.069,33.172 100,-72 100,-22 117.931,22.828 100,30 Z'
pop graphic-context
ENDMVG
