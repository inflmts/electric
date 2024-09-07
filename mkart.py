#!/usr/bin/env python3
########################################
# Electric art generator
#---------------------------------------
#
#   Author: Daniel Li
#   Date: Sep 06 2024
#
#   Dependencies:
#     - imagemagick <https://imagemagick.org>
#
########################################

from argparse import ArgumentParser
import os
import subprocess
import sys

root = os.path.dirname(__file__)

parser = ArgumentParser(
        prog='mkart',
        description='Electric art generator')
parser.add_argument('-o', '--output', help='output file')
parser.add_argument('group', nargs='?', default='core', help='name of group (core/extra)')
args = parser.parse_args()

group = args.group
match group:
    case 'core':
        background_gradient = '#ff0050-#800028'
    case 'extra':
        background_gradient = '#0050ff-#002880'
    case _:
        raise Exception(f'Invalid group: \'{group}\'')

output_file = args.output
if output_file is None:
    output_file = os.path.join(root, group, 'folder.jpg')

magick_args = [
    '-seed', '1369616726',
    '-size', '500x500', '-define', 'gradient:radii=353.553,353.553',
    'radial-gradient:' + background_gradient,

    '(',
        'canvas:transparent',
        '-fill', 'none', '-stroke', '#ffffff60', '-strokewidth', '10',
        '-draw', 'circle 250 250 250 100',
        '-stroke', '#ffffff40', '-strokewidth', '20',
        '-draw', 'circle 250 250 250 85',
        '(',
            '-size', '200x1', 'canvas:black', '-colorspace', 'gray', '+noise', 'random',
            '-evaluate', 'pow', '3',
            '-copy', '1x1', '+199+0',
            '-define', 'distort:viewport=500x500', '-distort', 'polar', '353.553,0,250,250',
            '-compose', 'mathematics', '-define', 'compose:args=1,-0.5,0,0.5', '-size', '500x500',
            '(',
                '-define', 'gradient:direction=east', 'gradient:white-black',
                '-colorspace', 'gray', '-function', 'polynomial', '4,-6,3,0',
                '-clone', '0', '-composite',
            ')',
            '(',
                '-define', 'gradient:direction=south', 'gradient:white-black',
                '-colorspace', 'gray', '-function', 'polynomial', '4,-6,3,0',
                '-clone', '0', '-composite',
            ')',
            '-delete', '0',
            '-set', 'colorspace', 'srgb',
        ')',
        '-compose', 'displace', '-define', 'compose:args=75', '-composite',
    ')',
    '-compose', 'over', '-composite',
    '-fill', 'white', '-stroke', 'none',
    '-draw', 'translate 250 250 path "M 10,-60 -30,15 -5,10 -10,60 30,-15 5,-10 Z"',
    '-fill', 'white', '-stroke', 'none', '-font', os.path.join(root, 'montserrat-bold.ttf').replace('\\', '\\\\'),
    '-pointsize', '40', '-kerning', '10',
    '-draw', 'gravity center text 0 150 "ELECTRIC"'
]

if group == 'extra':
    magick_args += [
        '-pointsize', '20', '-kerning', '10',
        '-draw', 'gravity center text 0 195 "EXTRA"'
    ]

sys.exit(subprocess.run(['magick', *magick_args, output_file]).returncode)
