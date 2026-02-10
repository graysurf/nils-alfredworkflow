#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: action_open.sh <url-or-uri>" >&2
  exit 2
fi

to_spotify_uri() {
  local target="$1"

  if [[ "$target" == spotify:* ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  local normalized="$target"
  normalized="${normalized%%\#*}"
  normalized="${normalized%%\?*}"

  local path=""
  case "$normalized" in
  https://open.spotify.com/*)
    path="${normalized#https://open.spotify.com/}"
    ;;
  http://open.spotify.com/*)
    path="${normalized#http://open.spotify.com/}"
    ;;
  *)
    return 1
    ;;
  esac

  # Locale-aware links may include an extra leading segment: intl-xx/...
  if [[ "$path" == intl-*/* ]]; then
    path="${path#*/}"
  fi

  local seg1=""
  local seg2=""
  local seg3=""
  local seg4=""
  IFS='/' read -r seg1 seg2 seg3 seg4 _ <<<"$path"

  local kind=""
  local id=""

  case "$seg1" in
  track | album | artist | playlist | show | episode)
    kind="$seg1"
    id="$seg2"
    ;;
  user)
    if [[ "$seg3" == "playlist" ]]; then
      kind="playlist"
      id="$seg4"
    fi
    ;;
  esac

  if [[ -z "$kind" || -z "$id" ]]; then
    return 1
  fi

  printf 'spotify:%s:%s\n' "$kind" "$id"
}

open_in_spotify() {
  local spotify_uri="$1"

  # Always attempt macOS-style app targeting first; non-macOS `open` commands
  # will fail fast and we fallback to opening the URI directly.
  if open -a Spotify "$spotify_uri" >/dev/null 2>&1; then
    return 0
  fi

  open "$spotify_uri"
}

target="$1"
spotify_uri=""

if spotify_uri="$(to_spotify_uri "$target")"; then
  if open_in_spotify "$spotify_uri"; then
    exit 0
  fi
fi

open "$target"
