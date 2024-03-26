#!/usr/bin/env bash
# sync music library to an MTP device
#
# A simple script for syncing the music library to an MTP device.
#
# Requirements:
#   - aft-mtp-cli (from android-file-transfer)
#

set -ue
LC_COLLATE=C
LC_CTYPE=C
ifs=$IFS

dry=

echo() { printf '%s\n' "$*"; }
msg() { printf >&2 '%s\n' "$*"; }
warn() { printf >&2 'warning: %s\n' "$*"; }
err() { printf >&2 'error: %s\n' "$*"; }

generate_args() {
  local group="$1"
  local dest="$2"

  # load manifest
  local manifest_file="manifest-$group.txt"
  local -A manifest=()
  local -a manifest_ids=()
  local id stat title artist album checksum
  while IFS=: read -r id stat title artist album checksum; do
    manifest[$id]=$checksum
    manifest_ids+=("$id")
  done < "$manifest_file"

  # get file list from device
  IFS=$'\n' ; set -f
  local output
  local -a dest_files
  if output=$(aft-mtp-cli "ls \"$dest\"" 2>&1); then
    dest_files=($(sed '1d; s/.* //' <<< "$output" \
      | grep -Ex '[0-9a-z-]+\.[0-9a-z-]+\.[[:xdigit:]]{32}\.mp3' \
      | LC_COLLATE=C LC_CTYPE=C sort -u))
  elif [[ $output = *'could not find'* ]]; then
    dest_files=()
  else
    err "aft-mtp-cli failed:"
    msg "$output"
    return 1
  fi

  local dest_file
  for dest_file in "${dest_files[@]}"; do
    id=${dest_file%.mp3}
    checksum=${id##*.}
    id=${id%.*}
    if [[ -v manifest[$id] ]] && [[ ${manifest[$id]} = "$checksum" ]]; then
      unset "manifest[$id]"
    else
      remove_args+=("rm \"$dest/$dest_file\"")
    fi
  done

  for id in "${manifest_ids[@]}"; do
    if [[ -v manifest[$id] ]]; then
      send_args+=("put \"$group/$id.mp3\" \"$dest/$id.${manifest[$id]}.mp3\"")
    fi
  done
}

usage() {
  cat <<EOF
usage: send.sh [<options>...]

Sync the music library to an MTP device.

Options:
  --dry         dry run
  --help        show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry)
      dry=1
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

send_args=()
remove_args=()

generate_args main /Music/electric
generate_args extra /Music/electric-extra

if [[ ${#send_args[@]} -gt 0 ]] || [[ ${#remove_args[@]} -gt 0 ]]; then
  args=('cd /Music' 'mkpath electric' 'mkpath electric-extra'
    "${send_args[@]}" "${remove_args[@]}")

  if [[ $dry ]]; then
    printf '%s\n' "${args[@]}"
  else
    aft-mtp-cli "${args[@]}"
  fi
else
  msg "Nothing to do."
fi
