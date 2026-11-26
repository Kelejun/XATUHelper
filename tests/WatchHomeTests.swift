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
        checkCourseProgress(on: friday)
        checkExamActivity(on: friday)
        print("Passed Watch home and timetable checks")
    }

    static func checkExamActivity(on day: Date) {
        func time(_ minute: Int) -> Date { day.addingTimeInterval(Double(minute * 60)) }
        let morning = WatchSnapshot.Exam(id: "e1", name: "数据结构", start: time(540), end: time(660),
                                         time: "09:00-11:00", room: "教3-402", seat: "28", note: "", hasStartTime: true)
        let afternoon = WatchSnapshot.Exam(id: "e2", name: "大学英语", start: time(840), end: time(960),
                                           time: "14:00-16:00", room: "", seat: "", note: "", hasStartTime: true)
        let untimed = WatchSnapshot.Exam(id: "e3", name: "体育", start: time(0), end: time(1440),
                                         time: "", room: "操场", seat: "", note: "", hasStartTime: false)
        let third = WatchSnapshot.Exam(id: "e4", name: "计算机网络", start: time(1080), end: time(1200),
                                       time: "18:00-20:00", room: "教2-101", seat: "12", note: "", hasStartTime: true)

        var snapshot = WatchSnapshot.empty
        snapshot.loggedIn = true
        snapshot.exams = [third, afternoon, untimed, morning]

        let before = ExamActivitySlot.upcoming(in: snapshot, at: time(470))
        precondition(before.map(\.exam.id) == ["e1", "e2"])
        precondition(before[0].visibleFrom == time(480) && before[0].begins == time(480))
        precondition(before[0].activityID == "exam-e1")
        precondition(before[1].visibleFrom == time(780))
        precondition(morning.displayRoom == "教3-402" && morning.displaySeat == "28")
        precondition(afternoon.displayRoom == "考场待定" && afternoon.displaySeat == nil)

        // Custom lead time (e.g. 45 minutes)
        let customLead = ExamActivitySlot.upcoming(in: snapshot, at: time(470), leadMinutes: 45)
        precondition(customLead.first?.visibleFrom == time(495))

        // No "in-exam" state: once start time is reached, it is excluded immediately.
        let atStart = ExamActivitySlot.upcoming(in: snapshot, at: time(540))
        precondition(atStart.map(\.exam.id) == ["e2", "e4"])

        // Untimed exams are never scheduled.
        snapshot.exams = [untimed]
        precondition(ExamActivitySlot.upcoming(in: snapshot, at: time(-30)).isEmpty)

        // Signed-out snapshot returns nothing.
        snapshot.exams = [morning]
        snapshot.loggedIn = false
        precondition(ExamActivitySlot.upcoming(in: snapshot, at: time(470)).isEmpty)
    }

    static func checkCourseProgress(on day: Date) {
        func time(_ minute: Int) -> Date { day.addingTimeInterval(Double(minute * 60)) }
        func lesson(_ room: String, _ start: Int, _ end: Int) -> WatchSnapshot.Lesson {
            .init(id: room, name: "", room: room, fullRoom: "", teacher: "", periods: "",
                  start: time(start), end: time(end))
        }
        var snapshot = WatchSnapshot.empty
        snapshot.loggedIn = true
        let first = lesson("5B502", 500, 600)
        for gap in [10, 20, 30, 31] {
            let next = lesson("3A201", 600 + gap, 700)
            snapshot.lessons = [next, first]
            func state(at minute: Int) -> WatchCourseProgress {
                WatchCourseProgress(snapshot: snapshot, at: time(minute))
            }
            let preparation = state(at: 470)
            precondition(preparation.previous == nil && preparation.preparationInterval == time(470)...first.start)
            let firstStart = state(at: 500)
            precondition(firstStart.lesson == first && firstStart.preparationInterval == nil)
            let before = CourseActivitySlot.upcoming(in: snapshot, at: time(469))
            precondition(before.map(\.lesson) == [first, next] && before[0].visibleFrom == time(470))
            let classOnly = CourseActivitySlot.upcoming(in: snapshot, at: time(480), beforeClass: false)
            precondition(classOnly.map(\.visibleFrom) == [first.start, next.start])
            precondition(classOnly.allSatisfy { $0.includesClass && $0.previousRoom == nil })
            let preparationOnly = CourseActivitySlot.upcoming(in: snapshot, at: time(480), duringClass: false)
            precondition(preparationOnly.map(\.lesson) == [first, next] && !preparationOnly[0].includesClass)
            precondition(CourseActivitySlot.upcoming(in: snapshot, at: first.start, duringClass: false).map(\.lesson) == [next])
            precondition(CourseActivitySlot.upcoming(in: snapshot, at: first.start, beforeClass: false, duringClass: false).isEmpty)
            let during = CourseActivitySlot.upcoming(in: snapshot, at: time(550))
            precondition(during.map(\.lesson) == [first, next])
            precondition(during[1].visibleFrom == time(max(600, 600 + gap - 30)))
            precondition(during[1].previousRoom == (gap <= 30 ? first.displayRoom : nil))
            let atEnd = CourseActivitySlot.upcoming(in: snapshot, at: time(700))
            precondition(atEnd.isEmpty)
            let breakStart = max(600, 600 + gap - 30)
            let between = state(at: 600)
            precondition(between.lesson == next && between.previous == (gap <= 30 ? first : nil))
            precondition(between.preparationInterval == time(breakStart)...next.start)
            let nextStart = state(at: 600 + gap)
            precondition(nextStart.lesson == next && nextStart.preparationInterval == nil)
        }
        // Custom before-class lead time applies before first class, while between-class breaks stay automatic.
        let shortBreakNext = lesson("3A201", 620, 700)
        snapshot.lessons = [first, shortBreakNext]
        let customFirst = CourseActivitySlot.upcoming(in: snapshot, at: time(400), beforeLeadMinutes: 45)
        precondition(customFirst.first?.visibleFrom == time(455) && customFirst.first?.begins == time(455))
        precondition(customFirst.last?.visibleFrom == time(600) && customFirst.last?.previousRoom == first.displayRoom)
        let shortLead = CourseActivitySlot.upcoming(in: snapshot, at: time(400), beforeLeadMinutes: 15)
        precondition(shortLead.first?.visibleFrom == time(485))
        precondition(shortLead.last?.visibleFrom == time(600) && shortLead.last?.previousRoom == first.displayRoom)

        let afternoon = lesson("3A201", 730, 790)
        snapshot.lessons = [lesson("5B502", 660, 720), afternoon]
        let lunch = WatchCourseProgress(snapshot: snapshot, at: time(720))
        precondition(lunch.lesson == afternoon && lunch.previous == nil)
        precondition(lunch.preparationInterval == time(700)...time(730))
        let beforeLunch = CourseActivitySlot.upcoming(in: snapshot, at: time(690))
        precondition(beforeLunch.last?.visibleFrom == time(720) && beforeLunch.last?.previousRoom == nil)
        snapshot.lessons = [lesson("5B502", -60, -5), lesson("3A201", 10, 60)]
        precondition(WatchCourseProgress(snapshot: snapshot, at: time(0)).previous == nil)
        snapshot.loggedIn = false
        let signedOut = WatchCourseProgress(snapshot: snapshot, at: time(0))
        precondition(signedOut.lesson == nil && signedOut.preparationInterval == nil)
        precondition(CourseActivitySlot.upcoming(in: snapshot, at: time(0)).isEmpty)
    }
}
