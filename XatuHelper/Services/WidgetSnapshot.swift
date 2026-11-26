import Foundation

/// App 和小组件共用的快照，两边都编进 target
struct WidgetSnapshot: Codable {
    struct Course: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var room: String
        var startMinutes: Int
        var endMinutes: Int
        var colorIndex: Int? = nil
        var day: Date? = nil
    }

    struct Break: Codable, Hashable {
        var title: String
        var date: Date
        var days: Int
    }

    struct Exam: Codable, Hashable {
        var title: String
        var date: Date?
        var days: Int?
        var end: Date?
        var startTime: String?
        var room: String?
        var seat: String?
    }

    var generatedAt: Date
    var week: Int
    var weekday: Int
    var courses: [Course]
    var tomorrowCourses: [Course]? = nil
    var tomorrowWeekday: Int? = nil
    var datedCourses: [Course]? = nil
    var balance: Double?
    var balanceUnit: String? = nil
    var balanceUpdatedAt: Date?
    var roomName: String?
    var upcomingBreak: Break?
    var nextExam: Exam?
    var upcomingExams: [Exam]?
    var loggedIn: Bool

    static let empty = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        week: 0,
        weekday: 1,
        courses: [],
        balance: nil,
        balanceUpdatedAt: nil,
        roomName: nil,
        upcomingBreak: nil,
        nextExam: nil,
        loggedIn: false
    )

    func resolved(at date: Date) -> Self {
        var value = self
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.startOfDay(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: generatedAt), to: today).day ?? 0
        if let datedCourses {
            value.courses = datedCourses.filter { $0.day.map { calendar.isDate($0, inSameDayAs: today) } ?? false }
            value.tomorrowCourses = datedCourses.filter { $0.day.map { calendar.isDate($0, inSameDayAs: tomorrow) } ?? false }
        } else if elapsed != 0 {
            value.courses = elapsed == 1 ? (tomorrowCourses ?? []) : []
            value.tomorrowCourses = []
        }
        value.weekday = (calendar.component(.weekday, from: today) + 5) % 7 + 1
        value.tomorrowWeekday = (calendar.component(.weekday, from: tomorrow) + 5) % 7 + 1
        value.week += (elapsed + weekday - 1) / 7
        if let item = upcomingBreak {
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: item.date)).day ?? 0
            value.upcomingBreak = days >= 0 ? Break(title: item.title, date: item.date, days: days) : nil
        }
        let exams = upcomingExams ?? nextExam.map { [$0] } ?? []
        let remaining: [Exam] = exams.compactMap { exam in
            guard let start = exam.date else { return nil }
            let isRemaining = exam.end.map { $0 > date } ?? (start >= today)
            guard isRemaining else { return nil }
            var updated = exam
            updated.days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: start)).day
            return updated
        }
        value.upcomingExams = remaining
        value.nextExam = remaining.first
        return value
    }

    func examTimelineDates(after now: Date, days: Int = 7) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let startOfToday = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: max(1, days), to: startOfToday)!
        var dates: [Date] = [now]
        for offset in 1...max(1, days) {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: startOfToday) {
                dates.append(midnight)
            }
        }
        let exams = upcomingExams ?? nextExam.map { [$0] } ?? []
        dates.append(contentsOf: exams.compactMap(\.end).filter { $0 > now && $0 <= horizon })
        return Array(Set(dates)).sorted()
    }

    var resolvedBalanceUnit: String {
        balanceUnit == "元" ? "元" : "度"
    }

    var isAmountBalance: Bool {
        resolvedBalanceUnit == "元"
    }

    var electricityWidgetTitle: String {
        isAmountBalance ? "宿舍电费" : "宿舍电量"
    }

    var electricityLowHeading: String {
        isAmountBalance ? "宿舍余额偏低" : "宿舍电量偏低"
    }

    var electricityLowHint: String {
        isAmountBalance ? "余额偏低，记得充值" : "电量偏低，记得充值"
    }

    var electricityAvailableHint: String {
        isAmountBalance ? "剩余可用金额" : "剩余可用电量"
    }

    var weekdayLabel: String { Self.weekdayLabel(weekday) }

    static func weekdayLabel(_ index: Int) -> String {
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard index >= 1, index <= names.count else { return "" }
        return names[index - 1]
    }

    static var campusCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    static func minutes(of date: Date) -> Int {
        let calendar = campusCalendar
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// 共享容器，读不到就说明没开 App Group
enum WidgetStore {
    static let appGroup = "group.com.cell.xatuapp"
    static let fileName = "widget-snapshot.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
