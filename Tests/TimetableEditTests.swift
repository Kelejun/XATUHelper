import Foundation

@main
struct TimetableEditTests {
    static func main() throws {
        let calendar = TimetableDates.calendar
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let nextMonday = TimetableDates.date(week: 2, day: 1, monday: monday)
        func date(_ week: Int, _ day: Int) -> Date {
            TimetableDates.date(week: week, day: day, monday: monday)
        }

        let dated = ManualCourse(name: "实验", teacher: "", room: "", days: [1, 3, 5],
                                 startPeriod: 3, endPeriod: 4, range: .dates(date(2, 2), date(3, 3)))
        let added = TimetableEdit(change: .add(dated))
        let weekBased = TimetableEdit(change: .add(
            ManualCourse(name: "选修", teacher: "", room: "", days: [3], startPeriod: 4, endPeriod: 4,
                         range: .weeks(2, 3))
        ))
        let base = [lesson("a3", period: 3, weeks: [2, 3]), lesson("a4", period: 4, weeks: [3])]
        let original = EditedTimetable(base: base, edits: [added, weekBased], monday: monday, unitCount: 12)
        let blocks = original.occurrences.courseBlocks()
        let datedBlocks = blocks.filter { $0.id.hasPrefix(added.prefix) }
        precondition(datedBlocks.first { $0.day == 1 }?.weeks == [3])
        precondition(datedBlocks.first { $0.day == 3 }?.weeks == [2, 3])
        precondition(datedBlocks.first { $0.day == 5 }?.weeks == [2])
        precondition(blocks.first { $0.occurrenceIDs == ["a3"] }?.weeks == [2])
        precondition(blocks.first { $0.occurrenceIDs == ["a3", "a4"] }?.weeks == [3])
        let conflicts = TimetableConflict.find(added: datedBlocks, among: blocks.filter { !$0.id.hasPrefix(added.prefix) })
        precondition(conflicts.first { $0.course.id.hasPrefix(weekBased.prefix) }?.weeks == [2, 3])
        precondition(conflicts.first { $0.course.occurrenceIDs == ["a3", "a4"] }?.weeks == [3])

        let move = TimetableEdit(change: .move(
            .init(ids: ["a3", "a4"], name: "英语", courseKey: "EN", weeks: [.teachingWeek(3)]),
            .init(day: 4, startPeriod: 5)
        ))
        let wednesday = datedBlocks.first { $0.day == 3 }!
        let deleteDated = TimetableEdit(change: .remove(
            .init(ids: wednesday.occurrenceIDs, name: wednesday.name, courseKey: wednesday.courseKey,
                  weeks: [.date(date(2, 3))])
        ))
        let edits = [added, weekBased, move, deleteDated]
        let encoded = try JSONEncoder().encode(edits)
        let reloaded = try JSONDecoder().decode([TimetableEdit].self, from: encoded)
        let refreshed = EditedTimetable(base: base + [lesson("new", key: "MA", period: 5, weeks: [3], day: 4)],
                                        edits: reloaded, monday: monday, unitCount: 12)
        precondition(refreshed.pending.isEmpty)
        precondition(refreshed.occurrences.first { $0.id == "a3" }?.weeks == [2])
        precondition(!refreshed.occurrences.contains { $0.id == "a4" })
        let refreshedBlocks = refreshed.occurrences.courseBlocks()
        let moved = refreshedBlocks.filter { $0.id.hasPrefix(move.prefix) }
        precondition(moved.count == 1 && moved[0].day == 4 && moved[0].startPeriod == 5 && moved[0].endPeriod == 6)
        precondition(TimetableConflict.find(added: moved, among: refreshedBlocks.filter { $0.occurrenceIDs == ["new"] }).first?.weeks == [3])
        precondition(refreshedBlocks.first { $0.id.hasPrefix(added.prefix) && $0.day == 3 }?.weeks == [3])

        let roomEdit = TimetableEdit(change: .move(
            .init(ids: ["a3", "a4"], name: "英语", courseKey: "EN", weeks: [.teachingWeek(3)]),
            .init(day: 3, startPeriod: 3, room: "教3-201")
        ))
        let savedRoomEdit = try JSONDecoder().decode(TimetableEdit.self, from: JSONEncoder().encode(roomEdit))
        let roomBlocks = EditedTimetable(base: base, edits: [savedRoomEdit], monday: monday, unitCount: 12)
            .occurrences.courseBlocks()
        precondition(roomBlocks.first { $0.id.hasPrefix(roomEdit.prefix) }?.room == "教3-201")
        precondition(roomBlocks.first { $0.occurrenceIDs == ["a3"] }?.room == "")

        let recalibrated = EditedTimetable(base: base, edits: reloaded, monday: nextMonday, unitCount: 12)
        let recalibratedBlocks = recalibrated.occurrences.courseBlocks()
        precondition(recalibratedBlocks.first { $0.id.hasPrefix(added.prefix) && $0.day == 3 }?.weeks == [2])
        precondition(recalibratedBlocks.first { $0.id.hasPrefix(weekBased.prefix) }?.weeks == [2, 3])

        let changed = [lesson("b3", period: 3, weeks: [3]), lesson("b4", period: 4, weeks: [3])]
        let unmatched = EditedTimetable(base: changed, edits: reloaded, monday: monday, unitCount: 12)
        precondition(unmatched.pending[move.id] == [3])
        precondition(unmatched.occurrences.contains { $0.id == "b3" })
        precondition(!unmatched.occurrences.contains { $0.id.hasPrefix(move.prefix) })

        var replacement = move.source!
        replacement.replacements[0] = ["b3", "b4"]
        let repaired = EditedTimetable(base: changed, edits: [move.replacingSource(replacement)], monday: monday, unitCount: 12)
        precondition(repaired.pending.isEmpty && repaired.occurrences.allSatisfy { $0.id.hasPrefix(move.prefix) })
        print("Timetable edit tests passed")
    }

    private static func lesson(_ id: String, key: String = "EN", period: Int, weeks: [Int], day: Int = 3) -> CourseOccurrence {
        CourseOccurrence(id: id, courseKey: key, name: "英语", teacher: "", room: "",
                         day: day, period: period, weeks: weeks, isRemote: false, isPlaceholder: false)
    }
}
