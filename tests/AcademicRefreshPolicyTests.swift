import Foundation

// Run with swiftc XatuHelper/Services/CachePolicy.swift XatuHelper/Models/Grade.swift tests/AcademicRefreshPolicyTests.swift -o /tmp/academic-refresh-tests
@main
struct AcademicRefreshPolicyTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        func date(_ text: String) -> Date { formatter.date(from: text)! }
        var count = 0
        func check(_ result: Bool, _ name: String) {
            precondition(result, name)
            count += 1
        }
        let terms: [AcademicRefreshPolicy.Term] = [
            .init(start: date("2026-08-31 00:00"), end: date("2027-01-17 00:00")),
            .init(start: date("2027-02-22 00:00"), end: date("2027-07-11 00:00")),
            .init(start: date("2027-08-30 00:00"), end: nil)
        ]
        func grades(_ day: String) -> Bool {
            AcademicRefreshPolicy.gradesEnabled(terms: terms, now: date(day), calendar: calendar)
        }
        func vacation(_ day: String) -> Bool {
            AcademicRefreshPolicy.isVacation(terms: terms, now: date(day), calendar: calendar)
        }
        check(!grades("2026-11-15 23:59"), "week 11")
        check(grades("2026-11-16 00:00"), "week 12 boundary")
        check(grades("2027-01-30 12:00"), "winter grades")
        check(grades("2027-02-21 23:59"), "last winter day")
        check(!grades("2027-02-22 00:00"), "new spring term stops daily grades")
        check(!grades("2027-05-09 23:59"), "spring week 11")
        check(grades("2027-05-10 00:00"), "spring week 12")
        check(grades("2027-08-29 23:59"), "last summer day")
        check(!grades("2027-08-30 00:00"), "new autumn stops daily grades")
        check(!vacation("2027-01-17 23:59"), "last teaching day included")
        check(vacation("2027-01-18 00:00"), "winter starts")
        check(!vacation("2027-02-22 00:00"), "winter ends")
        check(vacation("2027-07-12 00:00"), "summer starts")
        check(!vacation("2027-08-30 00:00"), "summer ends")
        check(AcademicRefreshPolicy.needsDailyRefresh(date("2026-11-12 23:59"), now: date("2026-11-13 00:00"), calendar: calendar), "midnight refresh")
        check(!AcademicRefreshPolicy.needsDailyRefresh(date("2026-11-13 00:01"), now: date("2026-11-13 23:59"), calendar: calendar), "one success per local day")
        check(AcademicRefreshPolicy.needsDailyRefresh(nil, now: Date(), calendar: calendar), "missing cache")
        let starts = terms.prefix(2).map(\.start)
        func decision(_ day: String, pending: Int? = nil, dates: [Date]? = nil) -> AcademicRefreshPolicy.CalendarDecision {
            AcademicRefreshPolicy.calendarDecision(starts: dates ?? starts, pendingYear: pending, now: date(day), calendar: calendar)
        }
        check(decision("2027-07-30 23:59") == .wait, "before summer last 30 days")
        check(decision("2027-07-31 00:00") == .update(year: 2027), "summer last 30 days begins")
        check(decision("2027-09-15 12:00", pending: 2027) == .update(year: 2027), "retry until next calendar even after school starts")
        let next = [date("2027-08-30 00:00"), date("2028-02-21 00:00")]
        check(decision("2027-08-01 12:00", pending: 2027, dates: next) == .wait, "new academic calendar stops attempts")
        check(decision("2028-07-28 23:59", dates: next) == .wait, "leap year before next window")
        check(decision("2028-07-29 00:00", dates: []) == .bootstrap, "no calendar bootstrap")
        check(decision("2027-08-01 00:00", dates: [starts[0]]) == .bootstrap, "incomplete OCR can recover")
        check(CacheKind.timetable.lifetime == 7 * 86400 && CacheKind.plan.lifetime == 8 * 86400 && CacheKind.grades.lifetime == 9 * 86400 && CacheKind.exams.lifetime == 10 * 86400, "legacy lifetimes")
        let first = GradeRecord(id: "a", course: "数学", code: "001", credit: "3", score: "80", gpa: "3", components: [])
        let second = GradeRecord(id: "b", course: "英语", code: "002", credit: "2", score: "90", gpa: "4", components: [])
        func fingerprint(_ records: [GradeRecord]) -> Data { try! GradeRecord.refreshFingerprint(records) }
        check(fingerprint([first, second]) == fingerprint([second, first]), "row reordering does not trigger plan refresh")
        check(fingerprint([first]) == fingerprint([first]), "identical successful grades do not trigger plan refresh")
        var changed = first
        changed.score = "85"
        check(fingerprint([first]) != fingerprint([changed]), "changed score triggers plan refresh")
        check(fingerprint([first]) != fingerprint([first, second]), "new course triggers plan refresh")
        check(fingerprint([first]) != fingerprint([]), "removed grades change snapshot")
        let midweek = [AcademicRefreshPolicy.Term(start: date("2026-09-02 00:00"), end: nil)]
        check(AcademicRefreshPolicy.gradesEnabled(terms: midweek, now: date("2026-11-16 00:00"), calendar: calendar), "week twelve follows Monday even for midweek start")
        check(decision("2028-07-29 00:00", dates: next) == .update(year: 2028), "leap year window boundary")
        print("Passed \(count) refresh policy checks")
    }
}
