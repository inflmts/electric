#!/usr/bin/env python3
########################################
# Electric music library manager
#---------------------------------------
#
#   Author: Daniel Li
#   Date: Sep 04 2024
#
#   Dependencies:
#     - ffmpeg
#
########################################

from argparse import ArgumentParser
from collections import namedtuple
import datetime
import hashlib
import os
import re
import shutil
import subprocess
import sys
import zlib

DEFAULT_ROOT = os.path.dirname(os.path.realpath(__file__))

# regex for group header
RE_GROUP_HEADER = re.compile('\\[([a-z]+)\\]')
# regex for artist and title fields
RE_IDENT = re.compile('[0-9a-z]+(?:-[0-9a-z]+)*')
# regex for date field
RE_DATE = re.compile('([0-9]{4})-([0-9]{2})-([0-9]{2})')
# regex for file_hash field
RE_FILE_HASH = re.compile('[0-9a-f]{32}')
# regex for tag_hash field
RE_TAG_HASH = re.compile('[0-9a-f]{8}')

Tags = namedtuple('Tags', ['title', 'artist', 'album'])

#---------------------------------------
# Tags
#---------------------------------------

# list of valid groups
GROUPS = ['core', 'extra']

GROUP_ALBUM_NAMES = {
    'core': 'Electric',
    'extra': 'Electric Extra'
}

# The artist name and song title are automatically generated from the artist ID and title ID, respectively,
# by converting them to uppercase and replacing dashes with spaces.
# Most of the time, this works great, however there are a few exceptions.
# These dictionaries can be used to override the automatically generated values.

ARTIST_NAME_OVERRIDES = {
    'a-39': 'A-39',
    'ex-lyd': 'EX-LYD'
}

SONG_TITLE_OVERRIDES = {
    ('camellia', '1f1e33'): '#1F1E33'
}

#---------------------------------------
# Utility Functions
#---------------------------------------

istty = os.isatty(2)

def err(message):
    print(f"{err.prefix} {message}", file=sys.stderr)

def warn(message):
    print(f"{warn.prefix} {message}", file=sys.stderr)

err.prefix = '\033[1;31merror:\033[0m' if istty else 'error:'
warn.prefix = '\033[1;33mwarning:\033[0m' if istty else 'warning:'

# Calculate the MD5 hash of a file and return it as a hex string.
# See https://stackoverflow.com/a/59056837
def get_file_hash(filename):
    with open(filename, 'rb') as file:
        md5 = hashlib.md5()
        while chunk := file.read(65536):
            md5.update(chunk)
    return md5.hexdigest()

# Calculate the tag hash from the given Tags object.
# Returns a 32-bit integer.
def get_tag_hash(tags):
    return 0xffffffff & zlib.crc32(
        tags.title.encode('utf-8') + bytes(0) +
        tags.artist.encode('utf-8') + bytes(0) +
        tags.album.encode('utf-8'))

class Song:
    def __init__(self, group, artist, title, date, file_hash, tag_hash):
        self.group = group
        self.id = (artist, title)
        self.artist = artist
        self.title = title
        self.date = date
        self.file_hash = file_hash
        self.tag_hash = tag_hash

    def __str__(self):
        return f'{self.group}/{self.artist}.{self.title}'

    def get_tags(self):
        title = (SONG_TITLE_OVERRIDES[self.id]
            if self.id in SONG_TITLE_OVERRIDES
            else self.title.upper().replace('-', ' '))
        artist = (ARTIST_NAME_OVERRIDES[self.artist]
            if self.artist in ARTIST_NAME_OVERRIDES
            else self.artist.upper().replace('-', ' '))
        album = GROUP_ALBUM_NAMES[self.group]
        return Tags(title, artist, album)

    def basename(self):
        return f'{self.artist}.{self.title}.{self.file_hash}.mp3'

    def basepath(self):
        return os.path.join(self.group, self.basename())

def tag_file(input_file, output_file, tags):
    subprocess.run([
        'ffmpeg', '-y', '-hide_banner', '-loglevel', 'warning',
        '-i', input_file,
        '-codec', 'copy',
        '-map', '0:a',
        '-map_metadata', '-1',
        '-metadata', 'title=' + tags.title,
        '-metadata', 'artist=' + tags.artist,
        '-metadata', 'album=' + tags.album,
        '-bitexact',
        '-f', 'mp3', output_file], check=True)

class ManifestParseError(Exception):
    pass

