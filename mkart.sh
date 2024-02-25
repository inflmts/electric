#!/usr/bin/env bash
# cover art generator
#
# Requirements:
#   - imagemagick
#   - calc
#

set -ue

echo() { printf '%s\n' "$*"; }
diag() { printf >&2 '%s\n' "$*"; }
warn() { printf >&2 'warning: %s\n' "$*"; }
err() { printf >&2 'error: %s\n' "$*"; }

usage() {
  cat >&2 <<EOF
usage: mkart.sh <output-file>

Generate cover art.
EOF
}

if [[ ${1-} = -- ]]; then
  shift
fi

if (( $# != 1 )); then
  usage
  exit 1
fi

output_file=$1

lightning=$(calc -dpq '
srand(2227438307676295025),
n=20
printf("M250,-10")
for (i=1; i<n; ++i) printf(" %f,%f", rand(200,301), 500*i/n)
printf(" 250,510")
')

polygon() {
  calc -dpq <<EOF
n=$1
r=$2
for (i=0; i<n; ++i) {
  a=i*2*pi()/n;
  printf(" %f,%f", round(-r*sin(a),3), round(-r*cos(a),3));
}
EOF
}

colorscale() {
  local r g b scale
  r=0x${1:0:2}
  g=0x${1:2:2}
  b=0x${1:4:2}
  scale=$2
  printf '%02x%02x%02x' \
    $(calc -dpq "min(255,round($r*$scale));min(255,round($g*$scale));min(255,round($b*$scale))")
}

mvg2="
viewbox 0 0 500 500
push graphic-context
  translate 250 250
  stroke-width 15
  fill #00000060
  push graphic-context
    scale 1 -1
    stroke #$(colorscale 202024 1.5)
    path 'M $(polygon 5 210) Z'
  pop graphic-context
  push graphic-context
    stroke #$(colorscale 202024 2)
    path 'M $(polygon 5 210) Z'
  pop graphic-context
pop graphic-context
push graphic-context
  translate 250 250
  fill #$(colorscale ffe000 0.6)
  path 'M -80,72 -100,22 -100,72 -80,122 Z'
  fill #ffe000
  path 'M -100,-50 -142.069,-33.172 -100,72 -100,22 -117.931,-22.828 -100,-30 Z'
  path 'M -10,-110 -80,-110 -80,-33 -10,-61 Z'
  path 'M -10,-41 -80,-13 -80,122 -10,94 Z'
  fill #$(colorscale ff7800 0.6)
  path 'M 80,-72 100,-22 100,-72 80,-122 Z'
  fill #ff7800
  path 'M 10,41 10,-94 80,-122 80,13 Z'
  path 'M 10,110 80,110 80,33 10,61 Z'
  path 'M 100,50 142.069,33.172 100,-72 100,-22 117.931,22.828 100,30 Z'
pop graphic-context
"

magick -respect-parenthesis -background transparent \
  -size 500x500 canvas:'#202024' \
  \( canvas:transparent -size 250x500 \
     -define gradient:direction=East gradient:transparent-\#504824 -geometry +0+0 -composite \
     -define gradient:direction=West gradient:transparent-\#504824 -geometry +250+0 -composite \
  \) \
  \( canvas:transparent \
     -fill none -stroke '#ffe000' -strokewidth 20 \
     -draw "path '$lightning'" \
     -blur x15 \
  \) \
  \( canvas:transparent \
     -fill none -stroke '#ffe000' -strokewidth 5 \
     -draw "path '$lightning'" \
  \) \
  mvg:fd:12 12<<<"$mvg2" \
  -layers flatten \
  "$output_file"
