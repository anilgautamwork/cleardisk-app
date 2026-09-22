#!/bin/zsh
# Full direct-distribution release: signed app -> notarized -> stapled -> DMG.
# One-time setup (run these yourself, they need your Apple ID):
#   1. Xcode -> Settings -> Accounts -> Manage Certificates -> + ->
#      "Developer ID Application"
#   2. xcrun notarytool store-credentials csvcompare \
#        --apple-id <your-apple-id> --team-id CH96562777
#      (profile shared with the CSV Compare Local release pipeline)
set -e
cd "$(dirname "$0")/.."

NOTARY_PROFILE=csvcompare

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "No 'Developer ID Application' certificate installed — see the setup" >&2
  echo "comment at the top of this script. (Apple Development certs can't" >&2
  echo "be notarized for distribution.)" >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "No notarytool credentials stored under profile '$NOTARY_PROFILE' — see the" >&2
  echo "setup comment at the top of this script." >&2
  exit 1
fi

./Scripts/make-app.sh

echo "— notarizing app —"
ditto -c -k --keepParent dist/ClearDisk.app dist/ClearDisk.zip
xcrun notarytool submit dist/ClearDisk.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple dist/ClearDisk.app

echo "— building DMG —"
swift Scripts/render-installer.swift dist/installer-background.tiff
uvx --from dmgbuild==1.6.7 dmgbuild -s Scripts/dmg-settings.py "ClearDisk" dist/ClearDisk.dmg
# The DMG container needs its own signature for Gatekeeper to accept it.
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
codesign --force --sign "$IDENTITY" --timestamp dist/ClearDisk.dmg
xcrun notarytool submit dist/ClearDisk.dmg --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple dist/ClearDisk.dmg
spctl -a -t open --context context:primary-signature -v dist/ClearDisk.dmg

./Scripts/stage-update.sh
echo "release ready: dist/ClearDisk.dmg and website/public/updates/appcast.xml"
