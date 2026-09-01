#!/bin/bash

set -euo pipefail

if (($# != 5)); then
  echo "usage: capture-window-preview.sh <x> <y> <w> <h> <dest.png>" >&2
  exit 2
fi

x=$1
y=$2
w=$3
h=$4
dest=$5

[[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ && $w =~ ^[0-9]+$ && $h =~ ^[0-9]+$ ]] || {
  echo "capture-window-preview: geometry must be integers" >&2
  exit 2
}

(( w >= 8 && h >= 8 && w <= 7680 && h <= 4320 )) || {
  echo "capture-window-preview: geometry is out of range" >&2
  exit 2
}

[[ $dest == *.png && $dest != *..* ]] || {
  echo "capture-window-preview: destination must be a png path" >&2
  exit 2
}

mkdir -p -- "$(dirname -- "$dest")"
grim -g "${x},${y} ${w}x${h}" "$dest"
