#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/xatu-checkin-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -swift-version 5 -module-cache-path "$test_dir/module-cache" \
    XatuHelper/Services/LocationCoordinateTransform.swift \
    XatuHelper/Services/CheckinLocationSettings.swift \
    Tests/CheckinLocationSettingsTests.swift -o "$test_dir/settings-tests"
"$test_dir/settings-tests"
swiftc -parse-as-library -swift-version 5 -module-cache-path "$test_dir/module-cache" \
    XatuHelper/Services/WebLocationScript.swift \
    Tests/WebLocationFrameTests.swift -o "$test_dir/frame-tests"
"$test_dir/frame-tests"
