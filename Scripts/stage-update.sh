#!/bin/zsh
# Stage a notarized archive and signed Sparkle feed together, then deploy website/.
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/ClearDisk.app/Contents/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' dist/ClearDisk.app/Contents/Info.plist)
NAME="ClearDisk-$VERSION-$BUILD"
spctl --assess --type open --context context:primary-signature dist/ClearDisk.dmg
mkdir -p dist/updates website/public/updates
cp dist/ClearDisk.dmg "dist/updates/$NAME.dmg"
if [[ -f "releases/$VERSION.html" ]]; then cp "releases/$VERSION.html" "dist/updates/$NAME.html"; fi
if [[ -f website/public/updates/appcast.xml ]]; then cp website/public/updates/appcast.xml dist/updates/appcast.xml; fi
"$TOOLS/generate_appcast" --account cleardisk-updates --maximum-deltas 0 \
  --download-url-prefix https://cleardisk.app/updates/ \
  --link https://cleardisk.app/download --embed-release-notes dist/updates
"$TOOLS/sign_update" --account cleardisk-updates --verify dist/updates/appcast.xml
cp "dist/updates/$NAME.dmg" website/public/updates/
cp dist/updates/appcast.xml website/public/updates/appcast.xml
cp dist/ClearDisk.dmg website/public/ClearDisk.dmg
(cd website/public && shasum -a 256 ClearDisk.dmg > SHA256SUMS.txt)
echo "Staged $NAME and its signed feed. Deploy website/ together."
