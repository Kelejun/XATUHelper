#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/xatu-exit-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
    XatuHelper/Services/TerminationNotificationSubmission.swift \
    Tests/TerminationNotificationSubmissionTests.swift -o "$test_dir/submission-tests"
"$test_dir/submission-tests"
