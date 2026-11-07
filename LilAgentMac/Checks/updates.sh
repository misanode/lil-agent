#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/lil-agent-update-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -module-cache-path "$check_dir/modules" \
    "$project_dir/LilAgent/Core/Brand.swift" \
    "$project_dir/LilAgent/System/UpdateChecker.swift" \
    "$project_dir/Checks/Updates/main.swift" -o "$check_dir/checks"
"$check_dir/checks"
