import Foundation

@main
struct WatchHomeTests {
    static func main() {
        let friday = WatchSnapshot.parseDay("2027-12-31")!
        let calendar = WatchSnapshot.campusCalendar
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: friday)!
        }
        func lesson(_ offset: Int) -> WatchSnapshot.Lesson {
            let start = day(offset).addingTimeInterval(8 * 3600)
            return .init(id: String(offset), name: "", room: "", fullRoom: "", teacher: "",
                         periods: "", start: start, end: start.addingTimeInterval(3600))
        }
        func exam(_ offset: Int) -> WatchSnapshot.Exam {
            .init(id: String(offset), name: "", start: day(offset), end: day(offset + 1),
                  time: "", room: "", seat: "", note: "")
        }

        var snapshot = WatchSnapshot.empty
        snapshot.loggedIn = true
        let lateFriday = day(1).addingTimeInterval(-1)
        snapshot.lessons = [lesson(3), lesson(0), lesson(2)]
        precondition(snapshot.nextHomeLesson(at: friday) == lesson(0))
        precondition(snapshot.nextHomeLesson(at: lateFriday) == nil)
        precondition(snapshot.nextTimetableDay(after: friday) == day(2))
        precondition(snapshot.nextHomeLesson(at: day(1)) == lesson(2))
        snapshot.lessons.append(lesson(1))
        precondition(snapshot.nextHomeLesson(at: lateFriday) == lesson(1))
        precondition(snapshot.nextTimetableDay(after: friday) == day(1))
        precondition(snapshot.nextTimetableDay(after: day(3)) == nil)

        for (offset, title) in [(0, "今日课表"), (1, "明日课表"), (2, "后天课表"),
                                (3, "下周一课表"), (9, "下周日课表"), (10, "1月10日课表")] {
            precondition(WatchSnapshot.timetableTitle(for: day(offset), relativeTo: friday) == title)
        }

        snapshot.exams = [exam(8), exam(7), exam(4), exam(3), exam(-1)]
        for offset in [3, 4, 7, 8] {
            switch (offset, snapshot.homeExam(at: lateFriday)) {
            case (3, .aboveCourses(let item)), (4, .belowCourses(let item)), (7, .belowCourses(let item)):
                precondition(item == exam(offset))
            case (8, nil): break
            default: preconditionFailure("Unexpected placement for exam in \(offset) days")
            }
            snapshot.exams.removeAll { $0.id == String(offset) }
        }
        snapshot.exams = [exam(0)]
        guard case .aboveCourses = snapshot.homeExam(at: lateFriday) else { preconditionFailure("Ongoing exam") }
        precondition(snapshot.homeExam(at: day(1)) == nil)
        print("Passed Watch home and timetable checks")
    }
}
