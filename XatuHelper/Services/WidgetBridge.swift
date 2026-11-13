import Foundation
import WidgetKit

/// 把当前状态压成小组件能读的快照，写到 App Group 容器里
extension AppState {
    func publishWidgetSnapshot() {
        guard !isDemoMode else { return }
        PhoneWatchBridge.shared.start(app: self)
        let calendar = WatchSnapshot.campusCalendar
        let today = calendar.startOfDay(for: Date())
        // Calendar 里周日是 1，转成周一=1
        let weekdayIndex = (calendar.component(.weekday, from: today) + 5) % 7 + 1
        let week = TimetableDates.week(of: today, monday: reminderMonday)
        func blocks(on date: Date) -> [CourseBlock] {
            let week = TimetableDates.week(of: date, monday: reminderMonday)
            let day = (calendar.component(.weekday, from: date) + 5) % 7 + 1
            return reminderOccurrences.filter { $0.weeks.contains(week) && $0.day == day }.courseBlocks()
        }

        let todayBlocks = blocks(on: today)

        let courses = todayBlocks.map { block in
            WidgetSnapshot.Course(
                id: block.id,
                name: block.name,
                room: block.shortRoom,
                startMinutes: PeriodSchedule.startMinutes(of: block),
                endMinutes: PeriodSchedule.endMinutes(of: block),
                colorIndex: CoursePalette.index(forCourseKey: block.courseKey)
            )
        }.sorted { $0.startMinutes < $1.startMinutes }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let tomorrowWeekday = (calendar.component(.weekday, from: tomorrow) + 5) % 7 + 1
        let tomorrowCourses = blocks(on: tomorrow)
            .filter { $0.day == tomorrowWeekday && !$0.isPlaceholder && !$0.isRemote }
            .map { block in
                WidgetSnapshot.Course(
                    id: block.id,
                    name: block.name,
                    room: block.shortRoom,
                    startMinutes: PeriodSchedule.startMinutes(of: block),
                    endMinutes: PeriodSchedule.endMinutes(of: block),
                    colorIndex: CoursePalette.index(forCourseKey: block.courseKey)
                )
            }
            .sorted { $0.startMinutes < $1.startMinutes }

        var snapshot = WidgetSnapshot(
            generatedAt: Date(),
            week: week,
            weekday: weekdayIndex,
            courses: courses,
            tomorrowCourses: tomorrowCourses,
            tomorrowWeekday: tomorrowWeekday,
            balance: electricityBalance.flatMap(Double.init),
            balanceUpdatedAt: electricityCheckedAt,
            roomName: dorm?.roomName,
            upcomingBreak: upcomingBreakForWidget(),
            nextExam: nextExamForWidget(),
            loggedIn: isLoggedIn
        )

        snapshot.datedCourses = (0..<14).flatMap { offset -> [WidgetSnapshot.Course] in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return blocks(on: date).map { block in
                WidgetSnapshot.Course(id: "\(offset)-\(block.id)", name: block.name, room: block.shortRoom,
                    startMinutes: PeriodSchedule.startMinutes(of: block), endMinutes: PeriodSchedule.endMinutes(of: block),
                    colorIndex: CoursePalette.index(forCourseKey: block.courseKey), day: date)
            }.sorted { $0.startMinutes < $1.startMinutes }
        }
        if !isLoggedIn { snapshot = .empty }
        WidgetStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func upcomingBreakForWidget() -> WidgetSnapshot.Break? {
        guard let info = CalendarCache.load(), !info.semesters.isEmpty else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = Self.dayKeyFormatter
        var candidates: [(String, Date)] = []

        for (index, span) in info.semesters.enumerated() {
            if let start = formatter.date(from: span.start) {
                candidates.append(("\(span.label)开学", start))
            }
            if let end = formatter.date(from: span.end),
               let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: end) {
                candidates.append((index == 0 ? "放寒假" : "放暑假", dayAfter))
            }
        }

        guard let next = candidates
            .filter({ $0.1 >= today })
            .min(by: { $0.1 < $1.1 }) else { return nil }

        let days = Calendar.current.dateComponents([.day], from: today, to: next.1).day ?? 0
        return WidgetSnapshot.Break(title: next.0, date: next.1, days: days)
    }

    private func nextExamForWidget() -> WidgetSnapshot.Exam? {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = Self.dayKeyFormatter

        let upcoming = currentExams
            .compactMap { exam -> (ExamRecord, Date)? in
                guard let date = formatter.date(from: exam.dateKey), date >= today else { return nil }
                return (exam, date)
            }
            .sorted { $0.1 < $1.1 }

        guard let first = upcoming.first else { return nil }
        let days = Calendar.current.dateComponents([.day], from: today, to: first.1).day ?? 0
        return WidgetSnapshot.Exam(title: first.0.course, date: first.1, days: days)
    }

    static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
