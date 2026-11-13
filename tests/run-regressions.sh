#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d /tmp/xatu-regressions.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
swiftc -module-cache-path "$build_dir/modules" \
  XatuHelper/Services/CachePolicy.swift XatuHelper/Models/Grade.swift \
  tests/AcademicRefreshPolicyTests.swift -o "$build_dir/academic"
"$build_dir/academic"
swiftc -module-cache-path "$build_dir/modules" \
  XatuHelper/Models/Course.swift XatuHelper/Models/Grade.swift \
  XatuHelper/Models/Exam.swift XatuHelper/Models/Plan.swift XatuHelper/Models/PlanCatalog.swift \
  XatuHelper/Services/TimetableParser.swift XatuHelper/Services/EamsService.swift \
  XatuHelper/Services/WidgetSnapshot.swift XatuHelper/Services/GradeStore.swift \
  XatuHelper/Services/LocalJSONFile.swift tests/RepositoryRegressionTests.swift \
  -o "$build_dir/repository"
"$build_dir/repository"
