#!/usr/bin/env bash
# music library autotagger
#
# Requirements:
#   - bash
#   - ffmpeg
#

set -ue
shopt -s nullglob
LC_COLLATE=C
LC_CTYPE=C
ifs=$IFS

echo() { printf '%s\n' "$*"; }
msg() { printf >&2 '%s\n' "$*"; }
warn() { printf >&2 'warning: %s\n' "$*"; }
err() { printf >&2 'error: %s\n' "$*"; }

get_song_info() {
  local id="$1" group="$2"
  local song_id="${id#*.}"
  local artist_id="${id%%.*}"

  title=${song_id//-/ }
  title=${title^^}

  artist=${artist_id//-/ }
  artist=${artist^^}

  case $group in
    main) album="Electric" ;;
    extra) album="Electric Extra" ;;
    *) err "invalid group '$group'"; exit 1 ;;
  esac

  # special cases

  title=${title/% LOOP/ (LOOP)}
  title=${title/% VIP/ (VIP)}

  case $artist_id in
    killer-fx)
      artist="KILLER-FX"
      ;;
    ex-lyd)
      artist="EX-LYD"
      ;;
  esac

  case $id in
    au5.moonland-derpcat-remix)
      title="MOONLAND (DERPCAT REMIX)"
      ;;
    camellia.1f1e33)
      title="#1f1E33"
      ;;
    camellia.mystery-circles-ultra-uufo)
      title="MYSTERY CIRCLES ULTRA / U.U.F.O."
      ;;
    camellia.tera-io)
      title="TERA I/O"
      ;;
    creo.showdown)
      album="InfiniteLimits Official Theme Song"
      ;;
    illenium.dont-give-up-on-me)
      title="DON'T GIVE UP ON ME"
      ;;
    redsoul92.if-youd-only-listened-for-a-while)
      title="IF YOU'D ONLY LISTENED FOR A WHILE"
      ;;
    teminite.goin-in)
      title="GOIN' IN"
      ;;
    teminite.party-like-its-1923)
      title="PARTY LIKE IT'S 1923"
      ;;
  esac
}

update_group() {
  local group="$1"
  local manifest_file="manifest-$group.txt"

  # get a list of songs
  local ids files basename
  ids=()
  files=()
  for file in "$group"/*; do
    basename=${file#*/}
    if [[ $basename = +([0-9a-z-]).+([0-9a-z-]).mp3 ]]; then
      ids+=("${basename%.mp3}")
      files+=("$file")
    fi
  done

  # stat files
  local stats
  stats=($(stat -c %s.%Y "${files[@]}"))

  # generate manifest
  local manifest title artist album
  manifest=()
  for (( i=0; i<${#ids[@]}; ++i )); do
    get_song_info "${ids[i]}" "$group"
    manifest+=("${ids[i]}:${stats[i]}:$title:$artist:$album")
  done

  local need_write_manifest=
  local retag retag_files i get_next
  local old_id old_stat old_title old_artist old_album old_checksum

  if [[ -e "$manifest_file" ]]; then
    retag=()
    retag_files=()
    i=0
    get_next=1
    while [[ $i -lt ${#ids[@]} ]]; do
      if [[ $get_next ]]; then
        if ! IFS=: read -r old_id old_stat old_title old_artist old_album old_checksum; then
          # add remaining files
          while [[ $i -lt ${#ids[@]} ]]; do
            retag+=("$i")
            (( ++i ))
          done
          break
        fi
        get_next=
      fi

      id="${manifest[i]%%:*}"
      if [[ "$old_id" < "$id" ]]; then
        # old entry
        msg "Pruning $old_id"
        get_next=1
        need_write_manifest=1
        continue
      fi
      if [[ "$old_id" = "$id" ]]; then
        get_next=1
      fi
      if [[ "$old_id:$old_stat:$old_title:$old_artist:$old_album" = "${manifest[i]}" ]]; then
        # no change
        manifest[i]+=":$old_checksum"
      else
        retag+=("$i")
        retag_files+=("$group/$id.mp3")
      fi
      (( ++i ))
    done < "$manifest_file"
  else
    for (( i=0; i<${#ids[@]}; ++i )); do
      retag+=("$i")
    done
    retag_files=("${files[@]}")
  fi

  # tag files
  local id stat title artist album file
  for i in "${retag[@]}"; do
    IFS=: ; set -f
    set -- ${manifest[i]}
    IFS=$ifs ; set +f
    id=$1 stat=$2 title=$3 artist=$4 album=$5
    file="$group/$id.mp3"

    msg "Tagging $id ($artist - $title - $album)"
#   if [[ -z $dry ]]; then
#     ffmpeg -y -hide_banner -loglevel warning \
#       -i "$file" \
#       -codec copy \
#       -map 0:a \
#       -map_metadata -1 \
#       -metadata title="$title" \
#       -metadata artist="$artist" \
#       -metadata album="$album" \
#       -bitexact \
#       -f mp3 "$file.tmp"
#     mv "$file.tmp" "$file"
#   fi
  done

  # if any files were tagged, update the manifest
  if [[ ${#retag[@]} > 0 ]]; then
    msg "Getting updated file information..."

    if [[ -z $dry ]]; then
      stats=($(stat -c %s.%Y "${retag_files[@]}"))
      checksums=($(md5sum "${retag_files[@]}" | cut -d ' ' -f 1))

      # update manifest
      j=0
      for i in "${retag[@]}"; do
        IFS=: ; set -f
        set -- ${manifest[i]}
        IFS=$ifs ; set +f
        file=$1 title=$3 artist=$4 album=$5

        manifest[$i]="$file:${stats[j]}:$title:$artist:$album:${checksums[j]}"
        (( ++j ))
      done
    fi

    need_write_manifest=1
  fi

  if [[ $need_write_manifest ]]; then
    msg "Updating manifest..."
    if [[ $show_manifest ]]; then
      printf '%s\n' "${manifest[@]}"
    fi
    if [[ -z $dry ]]; then
      printf '%s\n' "${manifest[@]}" > "$manifest_file"
    fi
    something_done=1
  fi
}

usage() {
  cat <<EOF
usage: tag.sh [<options>...]

Electric music library autotagger.

Options:
  --dry             dry run
  --show-manifest   print the updated manifest when done
  --help            show this help
EOF
}

dry=
show_manifest=

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry)
      dry=1
      ;;
    --show-manifest)
      show_manifest=1
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

something_done=

update_group main
update_group extra

if [[ -z $something_done ]]; then
  msg "Nothing to do."
fi