# Reads the manifest from a file object.
def read_manifest(file):
    manifest = {group: dict() for group in GROUPS}

    line_num = 0
    current_group = None
    current_group_manifest = None

    for line in file:
        # increment line number before the loop to catch continue
        line_num += 1
        # remove trailing newline
        line = line[:-1]

        match = RE_GROUP_HEADER.fullmatch(line)
        if match:
            group = match.group(1)
            if group not in manifest:
                raise ManifestParseError(f'Invalid group \'{group}\' at line {line_num}')
            current_group = group
            current_group_manifest = manifest[group]
            continue

        if current_group is None:
            raise ManifestParseError(f"Group header required before line {line_num}")

        fields = line.split(' ')
        if len(fields) != 5:
            raise ManifestParseError(f"Incorrect number of fields at line {line_num}")

        artist = fields[0]
        if not RE_IDENT.fullmatch(artist):
            raise ManifestParseError(f"Invalid artist '{artist}' at line {line_num}")

        title = fields[1]
        if not RE_IDENT.fullmatch(title):
            raise ManifestParseError(f"Invalid title '{title}' at line {line_num}")

        song_id = (artist, title)
        if song_id in current_group_manifest:
            raise ManifestParseError(f"Duplicate song '{artist}.{title}' at line {line_num}")

        date_str = fields[2]
        match = RE_DATE.fullmatch(date_str)
        if not match:
            raise ManifestParseError(f"Invalid date '{date_str}' at line {line_num}")
        date = datetime.date(int(match.group(1)), int(match.group(2)), int(match.group(3)))

        file_hash_str = fields[3]
        if not RE_FILE_HASH.fullmatch(file_hash_str):
            raise ManifestParseError(f"Invalid file hash '{file_hash_str}' at line {line_num}")
        file_hash = file_hash_str

        tag_hash_str = fields[4]
        if not RE_TAG_HASH.fullmatch(tag_hash_str):
            raise ManifestParseError(f"Invalid tag hash '{tag_hash_str}' at line {line_num}")
        tag_hash = int(tag_hash_str, 16)

        current_group_manifest[song_id] = Song(current_group, artist, title, date, file_hash, tag_hash)

    return manifest

# Load the manifest from a file by name.
def load_manifest(filename):
    with open(filename, 'r') as file:
        return read_manifest(file)

# Load the manifest from a file by name and terminate on failure.
def load_manifest_or_abort(filename):
    try:
        return load_manifest(filename)
    except OSError as e:
        err(f"failed to load '{filename}': {e.strerror}")
        sys.exit(1)
    except ManifestParseError as e:
        err(f"failed to parse '{filename}': {e}")
        sys.exit(1)

# Write the manifest to a file object.
def write_manifest(file, manifest):
    for group in GROUPS:
        group_manifest = manifest[group]
        file.write(f'[{group}]\n')
        for song_id in sorted(group_manifest):
            song = group_manifest[song_id]
            artist = song.artist
            title = song.title
            date = song.date.strftime("%Y-%m-%d")
            file_hash = song.file_hash
            tag_hash = '%08x' % song.tag_hash

            file.write(f'{artist} {title} {date} {file_hash} {tag_hash}\n')

# Save the manifest to a file by name.
def save_manifest(filename, manifest):
    with open(filename, 'w') as file:
        write_manifest(file, manifest)

# Save the manifest to a file by name and terminate on failure.
def save_manifest_or_abort(filename, manifest):
    try:
        save_manifest(filename, manifest)
    except OSError as e:
        err(f"failed to save '{filename}': {e.strerror}")
        sys.exit(1)

# Copy files from the source directories to the target directory as necessary to satisfy the manifest.
# If a file is not found in the target directory,
# it is searched for in the source directories in the order provided.
# If `dry_run` is true, the actual copy is not performed, but output is still printed.
# TODO: prune
def sync_files(manifest, target_dir, source_dirs, dry_run):
    ok = True

    for group in GROUPS:
        group_manifest = manifest[group]

        # ensure the target group directory exists
        group_dir = os.path.join(target_dir, group)
        if not os.path.isdir(group_dir):
            warn(f"directory '{group_dir}' doesn't exist")
            ok = False
            continue

        for song_id in sorted(group_manifest):
            song = group_manifest[song_id]
            basepath = song.basepath()
            target_file = os.path.join(target_dir, basepath)
            if not os.path.exists(target_file):
                # search source dirs for the file
                for source_dir in source_dirs:
                    source_file = os.path.join(source_dir, basepath)
                    if not os.path.exists(source_file):
                        continue
                    print(f"Copying {song}")
                    if not dry_run:
                        with open(source_file, 'rb') as source, open(target_file, 'xb') as target:
                            shutil.copyfileobj(source, target)
                    break
                else:
                    warn(f"could not find source for {song}")
                    ok = False

    return ok

