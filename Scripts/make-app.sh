#!/bin/zsh
# Assembles a signed ClearDisk.app from the SPM release build.
# Signs with Developer ID Application when present (required for
# distribution), else Apple Development, else ad-hoc.
set -e
cd "$(dirname "$0")/.."

# Safety gate: permanent deletion is allowed in exactly ONE audited place —
# TrashService.deleteForever (double-confirmed, type-to-confirm in UI).
# Anywhere else, the build fails.
if grep -rn '\.removeItem(' Sources/ | grep -v 'Sources/Core/TrashService.swift' | grep -q removeItem; then
  echo "FATAL: FileManager.removeItem outside TrashService.deleteForever — ClearDisk is trash-only elsewhere." >&2
  grep -rn '\.removeItem(' Sources/ | grep -v 'Sources/Core/TrashService.swift' >&2
  exit 1
fi

swift build -c release --arch arm64 --arch x86_64

APP=dist/ClearDisk.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/ClearDiskApp "$APP/Contents/MacOS/ClearDisk"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Scripts/AppIcon.icns ]; then
  swift Scripts/render-icon.swift /tmp/cleardisk_icon_1024.png
  ICONSET=/tmp/ClearDisk.iconset
  rm -rf "$ICONSET" && mkdir "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s /tmp/cleardisk_icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d /tmp/cleardisk_icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Scripts/AppIcon.icns
fi
cp Scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')
fi
if [ -n "$IDENTITY" ]; then
  # --timestamp is required for notarization.
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  echo "signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "signed ad-hoc (no identity found)"
fi

codesign --verify --deep "$APP" && echo "built $APP"
