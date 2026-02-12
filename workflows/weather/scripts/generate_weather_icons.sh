#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out_dir="$(cd "$script_dir/../src/assets" && pwd)/icons/weather"
mkdir -p "$out_dir"

base_bg=(
  -size 128x128
  xc:none
  -fill '#1C4A86'
  -stroke '#8AB6F2'
  -strokewidth 4
  -draw 'circle 64,64 64,10'
  -stroke none
  -fill '#245A9B'
  -draw 'circle 64,64 64,16'
)

# clear
magick "${base_bg[@]}" \
  -stroke '#FFD65A' -strokewidth 4 \
  -draw 'line 64,22 64,12' -draw 'line 64,106 64,116' \
  -draw 'line 22,64 12,64' -draw 'line 106,64 116,64' \
  -draw 'line 33,33 25,25' -draw 'line 95,95 103,103' \
  -draw 'line 95,33 103,25' -draw 'line 33,95 25,103' \
  -stroke none -fill '#FFD65A' -draw 'circle 64,64 64,38' \
  "$out_dir/clear.png"

# mainly-clear
magick "${base_bg[@]}" \
  -stroke '#FFD65A' -strokewidth 3 \
  -draw 'line 42,24 42,16' -draw 'line 24,42 16,42' \
  -draw 'line 31,31 24,24' \
  -stroke none -fill '#FFD65A' -draw 'circle 42,42 42,28' \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 32,70 98,90 10,10' \
  -draw 'circle 44,72 44,58' \
  -draw 'circle 66,62 66,44' \
  -draw 'circle 86,72 86,58' \
  "$out_dir/mainly-clear.png"

# partly-cloudy
magick "${base_bg[@]}" \
  -stroke '#FFD65A' -strokewidth 3 \
  -draw 'line 46,20 46,12' -draw 'line 28,38 20,38' \
  -draw 'line 34,26 27,19' \
  -stroke none -fill '#FFD65A' -draw 'circle 46,38 46,24' \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 28,68 100,92 11,11' \
  -draw 'circle 42,70 42,54' \
  -draw 'circle 66,58 66,38' \
  -draw 'circle 88,70 88,54' \
  "$out_dir/partly-cloudy.png"

# cloudy
magick "${base_bg[@]}" \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 28,66 100,92 11,11' \
  -draw 'circle 42,70 42,54' \
  -draw 'circle 66,58 66,38' \
  -draw 'circle 88,70 88,54' \
  "$out_dir/cloudy.png"

# fog
magick "${base_bg[@]}" \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 28,58 100,82 11,11' \
  -draw 'circle 42,62 42,48' \
  -draw 'circle 66,52 66,34' \
  -draw 'circle 88,62 88,48' \
  -stroke '#D8E8FA' -strokewidth 4 \
  -draw 'line 30,92 98,92' \
  -draw 'line 36,102 92,102' \
  "$out_dir/fog.png"

# drizzle
magick "${base_bg[@]}" \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 28,58 100,82 11,11' \
  -draw 'circle 42,62 42,48' \
  -draw 'circle 66,52 66,34' \
  -draw 'circle 88,62 88,48' \
  -fill '#9ED0FF' \
  -draw 'circle 46,96 46,93' \
  -draw 'circle 64,102 64,99' \
  -draw 'circle 82,96 82,93' \
  "$out_dir/drizzle.png"

# rain
magick "${base_bg[@]}" \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 28,58 100,82 11,11' \
  -draw 'circle 42,62 42,48' \
  -draw 'circle 66,52 66,34' \
  -draw 'circle 88,62 88,48' \
  -stroke '#9ED0FF' -strokewidth 5 \
  -draw 'line 44,90 38,106' \
  -draw 'line 64,90 58,108' \
  -draw 'line 84,90 78,106' \
  "$out_dir/rain.png"

# snow
magick "${base_bg[@]}" \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 28,58 100,82 11,11' \
  -draw 'circle 42,62 42,48' \
  -draw 'circle 66,52 66,34' \
  -draw 'circle 88,62 88,48' \
  -stroke '#EAF4FF' -strokewidth 3 \
  -draw 'line 44,94 44,108' -draw 'line 37,101 51,101' \
  -draw 'line 64,94 64,108' -draw 'line 57,101 71,101' \
  -draw 'line 84,94 84,108' -draw 'line 77,101 91,101' \
  "$out_dir/snow.png"

# rain-showers
magick "${base_bg[@]}" \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 24,54 104,82 11,11' \
  -draw 'circle 40,58 40,44' \
  -draw 'circle 66,46 66,30' \
  -draw 'circle 92,58 92,44' \
  -stroke '#9ED0FF' -strokewidth 5 \
  -draw 'line 38,88 30,108' \
  -draw 'line 54,88 46,110' \
  -draw 'line 70,88 62,110' \
  -draw 'line 86,88 78,108' \
  "$out_dir/rain-showers.png"

# snow-showers
magick "${base_bg[@]}" \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 24,54 104,82 11,11' \
  -draw 'circle 40,58 40,44' \
  -draw 'circle 66,46 66,30' \
  -draw 'circle 92,58 92,44' \
  -stroke '#EAF4FF' -strokewidth 3 \
  -draw 'line 36,92 36,108' -draw 'line 28,100 44,100' \
  -draw 'line 56,92 56,110' -draw 'line 48,101 64,101' \
  -draw 'line 76,92 76,110' -draw 'line 68,101 84,101' \
  -draw 'line 96,92 96,108' -draw 'line 88,100 104,100' \
  "$out_dir/snow-showers.png"

# thunderstorm
magick "${base_bg[@]}" \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 24,52 104,80 11,11' \
  -draw 'circle 40,56 40,42' \
  -draw 'circle 66,44 66,28' \
  -draw 'circle 92,56 92,42' \
  -fill '#FFD65A' \
  -draw 'polygon 60,86 74,86 66,100 80,100 56,120 62,104 50,104' \
  -stroke '#9ED0FF' -strokewidth 4 \
  -draw 'line 34,88 28,102' \
  -draw 'line 94,88 88,102' \
  "$out_dir/thunderstorm.png"

# unknown
magick "${base_bg[@]}" \
  -fill '#F7FBFF' \
  -draw 'roundrectangle 24,56 104,84 11,11' \
  -draw 'circle 40,60 40,46' \
  -draw 'circle 66,48 66,32' \
  -draw 'circle 92,60 92,46' \
  -fill none -stroke '#FFD65A' -strokewidth 6 \
  -draw 'path \"M 50,44 C 50,30 78,30 78,46 C 78,56 64,58 64,70\"' \
  -stroke none -fill '#FFD65A' \
  -draw 'circle 64,86 64,90' \
  "$out_dir/unknown.png"

printf 'ok: generated weather icons in %s\n' "$out_dir"
