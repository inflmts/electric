#!/bin/sh
# music library autotagger
#
# Requirements:
#   - stat (coreutils)
#   - id3v2
#

set -u

echo() { printf '%s\n' "$1"; }
diag() { printf >&2 '%s\n' "$1"; }
warn() { printf >&2 'warning: %s\n' "$1"; }
err() { printf >&2 'error: %s\n' "$1"; }

usage() {
  cat >&2 <<EOF
usage: ./tags.sh [<options>...] <dir>

Music library autotagger.

Options:
  --dry         dry run, only show what would happen
  --force       ignore tag log, tag all
  --verbose     show skipped files as well
EOF
}

tab=$(printf '\t')

dry=
force=
verbose=
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
    --force)
      force=1
      ;;
    --verbose)
      verbose=1
      ;;
    -*)
      err "invalid option: $1"
      exit 1
      ;;
    *)
      break
      ;;
  esac
  shift
done

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

dir=$1
cd "$dir"

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

check_tags_helper() {
  local taglog
  taglog=.taglog
  ({
    export LC_ALL=C
    if [ -z "$force" ] && [ -e "$taglog" ]; then
      stat -c '%n:%s.%Y.%Z.%i' -- *.mp3 | comm - "$taglog"
    else
      stat -c '%n:%s.%Y.%Z.%i' -- *.mp3
    fi
  }) | ({
    ret=0
    while IFS= read -r line; do
      case $line in
        "$tab$tab"*)
          # Entry is in both the log file and music directory: skip.
          line=${line#"$tab$tab"}
          file=${line%:*}
          if [ "$verbose" ]; then
            diag " [skip] $file"
          fi
          if [ -z "$dry" ]; then
            echo "$line"
          fi
          ;;
        "$tab"*)
          # Entry no longer exists in music directory: remove entry.
          line=${line#"$tab"}
          file=${line%:*}
          diag " [old]  $file"
          ;;
        *)
          # Entry is not logged: tag music file.
          file=${line%:*}
          name=${file%.mp3}

          if ! contains "$name" .; then
            warn "$name: invalid format, expected artist.title"
            ret=1
            continue
          fi

          artist=$(echo "${name%%.*}" | sed 'y/abcdefghijklmnopqrstuvwxyz/ABCDEFGHIJKLMNOPQRSTUVWXYZ/; s/[^0-9A-Z]\+/ /g')
          title=$(echo "${name#*.}" | sed 'y/abcdefghijklmnopqrstuvwxyz/ABCDEFGHIJKLMNOPQRSTUVWXYZ/; s/[^0-9A-Z]\+/ /g')
          diag " [new]  $file ($artist - $title)"

          if [ -z "$dry" ]; then
            # tag & restat file
            id3v2 -D "$file" >/dev/null \
              && id3v2 -a "$artist" -t "$title" "$file" >/dev/null \
              && stat -c '%n:%s.%Y.%Z.%i' -- "$file" \
              || ret=1
          fi
          ;;
      esac
    done
    exit "$ret"
  })
}

if [ "$dry" ]; then
  diag "note: dry run, no files will be updated"
  check_tags_helper
else
  check_tags_helper > ".taglog.new" \
    && mv .taglog.new .taglog
fi