# Returns a list of music files that are not referenced by the manifest.
def find_orphans(manifest, music_dir):
    files = []
    for group in GROUPS:
        group_manifest = manifest[group]
        try:
            basenames = set([file for file in os.listdir(os.path.join(music_dir, group)) if not file.startswith('.') and file.endswith('.mp3')])
        except FileNotFoundError:
            basenames = set()
        basenames.difference_update(song.basename() for song in group_manifest.values())
        for basename in sorted(basenames):
            files.append(os.path.join(group, basename))
    return files

#---------------------------------------
# Parsing
#---------------------------------------

parser = ArgumentParser(
        prog='electric',
        description='Electric music library manager')
parser.add_argument('-r', '--root', metavar='DIR', default=DEFAULT_ROOT, help=f'root directory (default: {DEFAULT_ROOT})')
parser.add_argument('--music-dir', metavar='DIR', help='music directory (default: <root>)')
parser.add_argument('--manifest', metavar='FILE', help='manifest file (default: <root>/manifest.txt)')
parser.set_defaults(func=None)
subparsers = parser.add_subparsers(metavar='command')

#-- update

RE_MUSIC_FILE = re.compile('([0-9a-z]+(?:-[0-9a-z]+)*)\\.([0-9a-z]+(?:-[0-9a-z]+)*)\\.([0-9a-f]{32})\\.mp3')
RE_QUEUE_FILE = re.compile('([0-9a-z]+(?:-[0-9a-z]+)*)\\.([0-9a-z]+(?:-[0-9a-z]+)*)\\.mp3')

def command_update(args):
    manifest = load_manifest_or_abort(args.manifest)

    retag = []

    for group in GROUPS:
        group_manifest = manifest[group]
        group_dir = os.path.join(args.music_dir, group)

        music_files = set()
        queue_files = set()
        extraneous_files = set()

        for file in os.listdir(group_dir):
            if file.startswith('.') or not file.endswith('.mp3'):
                continue
            match = RE_MUSIC_FILE.fullmatch(file)
            if match:
                music_files.add((file, match.group(1), match.group(2), match.group(3)))
                continue
            match = RE_QUEUE_FILE.fullmatch(file)
            if match:
                queue_files.add((file, match.group(1), match.group(2)))
                continue
            extraneous_files.add(file)

        for song_id in sorted(group_manifest):
            song = group_manifest[song_id]
            tags = song.get_tags()
            expected_hash = get_tag_hash(tags)
            if song.tag_hash != expected_hash:
                print(f"retag: {song}")
                print(f"  title: {tags.title}")
                print(f"  artist: {tags.artist}")
                print(f"  album: {tags.album}")
                retag.append((song, tags, expected_hash))

    resp = input('Proceed [Y/n]? ')
    if not (len(resp) == 0 or resp[0] == 'y' or resp[0] == 'Y'):
        print('Cancelled')
        return False

    try:
        for song, tags, expected_hash in retag:
            print(f"Retagging {song}")
            src_file = os.path.join(args.music_dir, song.basepath())
            temp_file = src_file + '~'
            tag_file(src_file, temp_file, tags)
            song.file_hash = get_file_hash(temp_file)
            song.tag_hash = expected_hash
            dest_file = os.path.join(args.music_dir, song.basepath())
            os.replace(temp_file, dest_file)
            os.remove(src_file)
    finally:
        save_manifest_or_abort(args.manifest, manifest)

    return True


sp = subparsers.add_parser(
    'update',
    help='update file tags and the manifest',
    description='Update file tags and the manifest.')
sp.add_argument('--auto', help='do not prompt for confirmation')
sp.set_defaults(func=command_update)

#-- sync

def command_sync(args):
    manifest = load_manifest_or_abort(args.manifest)
    if not sync_files(manifest, args.music_dir, args.source, args.dry_run):
        sys.exit(1)

sp = subparsers.add_parser(
    'sync',
    help='copy files from source directories using manifest',
    description='Copies files from one or more source directories as necessary to satisfy the manifest.')
sp.add_argument('-n', '--dry-run', action='store_true', help='don\'t do anything, only show what would happen')
sp.add_argument('source', nargs='+', help='source directories')
sp.set_defaults(func=command_sync)

#-- push

def command_push(args):
    manifest = load_manifest_or_abort(args.manifest)
    if not sync_files(manifest, args.target, [args.music_dir], args.dry_run):
        sys.exit(1)
    if args.prune:
        for file in find_orphans(manifest, args.target):
            print(f"Pruning {file}")
            if not args.dry_run:
                os.remove(os.path.join(args.target, file))

