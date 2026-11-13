import Foundation

/// Reduced-frequency cache lifetimes.
enum CacheKind: String, CaseIterable {
    case timetable
    case plan
    case grades
    case exams

    var title: String {
        switch self {
        case .timetable: return "课程表"
        case .plan: return "学业完成情况"
        case .grades: return "成绩"
        case .exams: return "考试安排"
        }
    }

    /// 最短 168 小时（7 天），之后每类再推后一天
    var lifetime: TimeInterval {
        switch self {
        case .timetable: return 168 * 3600
        case .plan: return 192 * 3600
        case .grades: return 216 * 3600
        case .exams: return 240 * 3600
        }
    }
}

enum AcademicRefreshSettings {
    static let reducedKey = "reduceAcademicRefreshFrequency"
    static var reduced: Bool { UserDefaults.standard.bool(forKey: reducedKey) }
}

/// Dates are independent of the semester currently selected for browsing.
enum AcademicRefreshPolicy {
    struct Term {
        var start: Date
        var end: Date?
    }

    static func needsDailyRefresh(_ date: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        date.map { !calendar.isDate($0, inSameDayAs: now) } ?? true
    }

    static func gradesEnabled(terms: [Term], now: Date, calendar: Calendar = .current) -> Bool {
        guard let term = terms.filter({ $0.start <= now }).max(by: { $0.start < $1.start }) else { return false }
        let weekday = calendar.component(.weekday, from: term.start)
        guard let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: calendar.startOfDay(for: term.start)),
              let week12 = calendar.date(byAdding: .day, value: 77, to: monday) else { return false }
        return now >= week12
    }

    static func isVacation(terms: [Term], now: Date, calendar: Calendar = .current) -> Bool {
        guard let term = terms.filter({ $0.start <= now }).max(by: { $0.start < $1.start }),
              let end = term.end else { return false }
        return calendar.startOfDay(for: now) > calendar.startOfDay(for: end)
    }

    static func calendarWindowStart(firstStart: Date, nextYearStart: Date?, calendar: Calendar = .current) -> Date? {
        guard let nextStart = nextYearStart ?? calendar.date(byAdding: .day, value: 364, to: firstStart) else { return nil }
        return calendar.date(byAdding: .day, value: -30, to: nextStart)
    }

    enum CalendarDecision: Equatable {
        case bootstrap
        case wait
        case update(year: Int)
    }

    static func calendarDecision(starts: [Date], pendingYear: Int?, now: Date,
                                 calendar: Calendar = .current) -> CalendarDecision {
        let ordered = starts.sorted()
        guard ordered.count >= 2, let first = ordered.first else { return .bootstrap }
        let year = calendar.component(.year, from: first)
        if let pendingYear, year < pendingYear { return .update(year: pendingYear) }
        guard let window = calendarWindowStart(firstStart: first,
                                               nextYearStart: ordered.count >= 3 ? ordered[2] : nil,
                                               calendar: calendar), now >= window else { return .wait }
        return .update(year: year + 1)
    }

}
