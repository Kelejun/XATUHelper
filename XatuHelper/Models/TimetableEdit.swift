import Foundation

enum TimetableWeek: Codable {
    case teachingWeek(Int)
    case date(Date)

    func resolve(monday: Date) -> Int {
        switch self {
        case .teachingWeek(let week): return week
        case .date(let date): return TimetableDates.week(of: date, monday: monday)
        }
    }
}

enum TimetableDates {
    static let weeks = 1...30
    static let calendar = Calendar(identifier: .gregorian)

    static func date(week: Int, day: Int, monday: Date) -> Date {
        calendar.date(byAdding: .day, value: (week - 1) * 7 + day - 1,
                      to: calendar.startOfDay(for: monday)) ?? monday
    }

    static func week(of date: Date, monday: Date) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: monday),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return Int(floor(Double(days) / 7)) + 1
    }
}

struct ManualCourse: Codable {
    enum Range: Codable {
        case weeks(Int, Int)
        case dates(Date, Date)
    }

    var name: String
    var teacher: String
    var room: String
    var days: Set<Int>
    var startPeriod: Int
    var endPeriod: Int
    var range: Range

    var usesDates: Bool {
        if case .dates = range { return true }
        return false
    }

    func weeks(for day: Int, monday: Date) -> [Int] {
        TimetableDates.weeks.filter { week in
            switch range {
            case .weeks(let first, let last): return first <= week && week <= last
            case .dates(let first, let last):
                let date = TimetableDates.date(week: week, day: day, monday: monday)
                let calendar = TimetableDates.calendar
                return calendar.startOfDay(for: first) <= date && date <= calendar.startOfDay(for: last)
            }
        }
    }
}

struct TimetableEdit: Codable, Identifiable {
    struct Source: Codable {
        var ids: [String]
        var name: String
        var courseKey: String
        var weeks: [TimetableWeek]
        var replacements: [Int: [String]] = [:]
    }

    struct Destination: Codable {
        var day: Int
        var startPeriod: Int
        var room: String? = nil
    }

    enum Change: Codable {
        case add(ManualCourse)
        case move(Source, Destination)
        case remove(Source)
    }

    var id = UUID()
    var change: Change

    var title: String {
        switch change {
        case .add(let course): return "添加 · \(course.name)"
        case .move(let source, _): return "修改 · \(source.name)"
        case .remove(let source): return "移除 · \(source.name)"
        }
    }

    var source: Source? {
        switch change {
        case .add: return nil
        case .move(let source, _), .remove(let source): return source
        }
    }

    func replacingSource(_ source: Source) -> Self {
        var edit = self
        switch change {
        case .add: break
        case .move(_, let destination): edit.change = .move(source, destination)
        case .remove: edit.change = .remove(source)
        }
        return edit
    }

    var prefix: String { "local-\(id.uuidString)|" }
}

struct EditedTimetable {
    var occurrences: [CourseOccurrence]
    var pending: [UUID: [Int]] = [:]

    init(base: [CourseOccurrence], edits: [TimetableEdit], monday: Date, unitCount: Int) {
        var byID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func insert(_ occurrence: CourseOccurrence) {
            var item = occurrence
            item.weeks = Set(byID[item.id]?.weeks ?? []).union(item.weeks).sorted()
            byID[item.id] = item
        }

        for edit in edits {
            let source: TimetableEdit.Source
            let destination: TimetableEdit.Destination?
            switch edit.change {
            case .add(let course):
                guard course.startPeriod >= 1, course.startPeriod <= course.endPeriod,
                      course.endPeriod <= unitCount else { continue }
                for day in course.days.sorted() {
                    let weeks = course.weeks(for: day, monday: monday)
                    guard !weeks.isEmpty else { continue }
                    let key = "local-" + edit.id.uuidString
                    for period in course.startPeriod...course.endPeriod {
                        insert(CourseOccurrence(id: "\(edit.prefix)\(day)|\(period)", courseKey: key, name: course.name,
                                                teacher: course.teacher, room: course.room, day: day,
                                                period: period, weeks: weeks, isRemote: false,
                                                isPlaceholder: false, usesFixedDates: course.usesDates))
                    }
                }
                continue
            case .move(let original, let target):
                source = original
                destination = target
            case .remove(let original):
                source = original
                destination = nil
            }

            for (index, anchor) in source.weeks.enumerated() {
                let week = anchor.resolve(monday: monday)
                guard TimetableDates.weeks.contains(week) else { continue }
                let ids = source.replacements[index] ?? source.ids
                let matches = ids.compactMap { id -> CourseOccurrence? in
                    guard let occurrence = byID[id], occurrence.weeks.contains(week) else { return nil }
                    return occurrence
                }.sorted { $0.period < $1.period }
                guard !matches.isEmpty, matches.count == ids.count,
                      destination.map({ $0.startPeriod >= 1 && $0.startPeriod + matches.count - 1 <= unitCount }) ?? true else {
                    pending[edit.id, default: []].append(week)
                    continue
                }

                for (offset, original) in matches.enumerated() {
                    var remaining = original
                    remaining.weeks.removeAll { $0 == week }
                    byID[original.id] = remaining.weeks.isEmpty ? nil : remaining
                    if let destination {
                        var moved = original
                        moved.id = edit.prefix + String(offset)
                        moved.day = destination.day
                        moved.period = destination.startPeriod + offset
                        moved.room = destination.room ?? original.room
                        moved.weeks = [week]
                        insert(moved)
                    }
                }
            }
        }
        occurrences = byID.values.sorted { ($0.day, $0.period, $0.id) < ($1.day, $1.period, $1.id) }
    }
}

struct TimetableConflict: Identifiable {
    let course: CourseBlock
    let weeks: [Int]
    var id: String { course.id }

    static func find(added: [CourseBlock], among others: [CourseBlock]) -> [Self] {
        others.compactMap { other in
            var weeks = Set<Int>()
            for block in added where block.day == other.day
                && block.startPeriod <= other.endPeriod && other.startPeriod <= block.endPeriod {
                weeks.formUnion(Set(block.weeks).intersection(other.weeks))
            }
            return weeks.isEmpty ? nil : Self(course: other, weeks: weeks.sorted())
        }
    }
}

enum TimetableEditError: LocalizedError {
    case unavailable
    case sourceChanged

    var errorDescription: String? {
        switch self {
        case .unavailable: return "当前课表无法修改。"
        case .sourceChanged: return "课程安排已变化，请关闭编辑后重新选择课程。"
        }
    }
}
