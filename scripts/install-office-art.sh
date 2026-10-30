#!/bin/sh
set -eu

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "Usage: $0 /path/to/36-office-desk-3d-pixel-art-kit.zip" >&2
    exit 2
fi

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
asset_tmp=$(mktemp -d)
trap 'rm -rf "$asset_tmp"' EXIT HUP INT TERM
unzip -q "$1" -d "$asset_tmp"

asset_root="$asset_tmp/isometric/png_64"
cp "$asset_root/office_furniture/office_desk.png" "$project_root/Resources/IsoDesk.png"
cp "$asset_root/office_furniture/bookshelf.png" "$project_root/Resources/IsoBookshelf.png"
cp "$asset_root/office_tech/office_monitor.png" "$project_root/Resources/IsoMonitor.png"
cp "$asset_root/office_tech/office_keyboard.png" "$project_root/Resources/IsoKeyboard.png"
cp "$asset_root/office_tech/desk_lamp.png" "$project_root/Resources/IsoLamp.png"
cp "$asset_root/office_tech/laser_printer.png" "$project_root/Resources/IsoPrinter.png"
cp "$asset_root/break_room/potted_plant.png" "$project_root/Resources/IsoPlant.png"

# Chair frame 4 faces the monitor. sips is included with macOS.
sips -c 64 64 --cropOffset 0 256 \
    "$asset_tmp/spin/office_furniture/office_chair_spin.png" \
    --out "$project_root/Resources/IsoChair.png" >/dev/null

echo "Installed the eight office sprites in Resources/."
