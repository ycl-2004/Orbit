#!/bin/bash
#
# Build Orbit and leave exactly one copy of it on this machine.
#
# macOS grants Accessibility and Screen Recording per app *path*, so a build
# sitting in Build/ is a different app as far as the system is concerned — it
# shows up as a second Orbit in System Settings and never inherits the
# permissions you already granted. This script therefore installs to
# /Applications and removes the build product afterwards.
#
# Usage: scripts/install.sh [Debug|Release]     (default: Release)
#
set -euo pipefail

CONFIGURATION="${1:-Release}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/Build"
BUILT_APP="$BUILD_DIR/$CONFIGURATION/Orbit.app"
INSTALLED_APP="/Applications/Orbit.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

cd "$PROJECT_DIR"

echo "==> Building $CONFIGURATION"
xcodebuild -quiet -project Orbit.xcodeproj -scheme Orbit \
    -configuration "$CONFIGURATION" -derivedDataPath Build \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

[ -d "$BUILT_APP" ] || { echo "Build produced no app at $BUILT_APP"; exit 1; }

echo "==> Replacing $INSTALLED_APP"
pkill -x Orbit 2>/dev/null || true
sleep 1
rm -rf "$INSTALLED_APP"
cp -R "$BUILT_APP" "$INSTALLED_APP"
xattr -dr com.apple.quarantine "$INSTALLED_APP" 2>/dev/null || true
codesign -v "$INSTALLED_APP"

# Unregister the build product before deleting it, so it does not linger in
# LaunchServices as a second Orbit.
echo "==> Removing the build copy"
"$LSREGISTER" -u "$BUILT_APP" 2>/dev/null || true
rm -rf "$BUILT_APP" "$BUILT_APP.dSYM"

open -a "$INSTALLED_APP"
sleep 2
pgrep -x Orbit >/dev/null && echo "==> Running (PID $(pgrep -x Orbit))" || echo "==> Did not start"

echo
echo "Only copy on disk:"
find /Applications "$BUILD_DIR" -maxdepth 4 -name "Orbit.app" 2>/dev/null
echo
echo "The bundle is ad-hoc signed, so its code hash changes on every build and"
echo "macOS treats it as a new app. If the ring does not open, re-grant:"
echo "  System Settings > Privacy & Security > Accessibility     (required)"
echo "  System Settings > Privacy & Security > Screen Recording  (window previews)"
echo "Remove the stale Orbit entry there first, then add this one back."
