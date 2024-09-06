#!/usr/bin/env python3
########################################
#   Electric music library manager
#---------------------------------------
#
#   Author: Daniel Li
#   Date: Sep 04 2024
#
########################################

from argparse import ArgumentParser
from collections import OrderedDict
import datetime
import hashlib
import os
import re
import shutil
import subprocess
import sys

DEFAULT_ROOT = os.path.dirname(os.path.realpath(__file__))

# regex for group header
RE_GROUP_HEADER = re.compile('\\[([a-z]+)\\]')
# regex for artist and title fields
RE_IDENT = re.compile('[0-9a-z]+(-[0-9a-z]+)*')
# regex for hash field
RE_HASH = re.compile('[0-9a-f]{32}')
# regex for date field
RE_DATE = re.compile('([0-9]{4})-([0-9]{2})-([0-9]{2})')

istty = os.isatty(2)
_err_prefix = '\033[1;31merror:\033[0m' if istty else 'error:'
_warn_prefix = '\033[1;33mwarning:\033[0m' if istty else 'warning:'

def err(message):
    print(f"{_err_prefix} {message}", file=sys.stderr)

def warn(message):
    print(f"{_warn_prefix} {message}", file=sys.stderr)

# Calculate the MD5 hash of a file and return it as a hex string.
# See https://stackoverflow.com/a/59056837
def hash_file(filename):
    with open(filename, 'rb') as file:
        md5 = hashlib.md5()
        while chunk := file.read(65536):
            md5.update(chunk)
    return md5.hexdigest()

def ident_to_pretty(ident):
    return ident.upper().replace('-', ' ')

# Many parts of this script deal with manifest objects.
# A manifest object is an OrderedDict that maps group names to group objects.
# A group object is a dict that maps song IDs (artist, title) to Song objects.
class Song:

    def __init__(self, group, artist, title, hash, date):
        # group
        self.group = group
        # artist ID
        self.artist = artist
        # title ID
        self.title = title
        # MD5 hash as a 32-character hex string
        self.hash = hash
        # date as a date object
        self.date = date

    # Returns the basename of the song file.
    def basename(self):
        return f'{self.artist}.{self.title}.{self.hash}.mp3'

    # Returns the filename relative to the music directory.
    def filename(self):
        return os.path.join(self.group, f'{self.artist}.{self.title}.{self.hash}.mp3')

    def write_manifest(self, file):
        artist = self.artist
        title = self.title
        hash = self.hash
        date = f'{self.date.strftime("%Y-%m-%d")}'
        file.write(f'{artist} {title} {hash} {date}\n')

def tag_file(input_file, output_file, title, artist, album):
    return subprocess.run([
        'ffmpeg', '-y', '-hide_banner', '-loglevel', 'warning',
        '-i', input_file,
        '-codec', 'copy',
        '-map', '0:a',
        '-map_metadata', '-1',
        '-metadata', 'title=' + title,
        '-metadata', 'artist=' + artist,
        '-metadata', 'album=' + album,
        '-bitexact',
        '-f', 'mp3', output_file])

class ManifestParseError(Exception):
    pass

# Reads the manifest from a file object.
def read_manifest(file):
    manifest = OrderedDict()
    line_num = 0
    current_group = None
    current_group_dict = None
    for line in file:
        # increment line number before the loop to catch continue
        line_num += 1
        # remove trailing newline
        line = line[:-1]

        match = RE_GROUP_HEADER.fullmatch(line)
        if match:
            current_group = match.group(1)
            if current_group in manifest:
                raise ManifestParseError(f"Duplicate group header for '{current_group}' at line {line_num}")
            current_group_dict = dict()
            manifest[current_group] = current_group_dict
            continue

        if current_group is None:
            raise ManifestParseError(f"Group header required before line {line_num}")

        fields = line.split(' ')
        if len(fields) != 4:
            raise ManifestParseError(f"Incorrect number of fields at line {line_num}")

        artist = fields[0]
        if not RE_IDENT.fullmatch(artist):
            raise ManifestParseError(f"Invalid artist '{artist}' at line {line_num}")

        title = fields[1]
        if not RE_IDENT.fullmatch(title):
            raise ManifestParseError(f"Invalid title '{title}' at line {line_num}")

        song_id = (artist, title)
        if song_id in current_group_dict:
            raise ManifestParseError(f"Duplicate song '{artist}.{title}' at line {line_num}")

        hash = fields[2]
        match = RE_HASH.fullmatch(hash)
        if not match:
            raise ManifestParseError(f"Invalid hash '{hash}' at line {line_num}")

        date_str = fields[3]
        match = RE_DATE.fullmatch(date_str)
        if not match:
            raise ManifestParseError(f"Invalid date '{date_str}' at line {line_num}")
        date = datetime.date(int(match.group(1)), int(match.group(2)), int(match.group(3)))

        current_group_dict[song_id] = Song(current_group, artist, title, hash, date)

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
    for group, group_dict in manifest.items():
        file.write(f'[{group}]\n')
        for song_id in sorted(group_dict):
            group_dict[song_id].write_manifest(file)

