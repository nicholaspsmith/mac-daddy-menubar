#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Build Resources/bundle/AppIcon.icns from the approved 1024px mascot.
set -euo pipefail
cd "$(dirname "$0")/.."
src=../widgets.nicksmith.software/art/raw/mac-daddy.png
[ -f "$src" ] || { echo "Missing mascot: $src (clone widgets.nicksmith.software beside this repo)" >&2; exit 1; }
set_dir="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$set_dir" Resources/bundle
for s in 16 32 128 256 512; do
  sips -z $s $s "$src" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$src" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o Resources/bundle/AppIcon.icns
echo "wrote Resources/bundle/AppIcon.icns"
