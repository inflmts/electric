#!/usr/bin/env bash
# Electric art generator
#
# Dependencies:
#   - imagemagick <https://imagemagick.org>
#

set -u

echo() { printf '%s\n' "$*"; }
msg() { printf >&2 '%s\n' "$*"; }
warn() { printf >&2 'warning: %s\n' "$*"; }
err() { printf >&2 'error: %s\n' "$*"; }

variant=${1-main}

case $variant in
  main)
    background_gradient='#ff0050-#800028'
    ;;
  extra)
    background_gradient='#0050ff-#002880'
    ;;
  *)
    err "invalid variant '$variant'"
    exit 1
    ;;
esac

output_file="${2-art-$variant.jpg}"

args=(
  -seed 1369616726
  -size 500x500 -define gradient:radii=353.553,353.553
  radial-gradient:"$background_gradient"

  \(  canvas:transparent
      -fill none -stroke '#ffffff60' -strokewidth 10
      -draw 'circle 250 250 250 100'
      -stroke '#ffffff40' -strokewidth 20
      -draw 'circle 250 250 250 85'
      \(  -size 200x1 canvas:black -colorspace gray +noise random
          -evaluate pow 3
          -copy 1x1 +199+0
          -define distort:viewport=500x500 -distort polar 353.553,0,250,250
          -compose mathematics -define compose:args=1,-0.5,0,0.5 -size 500x500
          \(  -define gradient:direction=east gradient:white-black -colorspace gray -function polynomial 4,-6,3,0 -clone 0 -composite \)
          \(  -define gradient:direction=south gradient:white-black -colorspace gray -function polynomial 4,-6,3,0 -clone 0 -composite \)
          -delete 0
          -set colorspace srgb
      \)
      -compose displace -define compose:args=75 -composite
  \) -compose over -composite
  -fill white -stroke none
  -draw 'translate 250 250 path "M 10,-60 -30,15 -5,10 -10,60 30,-15 5,-10 Z"'
  -fill white -stroke none -font Montserrat-Bold -pointsize 40 -kerning 10
  -draw 'gravity center text 0 150 "ELECTRIC"'
)

if [[ $variant = extra ]]; then
  args+=(
    -pointsize 20 -kerning 10
    -draw 'gravity center text 0 195 "EXTRA"'
  )
fi

exec magick "${args[@]}" "$output_file"
