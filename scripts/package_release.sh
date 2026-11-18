#!/bin/bash
# Package an already-built app. This script never modifies the installed app or
# user data, and it does not claim to notarize an ad-hoc signed build.
set -euo pipefail
cd "$(dirname "$0")/.."

application_path="${1:-${RELEASE_APP_PATH:-dist/${RELEASE_PRODUCT_NAME:-Useleaf}.app}}"
output_directory="${2:-dist/release}"
if [[ "$application_path" != /* ]]; then application_path="$PWD/$application_path"; fi
if [[ "$output_directory" != /* ]]; then output_directory="$PWD/$output_directory"; fi
if [[ ! -d "$application_path" || ! -f "$application_path/Contents/Info.plist" ]]; then
  echo "Build the app first, then run: scripts/package_release.sh [path/to/App.app] [output-directory]" >&2
  exit 2
fi

plist="$application_path/Contents/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
product_name="${RELEASE_PRODUCT_NAME:-$(read_plist CFBundleName)}"
version="$(read_plist CFBundleShortVersionString)"
minimum_system="$(read_plist LSMinimumSystemVersion)"
executable_name="$(read_plist CFBundleExecutable)"
if [[ ! "$product_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || ! "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "RELEASE_PRODUCT_NAME and app version must be safe ASCII file-name components." >&2
  exit 2
fi
codesign --verify --deep --strict "$application_path"
architectures="$(lipo -archs "$application_path/Contents/MacOS/$executable_name")"
case "$architectures" in
  arm64) architecture="arm64" ;;
  x86_64) architecture="x86_64" ;;
  "x86_64 arm64"|"arm64 x86_64") architecture="universal" ;;
  *) echo "Unsupported release architectures: $architectures" >&2; exit 2 ;;
esac

asset_name="$product_name-$version-macos-$architecture"
mkdir -p "$output_directory"
for asset in "$asset_name.zip" "$asset_name.dmg"; do
  if [[ -e "$output_directory/$asset" ]]; then
    echo "Refusing to overwrite existing release asset: $output_directory/$asset" >&2
    exit 2
  fi
done

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/app-release.XXXXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT
ditto "$application_path" "$staging_directory/$(basename "$application_path")"
ln -s /Applications "$staging_directory/Applications"
cat > "$staging_directory/INSTALL.txt" <<EOF
$product_name $version

Requires macOS $minimum_system or later. Architecture: $architecture.
Drag the application to Applications, then open it from Applications.
This download does not include your existing vocabulary or personal settings.

The default open-source build is locally (ad-hoc) signed, not Apple notarized.
Check the download source and SHA256SUMS before deciding whether to open it.
For macOS security guidance, see:
https://support.apple.com/102445

Global selection lookup requires Accessibility permission, granted by you in
System Settings. Phrase/sentence translation requires macOS 15+ and the
English/Chinese Apple translation language packs installed on this Mac.
EOF
for license_file in LICENSE THIRD_PARTY_NOTICES.md; do
  if [[ -f "$license_file" ]]; then cp "$license_file" "$staging_directory/$license_file"; fi
done

ditto -c -k --sequesterRsrc --keepParent "$application_path" "$output_directory/$asset_name.zip"
hdiutil create -quiet -volname "$product_name $version" -srcfolder "$staging_directory" \
  -fs HFS+ -format UDZO "$output_directory/$asset_name.dmg"
hdiutil verify -quiet "$output_directory/$asset_name.dmg"
(
  cd "$output_directory"
  shasum -a 256 "$asset_name.zip" "$asset_name.dmg" > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)
printf 'Packaged: %s\n' "$output_directory/$asset_name.zip" "$output_directory/$asset_name.dmg" "$output_directory/SHA256SUMS"
