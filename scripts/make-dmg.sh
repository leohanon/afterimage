#!/bin/zsh
# Packages a notarized Afterimage.app into a drag-to-install disk image:
# the app on the left, an Applications shortcut on the right, an arrow between.
#
#   scripts/make-dmg.sh build/ship/notarized/Afterimage.app build/ship/Afterimage.dmg
set -euo pipefail

APP=${1:?path to Afterimage.app}
OUT=${2:?output .dmg path}
VOL="Afterimage"
HERE=${0:A:h}
WORK=$(mktemp -d)
trap 'hdiutil detach -quiet "/Volumes/$VOL" 2>/dev/null || true; rm -rf "$WORK"' EXIT

# Background at 1x and 2x, combined so Retina screens get the sharp one.
swiftc -o "$WORK/bg" "$HERE/dmg/background.swift"
"$WORK/bg" "$WORK/bg1.png" 1
"$WORK/bg" "$WORK/bg2.png" 2
mkdir -p "$WORK/stage/.background"
tiffutil -cathidpicheck "$WORK/bg1.png" "$WORK/bg2.png" -out "$WORK/stage/.background/background.tiff" >/dev/null

ditto "$APP" "$WORK/stage/Afterimage.app"
ln -s /Applications "$WORK/stage/Applications"

hdiutil detach -quiet "/Volumes/$VOL" 2>/dev/null || true
hdiutil create -quiet -volname "$VOL" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/rw.dmg"

# Finder stores the window layout in the volume's .DS_Store.
osascript <<EOF
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 840, 520}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Afterimage.app" of container window to {170, 190}
    set position of item "Applications" of container window to {470, 190}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sync
hdiutil detach -quiet "/Volumes/$VOL"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Wrote $OUT"
