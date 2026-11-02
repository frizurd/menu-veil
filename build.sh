#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="$PWD/build/Menu Veil.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Assets/MenuVeil.icns "$app/Contents/Resources/MenuVeil.icns"
xcrun swiftc -swift-version 5 -O -module-cache-path "$PWD/build/ModuleCache" Sources/main.swift -o "$app/Contents/MacOS/MenuVeil" -framework AppKit
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
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built $app"
