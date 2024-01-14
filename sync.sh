#!/bin/sh
# sync.sh

echo() { printf '%s\n' "$1"; }
diag() { printf >&2 '%s\n' "$1"; }
warn() { printf >&2 'warning: %s\n' "$1"; }
err() { printf >&2 'error: %s\n' "$1"; }

err "incomplete"
diag "Sorry, this utility is still not complete."
diag "Please come back another time."
exit 69

dry_run=

while [ "$#" -gt 0 ]; do
  case $1 in
    -n)
      dry_run=1
      ;;
    -*)
      err "invalid option: $1"
      exit 1
      ;;
  esac
  shift
done

if [ "$#" -ne 2 ]; then
  diag "usage: sync.sh <src> <dest>"
  exit 1
fi

src=$1
dest=$2

rsync_opt() {
  rsync ${dry_run:+-n} -rv --ignore-existing "$1" "$2"
}

local_files=$(ls | grep -E '[0-9a-z-]\.[0-9a-z-]\.mp3')

echo "Exporting files..."
rsync_opt "$src"/ "$dest" || exit 2
echo "Importing files..."
rsync_opt "$dest"/ "$src" || exit 2