# Save the manifest to a file by name.
# This uses a rename to ensure that errors during writing don't result in a corrupted file.
def save_manifest(filename, manifest):
    temp_filename = filename + '~'
    with open(temp_filename, 'w') as file:
        write_manifest(file, manifest)
    os.replace(temp_filename, filename)

# Save the manifest to a file by name and terminate on failure.
def save_manifest_or_abort(filename, manifest):
    try:
        save_manifest(filename, manifest)
    except OSError as e:
        err(f"failed to save '{filename}': {e.strerror}")
        sys.exit(1)

# Get a file list for a directory as a set.
def get_file_list(dir):
    try:
        return set([file for file in os.listdir(dir) if not file.startswith('.') and file.endswith('.mp3')])
    except FileNotFoundError:
        return set()

# Copy files from the source directories to the target directory as necessary to satisfy the manifest.
# If a file is not found in the target directory,
# it is searched for in the source directories in the order provided.
# If `dry_run` is true, the actual copy is not performed, but output is still printed.
def sync_files(manifest, target_dir, source_dirs, dry_run):
    ok = True

    # ensure the target is an existing directory
    if not os.path.isdir(target_dir):
        err(f"'{target_dir}' is not a directory")
        return False

    for group, group_dict in manifest.items():
        group_dir = os.path.join(target_dir, group)

        # create the group directory if needed
        if not dry_run:
            try:
                os.mkdir(group_dir)
            except FileExistsError:
                pass

        for song_id, song in group_dict.items():
            filename = song.filename()
            target_file = os.path.join(target_dir, filename)
            if not os.path.exists(target_file):
                # search source dirs for the file
                for source_dir in source_dirs:
                    source_file = os.path.join(source_dir, filename)
                    if not os.path.exists(source_file):
                        continue
                    print(f"Copying {filename}")
                    if not dry_run:
                        with open(source_file, 'rb') as source, open(target_file, 'xb') as target:
                            shutil.copyfileobj(source, target)
                    break
                else:
                    warn(f"could not find source for {filename}")
                    ok = False

    return ok

# Returns a list of music files that are not referenced by the manifest.
def find_orphans(manifest, music_root):
    files = []
    for group, group_dict in manifest.items():
        basenames = get_file_list(os.path.join(music_root, group))
        for song in group_dict.values():
            basenames.discard(song.basename())
        for basename in sorted(basenames):
            files.append(os.path.join(group, basename))
    return files

def import_file(manifest, music_root, file):
    print(f"\033[1mImporting {file}\033[0m")

    while True:
        # query for artist
        while True:
            artist = input('Enter artist: ')
            if RE_IDENT.fullmatch(artist):
                break
            err('invalid format, try again')

        # query for title
        while True:
            title = input('Enter title: ')
            if RE_IDENT.fullmatch(title):
                break
            err('invalid format, try again')

        # query for group
        while True:
            group = input('Enter group: ')
            if group in manifest:
                break
            err('invalid group, try again')

        group_dict = manifest[group]
        song_id = (artist, title)
        if song_id not in group_dict:
            break
        err(f'song exists: {group}/{artist}/{title}')

    date = datetime.date.today()

    # automatically generate tags
    artist_pretty = ident_to_pretty(artist)
    title_pretty = ident_to_pretty(title)

    print('Will set tags:')
    print(f'  Title: {title_pretty}')
    print(f'  Artist: {artist_pretty}')
    resp = input(f'Proceed with import [Y/n]? ')

    if not (len(resp) == 0 or resp[0] == 'y' or resp[0] == 'Y'):
        print('Skipped')
        return False

    # tag write to temporary file
    tmpfile = os.path.join(music_root, f'{group}/.{artist}.{title}.mp3~')
    if tag_file(file, tmpfile, title_pretty, artist_pretty, album).returncode != 0:
        sys.exit(1)
    hash = hash_file(tmpfile)

    song = Song(group, artist, title, hash, date)
    group_dict[song_id] = song
    os.rename(tmpfile, os.path.join(music_root, song.filename()))
    os.remove(file)
    return True

