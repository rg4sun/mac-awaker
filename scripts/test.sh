#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/build/module-cache"
before_settings="$(pmset -g custom)"

xcrun swiftc \
    -warnings-as-errors \
    -module-cache-path "$project_dir/build/module-cache" \
    -framework IOKit \
    "$project_dir/Sources/AwakeSession.swift" \
    "$project_dir/Tests/SessionChecks.swift" \
    -o "$project_dir/build/SessionChecks"

"$project_dir/build/SessionChecks"
after_settings="$(pmset -g custom)"
if [[ "$before_settings" != "$after_settings" ]]; then
    printf 'FAIL: Power settings differ from the snapshot before the checks.\n' >&2
    exit 1
fi
printf 'PASS: Power settings are unchanged.\n'
