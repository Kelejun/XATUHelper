#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/xatu-timetable-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
    XatuHelper/Models/Course.swift XatuHelper/Models/TimetableEdit.swift \
    Tests/TimetableEditTests.swift -o "$test_dir/timetable-tests"
"$test_dir/timetable-tests"