def check_integrity(manifest, music_root):
    for group, group_dict in manifest.items():
        index = -1
        for song_id, song in group_dict.items():
            index += 1
            if istty:
                sys.stderr.write(f'\r\033[K[{group}] {index}/{len(group_dict)} ')
            filename = os.path.join(args.music_root, song.filename())
            try:
                actual_hash = hash_file(filename)
            except FileNotFoundError:
                err(f"{group}/{song.artist}.{song.title}: file not found")
                continue
            if actual_hash != song.hash:
                print(f"{group}/{song.artist}.{song.title}: hashes differ")
    if istty:
        sys.stderr.write('\r\033[K')

#---------------------------------------
# Parsing
#---------------------------------------

ap = ArgumentParser(
        prog='electric',
        description='Electric music library manager')
ap.add_argument('-r', '--root', metavar='DIR', default=DEFAULT_ROOT, help=f'root directory (default: {DEFAULT_ROOT})')
ap.add_argument('--music-root', metavar='DIR', help='music directory (default: <root>)')
ap.add_argument('--manifest', metavar='FILE', help='manifest file (default: <root>/manifest.txt)')
ap.set_defaults(func=None)
subparsers = ap.add_subparsers(metavar='command')

#-- import

def command_import(args):
    if args.queue is not None:
        queue_dir = args.queue
    else:
        queue_dir = os.path.join(args.root, 'queue')

    print(f"Queue directory: {queue_dir}")
    manifest = load_manifest_or_abort(args.manifest)
    with os.scandir(queue_dir) as entries:
        for entry in entries:
            if entry.is_file() and not entry.name.startswith('.') and entry.name.endswith('.mp3'):
                if import_file(manifest, args.music_root, os.path.join(queue_dir, entry.name)):
                    save_manifest_or_abort(args.manifest, manifest)

sp = subparsers.add_parser(
        'import',
        help='import new music',
        description='Import music from the queue directory.')
sp.add_argument('queue', nargs='?', help='queue directory (default: <root>/queue)')
sp.set_defaults(func=command_import)

#-- sync

def command_sync(args):
    manifest = load_manifest_or_abort(args.manifest)
    if not sync_files(manifest, args.music_root, args.source, args.dry_run):
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
    if not sync_files(manifest, args.target, [args.music_root], args.dry_run):
        sys.exit(1)

sp = subparsers.add_parser(
        'push',
        help='copy files to destination using local manifest',
        description='Copy files to destination using local manifest.')
sp.add_argument('-n', '--dry-run', action='store_true', help='don\'t do anything, only show what would happen')
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
    for file in find_orphans(manifest, args.music_root):
        print(file)
        if args.delete:
            os.remove(os.path.join(args.music_root, file))

sp = subparsers.add_parser(
        'orphans',
        help='find files not referenced by the manifest',
        description='Find and optionally delete files not referenced by the manifest.')
sp.add_argument('-d', '--delete', action='store_true', help='delete files')
sp.set_defaults(func=command_orphans)

#-- check

def command_check(args):
    manifest = load_manifest_or_abort(args.manifest)
    check_integrity(manifest, args.music_root)

sp = subparsers.add_parser(
        'check',
        help='check integrity of files',
        description='Check integrity of files.')
sp.set_defaults(func=command_check)

#-- tag

def command_tag(args):
    sys.exit(tag_file(
        args.input,
        args.output,
        args.title,
        args.artist,
        args.album).returncode)

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

#---------------------------------------

args = ap.parse_args()
if args.music_root is None:
    args.music_root = args.root
if args.manifest is None:
    args.manifest = os.path.join(args.root, 'manifest.txt')
if args.func is None:
    ap.print_help()
    sys.exit(2)
else:
    args.func(args)
