#!/usr/bin/env bash
# Builds "Family Publisher.app". Pass --install to copy it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd .. && pwd)"
APP="build/Family Publisher.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FamilyPublisher "$APP/Contents/MacOS/FamilyPublisher"
[[ -f AppIcon.icns ]] || swift make-icon.swift
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Family Publisher</string>
  <key>CFBundleDisplayName</key><string>Family Publisher</string>
  <key>CFBundleIdentifier</key><string>io.github.t11ii.family-publisher</string>
  <key>CFBundleExecutable</key><string>FamilyPublisher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>FPRepoPath</key><string>${REPO}</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>HTML document</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.html</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"Family Publisher.app"
  cp -R "$APP" ~/Applications/
  touch ~/Applications/"Family Publisher.app" # nudge Finder/Dock to pick up the icon
  echo "Installed to ~/Applications/Family Publisher.app"
fi
