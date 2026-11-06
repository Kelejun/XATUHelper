#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/xatu-watch-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
    Shared/WatchSnapshot.swift Shared/CampusGreeting.swift Tests/WatchSnapshotTests.swift -o "$test_dir/watch-tests"
"$test_dir/watch-tests"
