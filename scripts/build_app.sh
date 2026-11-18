#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
  echo "Usage: scripts/build_app.sh [release|debug]" >&2
  exit 2
fi
build_arguments=(-c "$configuration")
if [[ -n "${WORDSHELF_ARCH:-}" ]]; then
  if [[ "$WORDSHELF_ARCH" != "arm64" && "$WORDSHELF_ARCH" != "x86_64" ]]; then
    echo "WORDSHELF_ARCH must be arm64 or x86_64" >&2
    exit 2
  fi
  build_arguments+=(--arch "$WORDSHELF_ARCH")
fi
swift build "${build_arguments[@]}"
binary_directory="$(swift build "${build_arguments[@]}" --show-bin-path)"
application_directory="$PWD/dist/Useleaf.app"
swift scripts/make_icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o Support/AppIcon.icns
rm -rf "$application_directory"
mkdir -p "$application_directory/Contents/MacOS" "$application_directory/Contents/Resources"
cp "$binary_directory/WordShelf" "$application_directory/Contents/MacOS/Useleaf"
cp Support/Info.plist "$application_directory/Contents/Info.plist"
cp LICENSE "$application_directory/Contents/Resources/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$application_directory/Contents/Resources/THIRD_PARTY_NOTICES.md"
for resource_bundle in "$binary_directory"/*.bundle; do
  if [[ -d "$resource_bundle" ]]; then
    ditto "$resource_bundle" "$application_directory/Contents/Resources/$(basename "$resource_bundle")"
  fi
done
if [[ -f Support/AppIcon.icns ]]; then
  cp Support/AppIcon.icns "$application_directory/Contents/Resources/AppIcon.icns"
fi
signing_identity="${WORDSHELF_SIGNING_IDENTITY:--}"
codesign --force --sign "$signing_identity" --identifier com.yuki.wordshelf "$application_directory"
codesign --verify --strict "$application_directory"
echo "Built: $application_directory"
