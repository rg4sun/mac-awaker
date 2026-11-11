#!/bin/zsh
set -euo pipefail

# Resolve paths relative to this script so building works from any directory,
# including paths containing spaces. No third-party packages are downloaded.
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/build/Mac Awaker.app"
architecture="$(uname -m)"
if (( $# > 1 )) || [[ ${1:-} != "" && ${1:-} != --universal ]]; then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 2
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$project_dir/build/module-cache" "$project_dir/build/slices"

compile_slice() {
    # Compile each architecture against the same macOS minimum. lipo combines
    # the slices before signing so the signature covers the distributable app.
    xcrun swiftc \
        -O \
        -warnings-as-errors \
        -module-cache-path "$project_dir/build/module-cache" \
        -target "$1-apple-macosx13.0" \
        -framework AppKit \
        -framework IOKit \
        -framework CoreText \
        "$project_dir/Sources/AwakeSession.swift" \
        "$project_dir/Sources/StatusBadge.swift" \
        "$project_dir/Sources/CompactReminderView.swift" \
        "$project_dir/Sources/ReminderPanel.swift" \
        "$project_dir/Sources/AppDelegate.swift" \
        "$project_dir/Sources/main.swift" \
        -o "$2"
}

executable="$app_dir/Contents/MacOS/MacAwaker"
if [[ ${1:-} == --universal ]]; then
    compile_slice arm64 "$project_dir/build/slices/arm64"
    compile_slice x86_64 "$project_dir/build/slices/x86_64"
    xcrun lipo -create "$project_dir/build/slices/arm64" "$project_dir/build/slices/x86_64" -output "$executable"
else
    compile_slice "$architecture" "$executable"
fi

cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
"$project_dir/scripts/build-icon.sh"
cp "$project_dir/build/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_dir"
# Updating the bundle's modification date helps Finder notice a changed icon.
touch "$app_dir"
printf 'Built: %s\n' "$app_dir"
