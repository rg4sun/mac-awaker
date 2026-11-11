#!/bin/zsh
set -euo pipefail

# Package the source artwork into every standard macOS icon size. sips preserves
# the source PNG's alpha channel, including the transparent rounded corners.
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_icon="$project_dir/Resources/AppIcon.png"
iconset_dir="$project_dir/build/AppIcon.iconset"
mkdir -p "$iconset_dir"

for points in 16 32 128 256 512; do
    for scale in 1 2; do
        pixel_size=$((points * scale))
        suffix=""
        if [[ "$scale" == 2 ]]; then
            suffix="@2x"
        fi
        sips -z "$pixel_size" "$pixel_size" "$source_icon" \
            --out "$iconset_dir/icon_${points}x${points}${suffix}.png" >/dev/null
    done
done

iconutil --convert icns "$iconset_dir" --output "$project_dir/build/AppIcon.icns"
