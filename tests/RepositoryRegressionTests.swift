import Foundation

// Standalone parser tests: no campus requests are made.
enum AppError: Error { case badURL, parseFailed, sessionExpired, network(String) }
enum Net {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return URLSession(configuration: configuration)
    }()
    static func describe(_ error: Error) -> String { error.localizedDescription }
    static var redirectTrail: String { "" }
    static func formBody(_ pairs: [(String, String)]) -> String { "" }
}

@main
struct RepositoryRegressionTests {
    static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ name: String) {
            precondition(value, name)
            count += 1
        }
        for text in ["2027-01-12", "2027/1/12", "2027.1.12", "2027年1月12日"] {
            let exam = ExamRecord(id: "e", course: "数学", code: "M", name: "期末",
                                  time: text + " 09:00-11:00", room: "", seat: "", note: "")
            check(exam.dateKey == "2027-01-12", "normalized exam date")
            check(exam.timeWithoutDate == "09:00-11:00", "original date range removed")
        }
        let header = "<tr><th>课程名称</th><th>课程代码</th><th>学分</th><th>总评成绩</th><th>绩点</th></tr>"
        let math = "<tr><td>数学</td><td>M01</td><td>3</td><td>80</td><td>3</td></tr>"
        let english = "<tr><td>英语</td><td>E01</td><td>2</td><td>90</td><td>4</td></tr>"
        let first = EamsService.parseGrades(header + math + english)
        let reordered = EamsService.parseGrades(header + english + math)
        check(first.count == 2, "grade fixture recognized")
        check(Set(first.map(\.id)) == Set(reordered.map(\.id)), "stable row identity")
        check(try GradeRecord.refreshFingerprint(first) == GradeRecord.refreshFingerprint(reordered), "reorder is not a grade change")
        let changed = EamsService.parseGrades(header + math.replacingOccurrences(of: ">80<", with: ">85<") + english)
        check(first[0].id == changed[0].id, "score update preserves course identity")
        check(try GradeRecord.refreshFingerprint(first) != GradeRecord.refreshFingerprint(changed), "score update detected")
        var legacy = first
        legacy[0].id = "old-row-id"
        check(try GradeRecord.refreshFingerprint(first) == GradeRecord.refreshFingerprint(legacy), "legacy IDs do not trigger refresh")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        func date(_ text: String) -> Date { formatter.date(from: text)! }
        let monday = date("2026-11-09 10:00")
        let tuesday = date("2026-11-10 00:00")
        let wednesday = date("2026-11-11 00:00")
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = monday
        snapshot.loggedIn = true
        snapshot.week = 10
        snapshot.weekday = 1
        snapshot.datedCourses = [
            .init(id: "mon", name: "数学", room: "", startMinutes: 500, endMinutes: 600, day: monday),
            .init(id: "tue", name: "英语", room: "", startMinutes: 600, endMinutes: 700, day: tuesday)
        ]
        snapshot.upcomingBreak = .init(title: "放假", date: wednesday, days: 2)
        let next = snapshot.resolved(at: tuesday)
        check(next.courses.map(\.id) == ["tue"], "midnight selects dated courses")
        check(next.tomorrowCourses?.isEmpty == true, "empty following day")
        check(next.weekday == 2 && next.week == 10, "weekday advances")
        check(next.upcomingBreak?.days == 1, "countdown advances without app launch")
        check(snapshot.resolved(at: date("2026-11-16 00:00")).week == 11, "week rollover")
        check(snapshot.resolved(at: date("2026-11-30 00:00")).courses.isEmpty, "expired horizon never repeats old courses")
        check(snapshot.resolved(at: date("2026-11-12 00:00")).upcomingBreak == nil, "expired holiday removed")
        snapshot.datedCourses = nil
        snapshot.courses = [.init(id: "old", name: "旧课程", room: "", startMinutes: 500, endMinutes: 600)]
        check(snapshot.resolved(at: wednesday).courses.isEmpty, "legacy snapshot does not repeat after two days")
        let payload = GradeStore.Payload(grades: first, fetchedAt: monday, account: "student", context: "semester")
        let decoded = try JSONDecoder().decode(GradeStore.Payload.self, from: JSONEncoder().encode(payload))
        check(decoded.account == "student" && decoded.context == "semester", "cache ownership persists")
        let empty = WidgetSnapshot.empty.resolved(at: monday)
        check(!empty.loggedIn && empty.courses.isEmpty, "logged-out widget stays empty")
        FixtureProtocol.status = 200
        FixtureProtocol.html = "<script>var unitCount = 12;</script>"
        let emptyTable = try await EamsService().fetchTable(kind: .student, ids: "1", semesterID: "1")
        check(emptyTable.occurrences.isEmpty && emptyTable.unitCount == 12, "valid empty semester accepted")
        for (status, html) in [(500, "var unitCount = 12;"), (200, "maintenance"), (200, "loginExt.action")] {
            FixtureProtocol.status = status
            FixtureProtocol.html = html
            do {
                _ = try await EamsService().fetchTable(kind: .student, ids: "1", semesterID: "1")
                check(false, "invalid table response must fail")
            } catch {
                check(true, "invalid table response rejected")
            }
        }
        print("Passed \(count) repository regression checks")
    }
}

private final class FixtureProtocol: URLProtocol {
    static var status = 200
    static var html = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.html.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
