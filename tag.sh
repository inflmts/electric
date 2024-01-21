#!/usr/bin/env bash
# music library autotagger
#
# Requirements:
#   - bash
#   - stat (coreutils)
#   - ffmpeg
#

set -ueo pipefail
shopt -s nullglob
export LC_COLLATE=C
export LC_CTYPE=C

echo() { printf '%s\n' "$*"; }
diag() { printf >&2 '%s\n' "$*"; }
warn() { printf >&2 'warning: %s\n' "$*"; }
err() { printf >&2 'error: %s\n' "$*"; }

usage() {
  cat >&2 <<EOF
usage: tag.sh
   or: tag.sh --update-metadata

Electric music library autotagger.
EOF
}

manifest_file=manifest.txt
song_metadata_file=songs.txt
artist_metadata_file=artists.txt

declare -a SONG_IDS
declare -A SONG_TITLES ARTIST_NAMES MANIFEST

func=update_tags
while (( $# > 0 )); do
  case $1 in
    --help)
      usage
      exit 0
      ;;
    -M|--update-metadata)
      func=update_metadata
      ;;
    *)
      err "invalid option: $1"
      exit 1
      ;;
  esac
  shift
done

load_song_ids() {
  local file
  SONG_IDS=()
  for file in files/*; do
    file=${file##*/}
    if [[ $file = +([0-9a-z-]).+([0-9a-z-]).mp3 ]]; then
      SONG_IDS+=("${file%.mp3}")
    fi
  done
}

load_song_metadata() {
  local ln id title
  SONG_TITLES=()
  [[ -e "$song_metadata_file" ]] || return 0

  ln=1
  while read -r id; do
    if [[ $id != ::+([0-9a-z-]).+([0-9a-z-]) ]]; then
      err "failed to load song metadata: invalid header at line $ln"
      return 1
    fi
    id=${id#::}
    (( ++ln ))

    if ! read -r title; then
      err "failed to load song metadata: unexpected end of file"
      return 1
    fi
    if [[ $title = *[a-z]* ]]; then
      err "song titles may only contain uppercase letters ($id line $ln)"
      return 1
    fi
    SONG_TITLES[$id]=$title
    (( ++ln ))
  done < "$song_metadata_file"
}

load_artist_metadata() {
  local ln id name
  ARTIST_NAMES=()
  [[ -e "$artist_metadata_file" ]] || return 0

  ln=1
  while read -r id; do
    if [[ $id != ::+([0-9a-z-]) ]]; then
      err "failed to load artist metadata: invalid header at line $ln"
      return 1
    fi
    id=${id#::}
    (( ++ln ))

    if ! read -r name; then
      err "failed to load artist metadata: unexpected end of file"
      return 1
    fi
    if [[ $name = *[a-z]* ]]; then
      err "artist names may only contain uppercase letters ($id line $ln)"
      return 1
    fi
    ARTIST_NAMES[$id]=$name
    (( ++ln ))
  done < "$artist_metadata_file"
}

load_manifest() {
  local id check
  MANIFEST=()
  [[ -e "$manifest_file" ]] || return 0

  while read -r id check; do
    MANIFEST[$id]=$check
  done < "$manifest_file"
}

update_metadata() {
  local id title name
  local song_metadata_updated artist_metadata_updated

  load_song_ids
  load_song_metadata
  load_artist_metadata

  song_metadata_updated=
  for id in "${SONG_IDS[@]}"; do
    if [[ ! -v SONG_TITLES[$id] ]]; then
      title=${id#*.}
      title=${title//-/ }
      title=${title^^}
      SONG_TITLES[$id]=$title
      diag "Added song: $id ($title)"
      song_metadata_updated=1
    fi
  done

  artist_metadata_updated=
  for id in "${SONG_IDS[@]}"; do
    id=${id%%.*}
    if [[ ! -v ARTIST_NAMES[$id] ]]; then
      name=${id//-/ }
      name=${name^^}
      ARTIST_NAMES[$id]=$name
      diag "Added artist: $id ($name)"
      artist_metadata_updated=1
    fi
  done

  if [[ $song_metadata_updated ]]; then
    diag "Writing song metadata..."
    printf '%s\n' "${!SONG_TITLES[@]}" | sort | while read -r id; do
      echo "::$id"
      echo "    ${SONG_TITLES[$id]}"
    done > "$song_metadata_file.tmp"
    mv "$song_metadata_file.tmp" "$song_metadata_file"
  else
    diag "Song metadata up to date."
  fi

  if [[ $artist_metadata_updated ]]; then
    diag "Writing artist metadata..."
    printf '%s\n' "${!ARTIST_NAMES[@]}" | sort | while read -r id; do
      echo "::$id"
      echo "    ${ARTIST_NAMES[$id]}"
    done > "$artist_metadata_file.tmp"
    mv "$artist_metadata_file.tmp" "$artist_metadata_file"
  else
    diag "Artist metadata up to date."
  fi
}

update_tags() {
  local files stats retag
  local i id title artist album check file

  load_song_ids
  load_song_metadata
  load_artist_metadata
  load_manifest

  # Check for insufficient metadata
  for id in "${SONG_IDS[@]}"; do
    artist_id=${id%%.*}
    if [[ ! -v SONG_TITLES[$id] ]]; then
      err "song has no title: $id"
      return 1
    fi
    if [[ ! -v ARTIST_NAMES[$artist_id] ]]; then
      err "artist has no name: $artist_id"
      return 1
    fi
  done

  # Stat files
  files=("${SONG_IDS[@]/#/files/}")
  files=("${files[@]/%/.mp3}")
  stats=($(stat -c '%s:%Y' "${files[@]}"))

  # Tag files
  retag=()
  i=0
  for id in "${SONG_IDS[@]}"; do
    title=${SONG_TITLES[$id]}
    artist=${ARTIST_NAMES[${id%%.*}]}
    album='/Electric/'
    check="${artist// /_}:${title// /_}:${album// /_}:${stats[i++]}"

    if [[ -v MANIFEST[$id] ]] && [[ ${MANIFEST[$id]} = "$check" ]]; then
      : # skip
    else
      diag " [tag] $artist - $title"
      file="files/$id.mp3"
      ffmpeg -y -hide_banner -loglevel warning \
        -i "$file" \
        -codec copy \
        -map 0:a \
        -map_metadata -1 \
        -metadata title="$title" \
        -metadata artist="$artist" \
        -metadata album="$album" \
        -bitexact \
        -f mp3 "$file.tmp"
      mv "$file.tmp" "$file"
      retag+=("$id")
    fi
  done

  # If any files were tagged, update the manifest
  if (( ${#retag[@]} > 0 )); then
    diag "Updating manifest..."

    # Stat tagged files
    files=("${retag[@]/#/files/}")
    files=("${files[@]/%/.mp3}")
    stats=($(stat -c '%s:%Y' "${files[@]}"))

    # Update manifest entries for tagged files
    i=0
    for id in "${retag[@]}"; do
      title=${SONG_TITLES[$id]}
      artist=${ARTIST_NAMES[${id%%.*}]}
      album='/Electric/'
      check="${artist// /_}:${title// /_}:${album// /_}:${stats[i++]}"
      MANIFEST[$id]=$check
    done

    # Write manifest
    for id in "${SONG_IDS[@]}"; do
      echo "$id ${MANIFEST[$id]}"
    done > "$manifest_file.tmp"
    mv "$manifest_file.tmp" "$manifest_file"
  fi
}

"$func"