sp = subparsers.add_parser(
    'push',
    help='copy files to destination using local manifest',
    description='Copy files to destination using local manifest.')
sp.add_argument('-n', '--dry-run', action='store_true', help='don\'t do anything, only show what would happen')
sp.add_argument('--prune', action='store_true', help='prune extraneous files')
sp.add_argument('target', help='target directory')
sp.set_defaults(func=command_push)

#-- info

def command_info(args):
    print(f'Manifest: {args.manifest}')
    print('Groups:')
    manifest = load_manifest_or_abort(args.manifest)
    artists = set()
    total_songs = 0
    for group, group_dict in manifest.items():
        print(f'  {group}: {len(group_dict)} songs')
        for song_id in group_dict:
            artists.add(song_id[0])
        total_songs += len(group_dict)
    print(f'{len(artists)} artists, {total_songs} songs')

sp = subparsers.add_parser(
    'info',
    help='print info about the manifest',
    description='Print info about the manifest.')
sp.set_defaults(func=command_info)

#-- orphans

def command_orphans(args):
    manifest = load_manifest_or_abort(args.manifest)
    for file in find_orphans(manifest, args.music_dir):
        print(file)
        if args.delete:
            os.remove(os.path.join(args.music_dir, file))

sp = subparsers.add_parser(
    'orphans',
    help='find files not referenced by the manifest',
    description='Find and optionally delete files not referenced by the manifest.')
sp.add_argument('-d', '--delete', action='store_true', help='delete files')
sp.set_defaults(func=command_orphans)

#-- check

def command_check(args):
    manifest = load_manifest_or_abort(args.manifest)
    ok = True

    for group in GROUPS:
        group_manifest = manifest[group]
        song_ids = sorted(group_manifest)
        for i in range(len(song_ids)):
            song_id = song_ids[i]
            song = group_manifest[song_id]
            if istty and not quiet:
                sys.stderr.write(f'\r\033[K[{group}] {i}/{len(song_ids)} ')
            filename = os.path.join(args.music_dir, song.basepath())
            try:
                file_hash = get_file_hash(filename)
            except FileNotFoundError:
                err(f"{song}: file not found")
                ok = False
                continue
            if file_hash != song.file_hash:
                print(f"{song}: hashes differ")
                ok = False

    if istty and not quiet:
        sys.stderr.write('\r\033[K')
    if not ok:
        sys.exit(1)
    elif not quiet:
        print('OK')

sp = subparsers.add_parser(
    'check',
    help='check integrity of files',
    description='Check integrity of files.')
sp.add_argument('-q', '--quiet', action='store_true', help='suppress progress and informational output')
sp.set_defaults(func=command_check)

#-- tag

def command_tag(args):
    try:
        tag_file(args.input, args.output, Tags(args.title, args.artist, args.album))
    except subprocess.CalledProcessError as e:
        err(f"ffmpeg failed: {e}")

sp = subparsers.add_parser(
    'tag',
    help='tag a music file',
    description='Tag a music file.')
sp.add_argument('input', help='input file')
sp.add_argument('output', help='output file')
sp.add_argument('title', help='title')
sp.add_argument('artist', help='artist')
sp.add_argument('album', help='album')
sp.set_defaults(func=command_tag)

#-- dump

def command_dump(args):
    manifest = load_manifest_or_abort(args.manifest)
    write_manifest(sys.stdout, manifest)

sp = subparsers.add_parser(
    'dump',
    description='Dump the manifest to stdout.')
sp.set_defaults(func=command_dump)

#-- taghash

def command_taghash(args):
    import json
    data = json.loads(subprocess.check_output([
        'ffprobe', '-hide_banner', '-loglevel', 'warning',
        '-output_format', 'json', '-show_entries', 'format_tags',
        args.file]))['format']['tags']
    tag_hash = get_tag_hash(Tags(data['title'], data['artist'], data['album']))
    print('%08x' % tag_hash)

sp = subparsers.add_parser(
    'taghash',
    description='Print the tag hash of a file (currently very slow!)')
sp.add_argument('file', help='music file')
sp.set_defaults(func=command_taghash)

#---------------------------------------

args = parser.parse_args()
if args.music_dir is None:
    args.music_dir = args.root
if args.manifest is None:
    args.manifest = os.path.join(args.root, 'manifest.txt')
if args.func is None:
    parser.print_help()
    sys.exit(2)
else:
    args.func(args)
