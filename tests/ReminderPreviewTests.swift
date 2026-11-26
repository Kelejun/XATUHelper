import Foundation

@main
struct ReminderPreviewTests {
    static func main() {
        let day = WatchSnapshot.parseDay("2027-09-08")!
        func at(_ minutes: Int) -> Date { day.addingTimeInterval(Double(minutes) * 60) }
        func lesson(_ name: String, _ room: String, _ start: Int, _ end: Int) -> WatchSnapshot.Lesson {
            .init(id: name, name: name, room: room, fullRoom: room, teacher: "", periods: "", start: at(start), end: at(end))
        }
        var snapshot = WatchSnapshot.empty
        snapshot.loggedIn = true
        let a = lesson("理论力学", "一教201", 480, 525)
        let b = lesson("材料力学", "二教305", 535, 580)
        snapshot.lessons = [a, b]
        func preview(_ records: [ExamRecord] = [], seed: UInt64 = 0) -> ReminderPreviewData {
            ReminderPreviewData(snapshot: snapshot, exams: records, fallbackCourses: [], sampleIndex: seed, now: at(500))
        }
        let result = preview()
        precondition(result.before == b && result.during?.lesson == a && result.preparation?.lesson == a)
        precondition(result.preparationSlot(leadMinutes: 45)?.begins == at(435))
        precondition(result.between?.lesson == b && result.between?.previousRoom == a.room && result.between?.begins == a.end)
        precondition(result.exam?.name == a.name && result.exam?.simulated == true)
        precondition(result.examActivitySlot()?.exam.name == a.name)
        precondition(result.examActivitySlot()?.begins == a.start.addingTimeInterval(-3600))
        precondition(preview(seed: 1).exam?.name == b.name)
        let record = ExamRecord(id: "e", course: "英语", code: "", name: "", time: "2027-09-08 14：30–16：30",
                                room: "三教109", seat: "16", note: "")
        let examPreview = preview([record])
        let exam = examPreview.exam
        precondition(exam?.name == record.course && exam?.startMinutes == 870 && exam?.simulated == false)
        precondition(exam?.detail.contains("三教109") == true && exam?.detail.contains("座位 16") == true)
        precondition(exam?.leadDetail == "14:30 开考 · " + record.notificationDetail)
        precondition(examPreview.examActivitySlot()?.exam.name == "英语")
        precondition(examPreview.examActivitySlot()?.exam.displayRoom == "三教109")
        precondition(examPreview.examActivitySlot()?.exam.displaySeat == "16")
        precondition(examPreview.examActivitySlot(leadMinutes: 45)?.begins == at(825))
        snapshot.lessons = [lesson("上午", "A", 660, 712), lesson("下午", "B", 732, 777)]
        precondition(preview().between == nil)
        snapshot.lessons = []
        precondition(preview().before == nil && preview().exam == nil && preview().examActivitySlot() == nil)
        print("Passed reminder preview checks")
    }
}
