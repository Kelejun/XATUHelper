import Foundation
import WidgetKit

/// 把当前状态压成小组件能读的快照，写到 App Group 容器里
extension AppState {
    func publishWidgetSnapshot() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Calendar 里周日是 1，转成周一=1
        let weekdayIndex = (calendar.component(.weekday, from: today) + 5) % 7 + 1
        let week = currentWeek

        let blocks = occurrences(in: week)
            .courseBlocks()
            .filter { $0.day == weekdayIndex }

        let courses = blocks.map { block in
            WidgetSnapshot.Course(
                id: block.id,
                name: block.name,
                room: block.shortRoom,
                startMinutes: PeriodSchedule.startMinutes(of: block),
                endMinutes: PeriodSchedule.endMinutes(of: block)
            )
        }.sorted { $0.startMinutes < $1.startMinutes }

        let snapshot = WidgetSnapshot(
            generatedAt: Date(),
            week: week,
            weekday: weekdayIndex,
            courses: courses,
            balance: electricityBalance.flatMap(Double.init),
            balanceUpdatedAt: electricityCheckedAt,
            roomName: dorm?.displayName,
            upcomingBreak: upcomingBreakForWidget(),
            nextExam: nextExamForWidget(),
            loggedIn: isLoggedIn
        )

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
            if index < info.semesters.count - 1,
               let end = formatter.date(from: span.end),
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

        let upcoming = exams
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
