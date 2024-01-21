#!/usr/bin/env bash
# sync music library to an MTP device
#
# A simple script for syncing the music library to an MTP device.
#
# Requirements:
#   - aft-mtp-cli (from android-file-transfer)
#

set -ueo pipefail

echo() { printf '%s\n' "$*"; }
diag() { printf >&2 '%s\n' "$*"; }
warn() { printf >&2 'warning: %s\n' "$*"; }
err() { printf >&2 'error: %s\n' "$*"; }

usage() {
  cat >&2 <<EOF
usage: send.sh [<options>...]

Sync the music library to an MTP device.

Options:
  --dry     dry run, only show what would happen
EOF
}

dry=
while (( $# > 0 )); do
  case $1 in
    --help)
      usage
      exit 0
      ;;
    --dry)
      dry=1
      ;;
    *)
      err "invalid option: $1"
      exit 1
      ;;
  esac
  shift
done

manifest_file=manifest.txt
dest=/Music/electric
dest_manifest_file="$dest/.manifest.txt"

declare -A MANIFEST=()

diag 'Retrieving manifest...'
remote_manifest_file=$(mktemp /tmp/manifest.XXXXXX)
trap 'rm -f "$remote_manifest_file"' EXIT HUP INT QUIT TERM

if output=$(aft-mtp-cli "get \"$dest_manifest_file\" \"$remote_manifest_file\"" 2>&1); then
  while read -r id check; do
    MANIFEST[$id]=$check
  done < "$remote_manifest_file"
elif [[ $output != *'could not find'* ]]; then
  err "aft-mtp-cli failed"
  diag "$output"
  exit 1
fi

rm "$remote_manifest_file"
trap - EXIT HUP INT QUIT TERM

send=()
if [[ -e "$manifest_file" ]]; then
  while read -r id check; do
    if [[ ! -v MANIFEST[$id] ]] || [[ ${MANIFEST[$id]} != "$check" ]]; then
      MANIFEST[$id]=$check
      send+=("$id")
    fi
  done < "$manifest_file"
fi

if (( ${#send[@]} > 0 )); then
  args=()
  for id in "${send[@]}"; do
    args+=("put \"files/$id.mp3\" \"$dest/$id.mp3\"")
  done
  args+=("put \"$manifest_file\" \"$dest_manifest_file\"")
  if [[ $dry ]]; then
    printf '%s\n' "${args[@]}"
  else
    aft-mtp-cli >&2 "${args[@]}"
  fi
else
  diag "Nothing to do."
fi
