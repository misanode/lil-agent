#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "--help" || $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage: bash Scripts/release.sh KEYCHAIN_PROFILE [DEVELOPER_ID_SHA1]\n'
    printf 'Builds a universal app, signs it, and submits a DMG to Apple for notarization.\n'
    printf 'Store credentials first with: xcrun notarytool store-credentials PROFILE\n'
    [[ "${1:-}" == "--help" ]] && exit 0
    exit 2
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
profile="$1"
identity="${2:-}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

identities="$(/usr/bin/security find-identity -v -p codesigning)"
available=()
while IFS= read -r fingerprint; do
    [[ -n "$fingerprint" ]] && available+=("$fingerprint")
done < <(printf '%s\n' "$identities" | /usr/bin/sed -nE 's/^[[:space:]]*[0-9]+\) ([A-Fa-f0-9]{40}) "Developer ID Application:.*$/\1/p')

if [[ ${#available[@]} -eq 0 ]]; then
    printf 'No usable Developer ID Application certificate and private key found.\n' >&2
    printf 'In Xcode Settings > Accounts > Manage Certificates, create Developer ID Application.\n' >&2
    exit 1
fi
if [[ -z "$identity" ]]; then
    if [[ ${#available[@]} -ne 1 ]]; then
        printf 'Multiple Developer ID certificates found. Supply the desired SHA-1 fingerprint.\n' >&2
        exit 1
    fi
    identity="${available[0]}"
fi
found=false
for fingerprint in "${available[@]}"; do
    [[ "$fingerprint" == "$identity" ]] && found=true
done
if [[ "$found" != true ]]; then
    printf 'The requested fingerprint is not a usable Developer ID Application identity.\n' >&2
    exit 1
fi

xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null
mkdir -p "$project_dir/release"
release_dir="$(mktemp -d "$project_dir/release/macos.XXXXXX")"
printf 'Release files: %s\n' "$release_dir"

xcrun xcodebuild -project "$project_dir/LilAgent.xcodeproj" -scheme LilAgent \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$release_dir/DerivedData" \
    -archivePath "$release_dir/LilAgent.xcarchive" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
    archive >"$release_dir/build.log" 2>&1 || {
        printf 'Build failed. See %s/build.log\n' "$release_dir" >&2
        exit 1
    }

mkdir "$release_dir/Installer"
app="$release_dir/Installer/Lil Agent.app"
/usr/bin/ditto "$release_dir/LilAgent.xcarchive/Products/Applications/Lil Agent.app" "$app"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
xcrun lipo "$app/Contents/MacOS/$executable" -verify_arch arm64 x86_64
/usr/bin/codesign --force --sign "$identity" --options runtime --timestamp \
    --entitlements "$project_dir/Config/LilAgent.entitlements" "$app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
ln -s /Applications "$release_dir/Installer/Applications"

dmg="$release_dir/Lil-Agent-macOS.dmg"
/usr/bin/hdiutil create -volname 'Lil Agent' -srcfolder "$release_dir/Installer" \
    -format UDZO "$dmg"
/usr/bin/codesign --sign "$identity" --timestamp "$dmg"
/usr/bin/codesign --verify --strict --verbose=2 "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait \
    --output-format json >"$release_dir/notarization.json"
status="$(/usr/bin/plutil -extract status raw -o - "$release_dir/notarization.json")"
if [[ "$status" != Accepted ]]; then
    printf 'Notarization was not accepted. Do not distribute this DMG.\n' >&2
    submission="$(/usr/bin/plutil -extract id raw -o - "$release_dir/notarization.json")"
    xcrun notarytool log "$submission" --keychain-profile "$profile" \
        "$release_dir/notarization-log.json" || true
    exit 1
fi
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
(cd "$release_dir" && /usr/bin/shasum -a 256 Lil-Agent-macOS.dmg >SHA256.txt)
printf '\nSigned and notarized installer: %s\n' "$dmg"
