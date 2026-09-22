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
