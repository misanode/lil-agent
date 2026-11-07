#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/lil-agent-animation-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -module-cache-path "$check_dir/modules" \
    "$project_dir"/LilAgent/Core/*.swift \
    "$project_dir"/LilAgent/Model/*.swift \
    "$project_dir"/LilAgent/Character/*.swift \
    "$project_dir"/LilAgent/Effects/*.swift \
    "$project_dir/Checks/Animation/main.swift" -o "$check_dir/checks"
cp "$project_dir/LilAgent/Resources/bed.glb" "$check_dir/bed.glb"
"$check_dir/checks" "$project_dir"
