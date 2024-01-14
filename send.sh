#!/bin/sh
# send to phone
#
# A simple script for sending music files to my (FUSE-mounted) phone.
#
# Dependencies:
#   - rsync
#

echo() { printf '%s\n' "$1"; }
diag() { printf >&2 '%s\n' "$1"; }
warn() { printf >&2 'warning: %s\n' "$1"; }
err() { printf >&2 'error: %s\n' "$1"; }
die() { printf >&2 'error: %s\n' "$1"; exit 1; }

usage() {
  cat <<\USAGE
usage: send.sh <src> <dest>

Send music files to a phone.

options:
  --dry     dry run, only show what would happen
  --prune   delete old files
USAGE
}

dry=
delete=
while [ "$#" -gt 0 ]; do
  case $1 in
    --)
      shift
      break
      ;;
    --help)
      usage
      exit 0
      ;;
    --dry)
      dry=1
      ;;
    --prune)
      delete=1
      ;;
    -*)
      die "invalid option: $1"
      ;;
    *)
      break
      ;;
  esac
  shift
done

if [ "$#" -ne 2 ]; then
  usage >&2
  exit 1
fi

src=$1
dest=$2

# -i              itemize output
# --update        only send newer files
# --size-only     ignore times, because mtimes is iffy on mtp mount.
# --inplace       rename tends to fail for some reason
rsync \
  ${dry:+--dry-run} ${delete:+--delete} \
  -i --update --inplace --dirs --include '/*.mp3' --exclude '*' \
  -- "$src/" "$dest"
