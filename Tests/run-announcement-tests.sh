#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/xatu-announcement-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -swift-version 5 -D DEBUG -module-cache-path "$test_dir/module-cache" \
    XatuHelper/Services/Announcements.swift XatuHelper/Services/AnnouncementHistory.swift \
    XatuHelper/Services/AnnouncementMarkdown.swift XatuHelper/Services/AnnouncementImageStore.swift Tests/AnnouncementTests.swift -o "$test_dir/tests"
"$test_dir/tests"
