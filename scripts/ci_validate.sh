#!/bin/bash
# Validate the release metadata and test counts used by CI.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

BUILD_SETTINGS="$(xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Release -showBuildSettings)"
MARKETING_VERSION="$(awk -F' = ' '$1 ~ /^[[:space:]]*MARKETING_VERSION$/ { print $2; exit }' <<< "$BUILD_SETTINGS")"
BUILD_NUMBER="$(awk -F' = ' '$1 ~ /^[[:space:]]*CURRENT_PROJECT_VERSION$/ { print $2; exit }' <<< "$BUILD_SETTINGS")"
ARCHS="$(awk -F' = ' '$1 ~ /^[[:space:]]*ARCHS$/ { print $2; exit }' <<< "$BUILD_SETTINGS")"

[[ -n "$MARKETING_VERSION" ]] || { echo "MARKETING_VERSION was not found" >&2; exit 1; }
[[ -n "$BUILD_NUMBER" ]] || { echo "CURRENT_PROJECT_VERSION was not found" >&2; exit 1; }
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
    echo "Release ARCHS must include arm64 and x86_64; got: $ARCHS" >&2
    exit 1
}

EXPECTED_SOURCE_VERSION="${MARKETING_VERSION} (build ${BUILD_NUMBER})"
EXPECTED_SOURCE_VERSION_ZH="${MARKETING_VERSION}（build ${BUILD_NUMBER}）"
grep -Fq "Current source build: \`${EXPECTED_SOURCE_VERSION}\`." README.md || {
    echo "README.md does not contain the current source version: $EXPECTED_SOURCE_VERSION" >&2
    exit 1
}
grep -Fq "当前源码版本：\`${EXPECTED_SOURCE_VERSION_ZH}\`。" README.zh-CN.md || {
    echo "README.zh-CN.md does not contain the current source version: $EXPECTED_SOURCE_VERSION_ZH" >&2
    exit 1
}
grep -Eq "^## ${MARKETING_VERSION//./\\.} —" CHANGELOG.md || {
    echo "CHANGELOG.md does not start with version $MARKETING_VERSION" >&2
    exit 1
}

UNIT_TEST_COUNT="$(grep -Ec '^[[:space:]]*@Test' OrbitTests/OrbitTests.swift)"
UI_TEST_COUNT="$(find OrbitUITests -type f -name '*.swift' -exec grep -Ehc '^[[:space:]]*func test' {} + | awk '{ total += $1 } END { print total + 0 }')"
# Keep these three in step with each other. Two commits in a row changed the
# suite without touching this file, which is exactly the drift the check exists
# to catch — so it names the file to edit rather than only the number it wanted.
EXPECTED_UNIT_TESTS=61
EXPECTED_UI_TESTS=2

[[ "$UNIT_TEST_COUNT" == "$EXPECTED_UNIT_TESTS" ]] || {
    echo "Expected $EXPECTED_UNIT_TESTS OrbitTests tests; found $UNIT_TEST_COUNT." >&2
    echo "If the change is intended, update EXPECTED_UNIT_TESTS in $0 and the CHANGELOG test-count line." >&2
    exit 1
}
[[ "$UI_TEST_COUNT" == "$EXPECTED_UI_TESTS" ]] || {
    echo "Expected $EXPECTED_UI_TESTS OrbitUITests methods; found $UI_TEST_COUNT" >&2
    exit 1
}
grep -Eq "$EXPECTED_UNIT_TESTS.*OrbitTests.*$EXPECTED_UI_TESTS.*OrbitUITests|$EXPECTED_UI_TESTS.*OrbitUITests.*$EXPECTED_UNIT_TESTS.*OrbitTests" CHANGELOG.md || {
    echo "CHANGELOG.md does not declare $EXPECTED_UNIT_TESTS OrbitTests and $EXPECTED_UI_TESTS OrbitUITests" >&2
    exit 1
}

if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    EXPECTED_TAG="v${MARKETING_VERSION}"
    [[ "${GITHUB_REF_NAME:-}" == "$EXPECTED_TAG" ]] || {
        echo "Release tag must be $EXPECTED_TAG; got ${GITHUB_REF_NAME:-<missing>}" >&2
        exit 1
    }
fi

echo "Metadata OK: $MARKETING_VERSION (build $BUILD_NUMBER), ARCHS=$ARCHS, tests=$UNIT_TEST_COUNT+$UI_TEST_COUNT"
