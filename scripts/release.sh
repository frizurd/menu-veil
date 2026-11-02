#!/bin/zsh
# Sign and notarize the exact app shipped by both ZIP and Homebrew. Never strip quarantine.
set -euo pipefail
cd "${0:A:h}/.."
: "${MENU_VEIL_SIGNING_IDENTITY:?Set your Developer ID Application identity}"
: "${MENU_VEIL_NOTARY_PROFILE:?Set the notarytool keychain profile name}"
zsh scripts/test.sh
zsh build.sh
app="$PWD/build/Menu Veil.app"
archive="$PWD/build/Menu-Veil-0.2.1.zip"
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$MENU_VEIL_NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --strict "$app"
spctl --assess --type execute --verbose "$app"
ditto -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive"
python3 scripts/write-cask.py "$archive" "$PWD/build/menu-veil.rb"
