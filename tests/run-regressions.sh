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
swiftc -module-cache-path "$build_dir/modules" \
  XatuHelper/Models/ElectricityRecord.swift XatuHelper/Models/Dorm.swift \
  XatuHelper/Services/WidgetSnapshot.swift Shared/WatchSnapshot.swift \
  tests/ElectricityUsageTests.swift \
  -o "$build_dir/electricity"
"$build_dir/electricity"
swiftc -module-cache-path "$build_dir/modules" \
  Shared/WatchSnapshot.swift Shared/WatchCourseProgress.swift Shared/CourseActivitySlot.swift tests/WatchHomeTests.swift -o "$build_dir/watch-home"
"$build_dir/watch-home"
swiftc -module-cache-path "$build_dir/modules" \
  Shared/WatchSnapshot.swift Shared/WatchCourseProgress.swift Shared/CourseActivitySlot.swift \
  XatuHelper/Models/Course.swift XatuHelper/Models/Exam.swift XatuHelper/Models/ReminderPreviewData.swift \
  tests/ReminderPreviewTests.swift -o "$build_dir/reminder-preview"
"$build_dir/reminder-preview"
swiftc -module-cache-path "$build_dir/modules" \
  XatuHelper/Models/Course.swift XatuHelper/Models/Exam.swift \
  XatuHelper/Services/WidgetSnapshot.swift tests/ExamDisplayTests.swift \
  -o "$build_dir/exam-display"
"$build_dir/exam-display"
