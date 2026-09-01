#!/bin/zsh
# Full direct-distribution release: signed app -> notarized -> stapled -> DMG.
# One-time setup (run these yourself, they need your Apple ID):
#   1. Xcode -> Settings -> Accounts -> Manage Certificates -> + ->
#      "Developer ID Application"
#   2. xcrun notarytool store-credentials notary \
#        --apple-id <your-apple-id> --team-id <TEAMID> \
#        --password <app-specific password from appleid.apple.com>
set -e
cd "$(dirname "$0")/.."

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "No 'Developer ID Application' certificate installed — see the setup" >&2
  echo "comment at the top of this script. (Apple Development certs can't" >&2
  echo "be notarized for distribution.)" >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile notary >/dev/null 2>&1; then
  echo "No notarytool credentials stored under profile 'notary' — see the" >&2
  echo "setup comment at the top of this script." >&2
  exit 1
fi

./Scripts/make-app.sh

echo "— notarizing app —"
ditto -c -k --keepParent dist/ClearDisk.app dist/ClearDisk.zip
xcrun notarytool submit dist/ClearDisk.zip --keychain-profile notary --wait
xcrun stapler staple dist/ClearDisk.app

echo "— building DMG —"
STAGE=dist/dmg-stage
rm -rf "$STAGE" && mkdir "$STAGE"
cp -R dist/ClearDisk.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname ClearDisk -srcfolder "$STAGE" -ov -format UDZO dist/ClearDisk.dmg
xcrun notarytool submit dist/ClearDisk.dmg --keychain-profile notary --wait
xcrun stapler staple dist/ClearDisk.dmg

echo "release ready: dist/ClearDisk.dmg"
