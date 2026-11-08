#!/bin/bash
# Generates Resources/AppIcon.icns from Tools/MakeIcon.swift.
set -euo pipefail
cd "$(dirname "$0")"

PNG="$(mktemp -t pbicon).png"
swift Tools/MakeIcon.swift "$PNG"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    d=$((s * 2))
    sips -z "$s" "$s" "$PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$d" "$d" "$PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
