#!/usr/bin/env bash
# sync music library to an MTP device
#
# A simple script for syncing the music library to an MTP device.
#
# Requirements:
#   - bash
#   - aft-mtp-cli (from android-file-transfer)
#

set -u
LC_COLLATE=C
LC_CTYPE=C
ifs=$IFS

metadata_file=metadata.txt

echo() { printf '%s\n' "$*"; }
msg() { printf >&2 '%s\n' "$*"; }
warn() { printf >&2 'warning: %s\n' "$*"; }
err() { printf >&2 'error: %s\n' "$*"; }

# get file list from device
process_dest_files() {
  local group="$1" dest="$2"
  local output dest_files
  local dest_file id checksum

  if output=$(aft-mtp-cli ${storage:+"storage \"$storage\""} "ls \"$dest\"" 2>&1); then
    dest_files=($(sed '1d; s/.* //' <<< "$output" \
      | grep -Ex '[0-9a-z-]+\.[0-9a-z-]+\.[[:xdigit:]]{32}\.mp3' \
      | LC_COLLATE=C LC_CTYPE=C sort -u))
  elif [[ $output = *'could not find'* ]]; then
    return
  else
    err "aft-mtp-cli failed:"
    msg "$output"
    exit 1
  fi

  for dest_file in "${dest_files[@]}"; do
    id=${dest_file%.mp3}
    checksum=${id##*.}
    id=${id%.*}
    if [[ -v manifest[$id] ]] && [[ ${manifest[$id]} = "$group $checksum" ]]; then
      unset "manifest[$id]"
    else
      remove_args+=("rm \"$dest/$dest_file\"")
    fi
  done
}

usage() {
  cat <<EOF
usage: send.sh [<options>...]

Sync the music library to an MTP device.

Options:
  --art               send art instead of music
  --dry               dry run
  --storage=<volume>  select storage
  --help              show this help
EOF
}

dry=
storage=
mode=

while [[ $# -gt 0 ]]; do
  case $1 in
    --art)
      mode=art
      ;;
    --dry)
      dry=1
      ;;
    --storage=*)
      storage=${1#*=}
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

common_args=(
  ${storage:+"storage \"$storage\""}
  'cd /Music'
  'mkpath electric'
  'mkpath electric-extra'
)

if [[ $mode = art ]]; then
  args=(
    "${common_args[@]}"
    'put art-main.jpg /Music/electric/folder.jpg'
    'put art-extra.jpg /Music/electric-extra/folder.jpg'
  )
  if [[ $dry ]]; then
    printf '%s\n' "${args[@]}"
  else
    aft-mtp-cli "${args[@]}"
  fi
  exit
fi

send_args=()
remove_args=()

# load manifest
declare -A manifest=()
manifest_ids=()

while read -r id date group checksum; do
  manifest[$id]="$group $checksum"
  manifest_ids+=("$id")
done < "$metadata_file"

process_dest_files main '/Music/electric'
process_dest_files extra '/Music/electric-extra'

for id in "${manifest_ids[@]}"; do
  if [[ -v manifest[$id] ]]; then
    set -- ${manifest[$id]}
    group=$1
    checksum=$2
    case $group in
      main) dest='/Music/electric' ;;
      extra) dest='/Music/electric-extra' ;;
    esac
    send_args+=("put \"$group/$id.mp3\" \"$dest/$id.$checksum.mp3\"")
  fi
done

if [[ ${#send_args[@]} -gt 0 ]] || [[ ${#remove_args[@]} -gt 0 ]]; then
  args=(
    "${common_args[@]}"
    "${send_args[@]}"
    "${remove_args[@]}"
  )
  if [[ $dry ]]; then
    printf '%s\n' "${args[@]}"
  else
    aft-mtp-cli "${args[@]}"
  fi
fi
