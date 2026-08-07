#!/bin/bash
# Build the distributable macOS app and create the GitHub Release asset.
# Usage: scripts/package_release.sh [version]   (default: 1.4.1)
set -euo pipefail

VERSION="${1:-1.4.1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/Build"
BUILT_APP="$BUILD_DIR/Release/Orbit.app"
DIST_DIR="$PROJECT_DIR/dist"
RELEASE_ASSET="$DIST_DIR/Orbit-macOS.zip"
LOCAL_ARCHIVE="$PROJECT_DIR/Orbit-macOS-v$VERSION.zip"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must use semantic versioning, for example 1.0.0" >&2
    exit 2
fi

cd "$PROJECT_DIR"

echo "==> Building Orbit $VERSION (Release)"
xcodebuild -quiet -project Orbit.xcodeproj -scheme Orbit \
    -configuration Release -derivedDataPath Build \
    MARKETING_VERSION="$VERSION" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" build

[ -d "$BUILT_APP" ] || { echo "Build produced no app at $BUILT_APP" >&2; exit 1; }

ARCHES="$(lipo -archs "$BUILT_APP/Contents/MacOS/Orbit")"
[[ " $ARCHES " == *" arm64 "* && " $ARCHES " == *" x86_64 "* ]] || {
    echo "Release executable is not Universal 2; found architectures: $ARCHES" >&2
    exit 1
}
echo "==> Universal 2 architectures: $ARCHES"

echo "==> Verifying signature"
codesign --verify --deep --strict "$BUILT_APP"

mkdir -p "$DIST_DIR"
rm -f "$RELEASE_ASSET" "$LOCAL_ARCHIVE" "$DIST_DIR/SHA256SUMS.txt"

echo "==> Creating archives"
ditto -c -k --sequesterRsrc --keepParent "$BUILT_APP" "$RELEASE_ASSET"
cp "$RELEASE_ASSET" "$LOCAL_ARCHIVE"
(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$RELEASE_ASSET")" > SHA256SUMS.txt
)

echo "==> Created"
ls -lh "$RELEASE_ASSET" "$LOCAL_ARCHIVE" "$DIST_DIR/SHA256SUMS.txt"
