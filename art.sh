#!/usr/bin/env bash
# Electric art generator
#
# Dependencies:
#   - imagemagick <https://imagemagick.org>
#

set -u
output_file=${1-folder.jpg}

args=(
  -seed 1369616726
  -size 500x500 -define gradient:radii=353.553,353.553
  radial-gradient:'#ff0050-#800028'

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
      #-compose over -layers flatten
  \) -compose over -composite
  -fill white -stroke none
  -draw 'translate 250 250 path "M 10,-60 -30,15 -5,10 -10,60 30,-15 5,-10 Z"'
  -fill white -stroke none -font Montserrat-Bold -pointsize 40 -kerning 10
  -draw 'gravity center text 0 150 "ELECTRIC"'
)

exec magick "${args[@]}" "$output_file"
