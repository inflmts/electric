#!/usr/bin/env bash
# Electric music library manager
#
# Requirements:
#   - bash
#   - ffmpeg
#   - mediainfo
#

set -u
shopt -s nullglob
LC_COLLATE=C
LC_CTYPE=C
ifs=$IFS

metadata_file=metadata.txt

echo() { printf '%s\n' "$*"; }
msg() { printf >&2 '%s\n' "$*"; }
warn() { printf >&2 '\033[1;33mwarning:\033[0m %s\n' "$*"; }
err() { printf >&2 '\033[1;31merror:\033[0m %s\n' "$*"; }

is_valid_title_id() {
  [[ $1 = [0-9a-z]*([0-9a-z-]) ]]
}

is_valid_artist_id() {
  [[ $1 = [0-9a-z]*([0-9a-z-]) ]]
}

tag_file() {
  local input_file="$1"
  local output_file="$2"
  local title="$3"
  local artist="$4"
  local album="$5"
  ffmpeg -n -hide_banner -loglevel warning \
    -i "$input_file" \
    -codec copy \
    -map 0:a \
    -map_metadata -1 \
    -metadata title="$title" \
    -metadata artist="$artist" \
    -metadata album="$album" \
    -bitexact \
    -f mp3 "$output_file"
}

# get_tags_for <id> <group>
#
#   Generates the file tags for a song based on the song ID and group.
#
get_tags_for() {
  local id="$1" group="$2"
  local title_id artist_id

  # The title is generated by converting the title ID to uppercase and
  # replacing dashes with spaces. In addition, if '--' is present in the ID,
  # the part following the '--' is enclosed in parentheses.
  title_id=${id#*.}
  title=$title_id
  if [[ $title = *--* ]]; then
    title="${title%%--*} (${title#*--})"
  fi
  title=${title//-/ }
  title=${title^^}

  # The artist name is generated by converting the artist ID to uppercase and
  # replacing dashes with spaces.
  artist_id=${id%%.*}
  artist=$artist_id
  artist=${artist//-/ }
  artist=${artist^^}

  # A few special cases require manual intervention. DO NOT USE THESE UNLESS
  # ABSOLUTELY NECESSARY. The vast majority of the time, the limited character
  # set is enough to adequately label an artist or song. It is generally
  # acceptable to exclude punctuation like apostrophes, commas, dashes, colons,
  # or even parentheses in song titles. Furthermore, the parentheses logic for
  # '--' covers many cases involving song titles with supplementary
  # information.

  case $artist_id in
    a-39) artist="A-39" ;;
    ex-lyd) artist="EX-LYD" ;;
  esac

  case $id in
    camellia.1f1e33) title="#1F1E33" ;;
  esac

  # The album name is based on the group.
  case $group in
    main) album="Electric" ;;
    extra) album="Electric Extra" ;;
  esac
}

import_file() {
  local input_file="$1"
  local title_id artist_id group sel
  local id output_file title artist album
  local date checksum

  printf '\033[1m%s\033[0m\n' "$input_file:"

  while :; do
    read -r -p 'Title: ' title_id || exit 1
    is_valid_title_id "$title_id" && break
    echo "Invalid title. Try again."
  done

  while :; do
    read -r -p 'Artist: ' artist_id || exit 1
    is_valid_artist_id "$artist_id" && break
    echo "Invalid artist. Try again."
  done

  group=main
  read -r -p 'Flags ([e]xtra): ' sel || exit 1
  if [[ $sel = *e* ]]; then
    group=extra
  fi

  id="$artist_id.$title_id"
  output_file="$group/$id.mp3"

  if [[ -e $output_file ]]; then
    err "output file exists: $output_file"
    exit 1
  fi

  if grep -Eq "^$id " "$metadata_file"; then
    err "metadata already exists for '$id'"
    exit 1
  fi

  get_tags_for "$id" "$group"

  echo "Writing to $output_file"
  echo "Importing $id ($artist - $title - $album)"

  tag_file "$input_file" "$output_file" "$title" "$artist" "$album" || exit 1
  rm "$input_file" || exit 1

  date=$(date '+%Y-%m-%d') || exit 1
  checksum=$(md5sum "$output_file") || exit 1
  checksum=${checksum%% *}

  echo "$id $date $group $checksum" | LC_ALL=C sort -k 1 "$metadata_file" - > "$metadata_file.tmp" || exit 1
  mv "$metadata_file.tmp" "$metadata_file" || exit 1
}

