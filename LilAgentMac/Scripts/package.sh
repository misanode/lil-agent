#!/bin/bash
# Builds the universal native app, signs it with the project's self-signed certificate, and zips it for a GitHub release.
# Every release must use the same certificate: macOS ties Input Monitoring and Apple Events permissions to it, so a
# different certificate (or ad hoc signing) makes people grant them again.
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(cd "$project_dir/.." && pwd)"
identity="${LILAGENT_SIGN_IDENTITY:-Lil Agent Self-Signed}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -q "\"$identity\""; then
    printf 'Signing identity "%s" not found in the keychain. Import the backed-up certificate first.\n' "$identity" >&2
    exit 1
fi

build_dir="$project_dir/build/Package"
rm -rf "$build_dir"
xcrun xcodebuild -project "$project_dir/LilAgent.xcodeproj" -scheme LilAgent -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$build_dir" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build >"$build_dir.log" 2>&1 || {
        printf 'Build failed. See %s.log\n' "$build_dir" >&2
        exit 1
    }

app="$build_dir/Build/Products/Release/Lil Agent.app"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
archs="$(xcrun lipo -archs "$app/Contents/MacOS/$executable")"
for arch in arm64 x86_64; do
    [[ " $archs " == *" $arch "* ]] || { printf 'Missing %s slice (found: %s)\n' "$arch" "$archs" >&2; exit 1; }
done
/usr/bin/codesign --force --sign "$identity" --options runtime \
    --entitlements "$project_dir/Config/LilAgent.entitlements" "$app"
/usr/bin/codesign --verify --deep --strict "$app"

out_dir="$repo_dir/release/v$version"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$app" "$stage/Lil Agent.app"
cp "$repo_dir/LICENSE" "$stage/LICENSE"
mkdir -p "$out_dir"
rm -f "$out_dir/Lil-Agent-Native-Swift-macOS.zip"
(cd "$stage" && /usr/bin/zip -qry "$out_dir/Lil-Agent-Native-Swift-macOS.zip" LICENSE "Lil Agent.app")
printf 'Signed with "%s": %s\n' "$identity" "$out_dir/Lil-Agent-Native-Swift-macOS.zip"
