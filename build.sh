#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="$PWD/build/Menu Veil.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Assets/MenuVeil.icns "$app/Contents/Resources/MenuVeil.icns"
touch build/.metadata_never_index
for architecture in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -target "$architecture-apple-macos14.0" -module-cache-path "$PWD/build/ModuleCache" Sources/*.swift -o "build/MenuVeil-$architecture" -framework AppKit
done
lipo -create build/MenuVeil-arm64 build/MenuVeil-x86_64 -output "$app/Contents/MacOS/MenuVeil"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MenuVeil</string>
<key>CFBundleIdentifier</key><string>local.frizurd.menu-veil-prototype</string>
<key>CFBundleName</key><string>Menu Veil</string>
<key>CFBundleIconFile</key><string>MenuVeil</string>
<key>CFBundleDisplayName</key><string>Menu Veil</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>0.2.1</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -n "${MENU_VEIL_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$MENU_VEIL_SIGNING_IDENTITY" "$app"
else
  codesign --force --sign - "$app"
  print "Development build: permission may need to be granted again after rebuilding."
fi
codesign --verify --strict "$app"
print "Built $app"