import() {
  queue=(queue/*.mp3)
  if [[ ${#queue[@]} -gt 0 ]]; then
    for file in "${queue[@]}"; do
      import_file "$file"
    done
  fi
}

# check_metadata
#
#   Checks for syntax errors and incorrectly ordered or duplicate keys in the
#   metadata file. The regular expression used is very strict and only allows
#   one space between each field and no leading or trailing whitespace. This
#   check must pass before the metadata file is committed.
#
#   Most commands in this repository assume a valid metadata file. When in
#   doubt, use --check-metadata to make sure this is the case.
#
#   The metadata file has one song per line. Each line has four fields,
#   separated by spaces:
#
#     - The song ID, composed of an artist ID and title ID
#     - The date that the song was added, in the format YYYY-MM-DD
#     - The group (main or extra)
#     - The MD5 checksum of the file (32 hexadecimal digits)
#
#   The metadata file is sorted by song ID.
#
check_metadata() {
  id_pat='[0-9a-z][0-9a-z-]*\.[0-9a-z][0-9a-z-]*'
  date_pat='[0-9]{4}-[0-9]{2}-[0-9]{2}'
  group_pat='(main|extra)'
  checksum_pat='[0-9a-f]{32}'
  ! grep -Envx "$id_pat $date_pat $group_pat $checksum_pat" "$metadata_file" \
    && LC_ALL=C sort -c -u -k 1 "$metadata_file"
}

check_file_tags() {
  local id="$1" group="$2"
  local file title artist album
  local expected_tags actual_tags sel output_file checksum

  file="$group/$id.mp3"
  get_tags_for "$id" "$group"
  expected_tags="$title | $artist | $album"
  actual_tags=$(mediainfo --inform='General;%Title% | %Performer% | %Album%' "$file")

  if [[ $expected_tags = "$actual_tags" ]]; then
    return 0
  fi

  warn "$group/$id: tags differ"
  msg "  Expected: $expected_tags"
  msg "  Actual: $actual_tags"

  if [[ -z $fix ]]; then
    return 1
  fi

  read -r -p 'Fix [y/N]? ' sel || exit 1
  case $sel in
    [Yy]*) ;;
    *) return 1 ;;
  esac

  tag_file "$file" "$file.tmp" "$title" "$artist" "$album" || exit 1
  mv "$file.tmp" "$file" || exit 1
  checksum=$(md5sum "$file" | cut -d ' ' -f 1) || exit 1
  msg "$group/$id: checksum is $checksum"
  sed -E "s/^($id .* )[0-9a-f]{32}$/\\1$checksum/" "$metadata_file" > "$metadata_file.tmp" || exit 1
  mv "$metadata_file.tmp" "$metadata_file" || exit 1
  return 0
}

check_tags() {
  fail=0
  while read -r id date group checksum <&3; do
    check_file_tags "$id" "$group" || fail=1
  done 3< "$metadata_file"
  exit "$fail"
}

check_integrity() {
  awk '{ print $4, $3 "/" $1 ".mp3" }' metadata.txt | md5sum -c
}

usage() {
  cat <<EOF
usage: manage.sh <command> [<options>...]

Electric music library manager

Commands:
  --import          import songs from queue
  --check-metadata  check the syntax of the metadata file
  --check-tags      check file tags
  --check-integrity check that metadata checksums are correct

Options:
  --fix             interactively fix file tags
  --help            show this help
EOF
}

func=
fix=

while [[ $# -gt 0 ]]; do
  case $1 in
    --import)
      func=import
      ;;
    --check-metadata)
      func=check_metadata
      ;;
    --check-tags)
      func=check_tags
      ;;
    --check-integrity)
      func=check_integrity
      ;;
    --fix)
      fix=1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      err "invalid option: $1"
      exit 1
      ;;
  esac
  shift
done

if [[ -z $func ]]; then
  err "no operation specified"
  exit 1
fi

"$func"
