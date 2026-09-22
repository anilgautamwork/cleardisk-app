#!/bin/zsh
# Mach-O UUIDs survive signing; require the packaged app to match SwiftPM's current build.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
BUILT_UUIDS=$(dwarfdump --uuid "$BUILD_DIR/ClearDiskApp" | awk '{print $2, $3}')
PACKAGED_UUIDS=$(dwarfdump --uuid dist/ClearDisk.app/Contents/MacOS/ClearDisk | awk '{print $2, $3}')
if [[ -z "$BUILT_UUIDS" || "$BUILT_UUIDS" != "$PACKAGED_UUIDS" ]]; then
  echo "Packaged executable does not match the current universal build." >&2
  exit 1
fi
echo "Packaged executable matches the current universal build."
python3 - <<'PY_CHECK'
import plistlib
from pathlib import Path
info = plistlib.loads(Path('dist/ClearDisk.app/Contents/Info.plist').read_bytes())
assert info['SUFeedURL'] == 'https://cleardisk.app/updates/appcast.xml'
assert info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction']
assert not info['SUAllowsAutomaticUpdates'], 'Installation must remain user initiated'
assert info['SUPublicEDKey'], 'An update verification key must be embedded'
assert Path('dist/ClearDisk.app/Contents/Frameworks/Sparkle.framework/Sparkle').is_file()
PY_CHECK
