#!/bin/bash
# Verify a built Orbit.app or Orbit-macOS.zip before publishing it.
set -euo pipefail

INPUT="${1:-}"
[[ -n "$INPUT" ]] || { echo "Usage: $0 /path/to/Orbit.app-or-zip" >&2; exit 2; }

TEMP_DIR=""
cleanup() {
    [[ -z "$TEMP_DIR" ]] || rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ -d "$INPUT" && "$(basename "$INPUT")" == "Orbit.app" ]]; then
    APP="$INPUT"
elif [[ -f "$INPUT" && "$INPUT" == *.zip ]]; then
    TEMP_DIR="$(mktemp -d -t orbit-release-check.XXXXXX)"
    ditto -x -k "$INPUT" "$TEMP_DIR"
    APP="$TEMP_DIR/Orbit.app"
else
    echo "Expected an Orbit.app bundle or a .zip archive: $INPUT" >&2
    exit 2
fi

EXECUTABLE="$APP/Contents/MacOS/Orbit"
[[ -d "$APP" ]] || { echo "Archive does not contain Orbit.app" >&2; exit 1; }
[[ -x "$EXECUTABLE" ]] || { echo "Missing executable: $EXECUTABLE" >&2; exit 1; }

ARCHES="$(lipo -archs "$EXECUTABLE")"
[[ " $ARCHES " == *" arm64 "* && " $ARCHES " == *" x86_64 "* ]] || {
    echo "Orbit.app is not Universal 2; found architectures: $ARCHES" >&2
    exit 1
}

codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"

echo "Release OK: Orbit $VERSION (build $BUILD), architectures: $ARCHES"
echo "Signature verification passed. Accessibility and Screen Recording still require the manual clean-machine checklist."
