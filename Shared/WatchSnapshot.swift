import Foundation

/// Phone-authored, dated data. The watch never contacts campus services.
struct WatchSnapshot: Codable, Equatable {
    static let schemaVersion = 1
    var schema = schemaVersion
    var generatedAt: Date
    var accountID: String
    var loggedIn: Bool
    var semester: String
    var weekOneMonday: Date
    var timetableUpdatedAt: Date?
    var examsUpdatedAt: Date?
    var lessons: [Lesson]
    var exams: [Exam]
    var balance: String?
    var balanceUpdatedAt: Date?
    var roomName: String?
    var holidays: [Holiday]

    struct Lesson: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var room: String
        var fullRoom: String
        var teacher: String
        var periods: String
        var start: Date
        var end: Date
        var colorIndex: Int? = nil
    }

    struct Exam: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var start: Date
        /// Unknown end times stay visible until the end of the examination day.
        var end: Date
        var time: String
        var room: String
        var seat: String
        var note: String
    }

    struct Holiday: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var date: Date
    }

    static var campusCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.locale = Locale(identifier: "zh_CN")
        return value
    }

    static var empty: Self {
        Self(generatedAt: .distantPast, accountID: "", loggedIn: false, semester: "",
             weekOneMonday: .distantPast, lessons: [], exams: [], holidays: [])
    }

    func lessons(on date: Date) -> [Lesson] {
        guard loggedIn else { return [] }
        return lessons.filter { Self.campusCalendar.isDate($0.start, inSameDayAs: date) }
            .sorted { $0.start < $1.start }
    }

    func currentLesson(at date: Date) -> Lesson? {
        guard loggedIn else { return nil }
        return lessons.filter { $0.start <= date && date < $0.end }.min { $0.end < $1.end }
    }

    func nextLesson(at date: Date) -> Lesson? {
        guard loggedIn else { return nil }
        return lessons.filter { $0.start > date }.min { $0.start < $1.start }
    }

    func upcomingExams(at date: Date) -> [Exam] {
        guard loggedIn else { return [] }
        return exams.filter { $0.end > date }.sorted { $0.start < $1.start }
    }

    func todayExam(at date: Date) -> Exam? {
        upcomingExams(at: date).first { Self.campusCalendar.isDate($0.start, inSameDayAs: date) }
    }

    func nearExam(at date: Date) -> Exam? {
        guard let exam = upcomingExams(at: date).first,
              Self.days(from: date, to: exam.start) <= 7 else { return nil }
        return exam
    }

    func nextHoliday(at date: Date) -> Holiday? {
        guard loggedIn else { return nil }
        let today = Self.campusCalendar.startOfDay(for: date)
        return holidays.filter { $0.date >= today }.min { $0.date < $1.date }
    }

    func week(at date: Date) -> Int {
        let days = Self.days(from: weekOneMonday, to: date)
        return days < 0 ? 0 : days / 7 + 1
    }

    static func days(from: Date, to: Date) -> Int {
        let calendar = campusCalendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                       to: calendar.startOfDay(for: to)).day ?? 0
    }

    static func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = campusCalendar
        formatter.timeZone = campusCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    static func clock(_ date: Date) -> String { format(date, "HH:mm") }
    static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = campusCalendar
        formatter.timeZone = campusCalendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    static func dayLabel(_ date: Date, relativeTo now: Date) -> String {
        switch days(from: now, to: date) {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        default: return format(date, "M月d日")
        }
    }

    /// Known transitions are precomputed for complications, without a network round trip.
    func timelineDates(after date: Date, horizon: TimeInterval = 48 * 3600) -> [Date] {
        let limit = date.addingTimeInterval(horizon)
        var values = lessons.flatMap { [$0.start, $0.end] } + exams.flatMap { [$0.start, $0.end] }
        let calendar = Self.campusCalendar
        for offset in 1...3 {
            if let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) {
                values.append(day)
            }
        }
        return Array(Set(values.filter { $0 > date && $0 <= limit })).sorted()
    }
}

/// A descriptor can clear a switched/logged-out account before a large file arrives.
struct WatchSyncDescriptor: Codable, Equatable {
    var generatedAt: Date
    var accountID: String
    var loggedIn: Bool

    init(_ snapshot: WatchSnapshot) {
        generatedAt = snapshot.generatedAt
        accountID = snapshot.accountID
        loggedIn = snapshot.loggedIn
    }
}

struct WatchCache: Codable {
    var descriptor: WatchSyncDescriptor?
    var snapshot: WatchSnapshot?

    mutating func receive(_ incoming: WatchSyncDescriptor) -> Bool {
        guard descriptor.map({ incoming.generatedAt >= $0.generatedAt }) ?? true else { return false }
        if !incoming.loggedIn || snapshot?.accountID != incoming.accountID {
            snapshot = nil
        }
        descriptor = incoming
        return true
    }

    mutating func receive(_ incoming: WatchSnapshot) -> Bool {
        guard incoming.schema == WatchSnapshot.schemaVersion,
              descriptor.map({ incoming.generatedAt >= $0.generatedAt }) ?? true else { return false }
        descriptor = WatchSyncDescriptor(incoming)
        snapshot = incoming.loggedIn ? incoming : nil
        return true
    }
}
