import Foundation

@main
struct ExamDisplayTests {
    static func main() {
        let calendar = ExamRecord.campusCalendar
        func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(
                timeZone: calendar.timeZone,
                year: year, month: month, day: day, hour: hour, minute: minute
            ))!
        }

        let morning = ExamRecord(
            id: "e1", course: "高等数学", code: "M1", name: "期末",
            time: "2026-11-25 09:00-11:00", room: "教1-101", seat: "12", note: ""
        )
        let afternoon = ExamRecord(
            id: "e2", course: "线性代数", code: "M2", name: "期末",
            time: "2026-11-25 14:30：00~16：30", room: "教2-205", seat: "8", note: ""
        )
        let startOnly = ExamRecord(
            id: "e3", course: "大学物理", code: "P1", name: "期末",
            time: "2026-11-25 19:00", room: "教3-301", seat: "", note: ""
        )
        let reversedOrder = ExamRecord(
            id: "e4", course: "概率论", code: "M3", name: "期末",
            time: "09:00-11:00 2026-11-26", room: "教3-102", seat: "5", note: ""
        )
        let undated = ExamRecord(
            id: "e5", course: "实验", code: "L1", name: "考核",
            time: "时间待定", room: "", seat: "", note: ""
        )

        precondition(morning.startMinutes == 9 * 60)
        precondition(morning.endMinutes == 11 * 60)
        precondition(afternoon.startMinutes == 14 * 60 + 30)
        precondition(afternoon.endMinutes == 16 * 60 + 30)
        precondition(startOnly.startMinutes == 19 * 60)
        precondition(startOnly.endMinutes == nil)
        precondition(reversedOrder.dateKey == "2026-11-26")
        precondition(reversedOrder.startMinutes == 9 * 60)
        precondition(reversedOrder.endMinutes == 11 * 60)

        let beforeEnd = makeDate(2026, 11, 25, 10, 59)
        let atEnd = makeDate(2026, 11, 25, 11, 0)
        let evening = makeDate(2026, 11, 25, 20, 42)
        let nextDayStart = makeDate(2026, 11, 26, 0, 0)

        precondition(!morning.isEnded(at: beforeEnd))
        precondition(morning.isEnded(at: atEnd))
        precondition(!afternoon.isEnded(at: atEnd))
        precondition(afternoon.isEnded(at: evening))
        // Start-only exam stays visible until end of exam day.
        precondition(!startOnly.isEnded(at: evening))
        precondition(startOnly.isEnded(at: nextDayStart))
        precondition(!undated.isEnded(at: nextDayStart))

        // WidgetSnapshot resolution & multi-day timeline transitions
        let exam1 = WidgetSnapshot.Exam(
            title: morning.course, date: morning.startDate(), days: 1,
            end: morning.endDate(), startTime: "09:00", room: morning.room, seat: morning.seat
        )
        let exam2 = WidgetSnapshot.Exam(
            title: reversedOrder.course, date: reversedOrder.startDate(), days: 2,
            end: reversedOrder.endDate(), startTime: "09:00", room: reversedOrder.room, seat: reversedOrder.seat
        )
        let baseNow = makeDate(2026, 11, 24, 20, 0)
        let snapshot = WidgetSnapshot(
            generatedAt: baseNow, week: 13, weekday: 2, courses: [],
            balance: nil, balanceUpdatedAt: nil, roomName: nil, upcomingBreak: nil,
            nextExam: exam1, upcomingExams: [exam1, exam2], loggedIn: true
        )

        let timelineDates = snapshot.examTimelineDates(after: baseNow, days: 7)
        precondition(timelineDates.contains(makeDate(2026, 11, 25, 0, 0)))
        precondition(timelineDates.contains(makeDate(2026, 11, 25, 11, 0)))
        precondition(timelineDates.contains(makeDate(2026, 11, 26, 11, 0)))

        let onMorning = snapshot.resolved(at: makeDate(2026, 11, 25, 8, 0))
        precondition(onMorning.nextExam?.title == "高等数学")
        precondition(onMorning.nextExam?.days == 0)
        precondition(onMorning.upcomingExams?.count == 2)
        precondition(onMorning.upcomingExams?[1].days == 1)

        let afterMorning = snapshot.resolved(at: atEnd)
        precondition(afterMorning.nextExam?.title == "概率论")
        precondition(afterMorning.nextExam?.days == 1)
        precondition(afterMorning.upcomingExams?.count == 1)

        let afterAll = snapshot.resolved(at: makeDate(2026, 11, 26, 11, 0))
        precondition(afterAll.nextExam == nil)
        precondition(afterAll.upcomingExams?.isEmpty == true)

        print("Passed ExamDisplayTests")
    }
}
