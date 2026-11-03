#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/xatu-electricity-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
    XatuHelper/Services/ElectricityRefreshPolicy.swift \
    XatuHelper/Models/ElectricityRecord.swift \
    XatuHelper/Services/ElectricityHistoryStore.swift \
    Tests/ElectricityRefreshPolicyTests.swift -o "$test_dir/refresh-tests"
"$test_dir/refresh-tests"
