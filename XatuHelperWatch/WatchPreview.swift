#if DEBUG
import Foundation

/// Explicit simulator-only launch fixtures; never stored or sent to the phone.
enum WatchPreview {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--watch-preview") }
    static var now: Date {
        let afterClass = ProcessInfo.processInfo.arguments.contains("--watch-preview-after-class")
        return WatchSnapshot.campusCalendar.date(bySettingHour: afterClass ? 19 : 9, minute: 0, second: 0, of: Date())!
    }
    static var snapshot: WatchSnapshot {
        let calendar = WatchSnapshot.campusCalendar
        let day = calendar.startOfDay(for: now)
        func at(_ minutes: Int, offset: Int = 0) -> Date {
            calendar.date(byAdding: .minute, value: minutes + offset * 1440, to: day)!
        }
        let examToday = ProcessInfo.processInfo.arguments.contains("--watch-preview-exam")
        var value = WatchSnapshot(generatedAt: now, accountID: "preview", loggedIn: true, semester: "2026–2027 第一学期",
            weekOneMonday: WatchSnapshot.parseDay("2026-09-07")!, timetableUpdatedAt: now, examsUpdatedAt: now,
            lessons: [
                .init(id: "1", name: "大学物理", room: "教1－305", fullRoom: "教1－305（未央校区）", teacher: "张老师", periods: "第1–2节", start: at(500), end: at(600)),
                .init(id: "2", name: "高等数学", room: "教2－201", fullRoom: "教2－201（未央校区）", teacher: "李老师", periods: "第3–4节", start: at(620), end: at(720), colorIndex: 2),
                .init(id: "3", name: "大学英语", room: "教3－402", fullRoom: "教3－402", teacher: "王老师", periods: "第5–6节", start: at(840), end: at(940), colorIndex: 1),
                .init(id: "4", name: "电路分析基础", room: "教2－301", fullRoom: "教2－301", teacher: "赵老师", periods: "第1–2节", start: at(500, offset: 1), end: at(600, offset: 1))
            ], exams: [.init(id: "exam", name: "大学英语", start: at(840, offset: examToday ? 0 : 1), end: at(960, offset: examToday ? 0 : 1), time: "14:00–16:00", room: "教3－402", seat: "28", note: "请携带学生证")],
            balance: "48.62", balanceUpdatedAt: now.addingTimeInterval(-3600), roomName: "未央校区 · 8号楼 305",
            holidays: [.init(id: "winter", title: "放寒假", date: WatchSnapshot.parseDay("2027-01-16")!)])
        if ProcessInfo.processInfo.arguments.contains("--watch-preview-long") {
            value.lessons[0].name = "思想道德与法治课程实践教学"
        }
        if ProcessInfo.processInfo.arguments.contains("--watch-preview-empty-exams") {
            value.exams = []
        }
        return value
    }
}
#endif
