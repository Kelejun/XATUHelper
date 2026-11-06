import Foundation

@main
struct WatchSnapshotTests {
    static func main() throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            assertions += 1
        }
        func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
        let greetingCalendar = WatchSnapshot.campusCalendar
        for (time, expected) in [("04:59", "晚安。"), ("05:00", "早，"), ("11:29", "早，"),
                                 ("11:30", "吃饭没？"), ("13:29", "吃饭没？"), ("13:30", "下午好，"),
                                 ("17:59", "下午好，"), ("18:00", "晚上好，"), ("22:29", "晚上好，"),
                                 ("22:30", "晚安。"), ("23:59", "晚安。"), ("00:00", "晚安。")] {
            check(CampusGreeting.text(at: date("2026-11-04T\(time):00+08:00"), calendar: greetingCalendar) == expected,
                  "Shared greeting boundary and punctuation at \(time)")
        }
        let now = date("2026-11-04T09:00:00+08:00")
        func lesson(_ id: String, _ day: String, _ start: String, _ end: String) -> WatchSnapshot.Lesson {
            .init(id: id, name: id, room: "教1-305", fullRoom: "教1-305(未央)", teacher: "老师", periods: "第1-2节",
                  start: date("\(day)T\(start):00+08:00"), end: date("\(day)T\(end):00+08:00"))
        }
        let current = lesson("physics", "2026-11-04", "08:20", "10:00")
        let next = lesson("math", "2026-11-04", "10:20", "12:00")
        let tomorrow = lesson("english", "2026-11-05", "08:20", "10:00")
        let nextWeek = lesson("next-week", "2026-11-09", "08:20", "10:00")
        var snapshot = WatchSnapshot(generatedAt: now, accountID: "A", loggedIn: true,
            semester: "第一学期", weekOneMonday: WatchSnapshot.parseDay("2026-09-07")!,
            timetableUpdatedAt: now, lessons: [nextWeek, next, current, tomorrow], exams: [], holidays: [])
        check(snapshot.week(at: now) == 9, "Teaching week is calculated from synchronized semester start")
        check(snapshot.week(at: date("2026-11-09T00:00:00+08:00")) == 10, "Week advances on Monday")
        check(snapshot.week(at: date("2026-09-06T23:59:00+08:00")) == 0, "Before semester is not week one")
        check(snapshot.lessons(on: now).map(\.id) == ["physics", "math"], "Today's lessons sort chronologically")
        check(snapshot.currentLesson(at: current.start)?.id == "physics", "Start is inclusive")
        check(snapshot.currentLesson(at: current.end) == nil, "End is exclusive")
        check(snapshot.currentLesson(at: now)?.id == "physics", "Current lesson works offline")
        check(snapshot.nextLesson(at: now)?.id == "math", "Next course during current course")
        check(snapshot.nextLesson(at: next.end)?.id == "english", "After school shows tomorrow")
        check(snapshot.lessons(on: date("2026-11-05T00:00:00+08:00")).count == 1, "Midnight advances the local day")
        check(snapshot.nextLesson(at: tomorrow.end)?.id == "next-week", "Search spans multiple offline days")
        check(snapshot.nextLesson(at: nextWeek.end) == nil, "Semester end has no invented lessons")
        check(WatchSnapshot.clock(current.start) == "08:20", "Campus time does not depend on system timezone")
        check(WatchSnapshot.dayLabel(tomorrow.start, relativeTo: now) == "明天", "Tomorrow label")
        check(WatchSnapshot.parseDay("2026-02-30") == nil, "Invalid calendar dates rejected")
        let exam = WatchSnapshot.Exam(id: "exam", name: "考试", start: date("2026-11-04T14:00:00+08:00"),
            end: date("2026-11-04T16:00:00+08:00"), time: "14:00–16:00", room: "教3", seat: "1", note: "")
        snapshot.exams = [exam]
        check(snapshot.todayExam(at: now)?.id == "exam", "Today's exam appears above course")
        check(snapshot.todayExam(at: exam.end) == nil, "Finished exam hides")
        check(snapshot.nearExam(at: date("2026-10-28T23:59:00+08:00")) != nil, "Seven calendar days is included")
        check(snapshot.nearExam(at: date("2026-10-27T23:59:00+08:00")) == nil, "Eight days stays off home")
        snapshot.holidays = [
            .init(id: "break", title: "放寒假", date: WatchSnapshot.parseDay("2027-01-16")!),
            .init(id: "school", title: "第二学期开学", date: WatchSnapshot.parseDay("2027-03-01")!)
        ]
        check(snapshot.nextHoliday(at: now)?.id == "break", "Next vacation")
        check(snapshot.nextHoliday(at: date("2027-01-16T22:00:00+08:00"))?.id == "break", "Vacation day remains visible all day")
        check(snapshot.nextHoliday(at: date("2027-01-17T00:00:00+08:00"))?.id == "school", "During vacation counts to school")
        let transitions = snapshot.timelineDates(after: now)
        check(transitions.contains(current.end), "Complication switches at end")
        check(transitions.contains(next.start), "Complication switches at next start")
        check(transitions.contains(WatchSnapshot.parseDay("2026-11-05")!), "Complication changes at midnight")
        check(transitions == transitions.sorted() && Set(transitions).count == transitions.count, "Timeline sorted and unique")
        check(!transitions.contains(now), "Timeline only includes future changes")
        snapshot.lessons[0].colorIndex = 2
        let encoded = try PropertyListEncoder().encode(snapshot)
        let decoded = try PropertyListDecoder().decode(WatchSnapshot.self, from: encoded)
        check(decoded == snapshot, "Snapshot round trip")
        check(decoded.lessons[0].colorIndex == 2, "Phone course color survives synchronization")
        var oldPayload = try PropertyListSerialization.propertyList(from: encoded, format: nil) as! [String: Any]
        oldPayload["lessons"] = (oldPayload["lessons"] as! [[String: Any]]).map { lesson in
            var value = lesson
            value.removeValue(forKey: "colorIndex")
            return value
        }
        let oldData = try PropertyListSerialization.data(fromPropertyList: oldPayload, format: .binary, options: 0)
        let oldSnapshot = try PropertyListDecoder().decode(WatchSnapshot.self, from: oldData)
        check(oldSnapshot.lessons.allSatisfy { $0.colorIndex == nil }, "Existing snapshots remain readable without color metadata")
        var cache = WatchCache()
        check(cache.receive(snapshot), "First snapshot accepted")
        var logout = WatchSnapshot.empty
        logout.generatedAt = now.addingTimeInterval(1)
        check(cache.receive(WatchSyncDescriptor(logout)), "Logout descriptor accepted")
        check(cache.snapshot == nil, "Logout clears local account content immediately")
        check(!cache.receive(snapshot), "Late pre-logout file rejected")
        var switched = snapshot
        switched.generatedAt = now.addingTimeInterval(2)
        switched.accountID = "B"
        check(cache.receive(WatchSyncDescriptor(switched)), "Account B descriptor accepted")
        check(cache.snapshot == nil, "Account switch never shows A's content")
        check(cache.receive(switched), "Matching file accepted")
        var newest = switched
        newest.generatedAt = now.addingTimeInterval(3)
        check(cache.receive(WatchSyncDescriptor(newest)), "Same-account pending descriptor accepted")
        check(cache.snapshot?.accountID == "B", "Same account retains offline snapshot while file arrives")
        check(!cache.receive(switched), "Outdated file cannot overwrite newer descriptor")
        check(cache.receive(newest), "Newest file fills pending snapshot")
        newest.schema = 999
        check(!cache.receive(newest), "Unsupported schema rejected")
        snapshot.loggedIn = false
        check(snapshot.lessons(on: now).isEmpty && snapshot.currentLesson(at: now) == nil,
              "Logged-out snapshots never expose course data")
        check(snapshot.upcomingExams(at: now).isEmpty && snapshot.nextHoliday(at: now) == nil,
              "Logged-out snapshots never expose secondary data")
        print("Watch snapshot: \(assertions) assertions passed")
    }
}
