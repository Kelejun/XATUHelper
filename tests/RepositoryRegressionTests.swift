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
        let noon = date("2026-11-10 12:00")
        snapshot.nextExam = .init(title: "旧快照考试", date: tuesday, days: 1)
        check(snapshot.resolved(at: noon).nextExam?.days == 0, "legacy exam stays visible on exam day")
        check(snapshot.resolved(at: wednesday).nextExam == nil, "expired legacy exam removed")
        snapshot.upcomingExams = [
            .init(title: "数学", date: date("2026-11-10 10:00"), days: 1, end: noon),
            .init(title: "英语", date: date("2026-11-10 14:00"), days: 1, end: date("2026-11-10 16:00"))
        ]
        check(snapshot.resolved(at: monday).nextExam?.days == 1, "exam counts campus calendar days")
        check(snapshot.resolved(at: tuesday).nextExam?.days == 0, "exam countdown rolls over at midnight")
        check(snapshot.resolved(at: noon).nextExam?.title == "英语", "next exam takes over at previous exam end")
        check(snapshot.resolved(at: noon).upcomingExams?.map(\.title) == ["英语"], "widget list drops the finished exam")
        check(snapshot.resolved(at: wednesday).nextExam == nil, "completed exam schedule is empty")
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

        // 多培养项目（本科 / 微专业）页面适配回归测试
        let normalShellHTML = """
        <input id="semesterBar15145952571Semester" />
        <script>
        bg.form.addInput(form,"ids","10001");
        bg.form.addInput(form,"ids","20002");
        semesterCalendar({value:"102"});
        </script>
        """
        let majorSelectedWrapper = """
        <div class="navmenu">
        <ul>
            <li><a class="selected" href="javascript:void(0);">本科</a></li>
            <li><a onclick="return bg.Go(this,null)" href="/eams/courseTableForStd!index.action?projectId=82">微专业</a></li>
        </ul>
        </div>
        <div id="div1" class="ajax_container"></div>
        <script>bg.Go('/eams/courseTableForStd!innerIndex.action?projectId=1','div1');</script>
        """
        let minorSelectedWrapper = """
        <div class="navmenu">
        <ul>
            <li><a onclick="return bg.Go(this,null)" href="/eams/courseTableForStd!index.action?projectId=1">本科</a></li>
            <li><a class="selected" href="javascript:void(0);">微专业</a></li>
        </ul>
        </div>
        <div id="div1" class="ajax_container"></div>
        <script>bg.Go('/eams/courseTableForStd!innerIndex.action?projectId=82','div1');</script>
        """

        check(EamsService.parseMultiProjectWrapper(normalShellHTML, modulePath: "/eams/courseTableForStd.action") == nil,
              "single-project shell is not treated as multi-project wrapper")
        let parsedMajorWrapper = EamsService.parseMultiProjectWrapper(majorSelectedWrapper, modulePath: "/eams/courseTableForStd.action")
        check(parsedMajorWrapper?.switchHref == nil && parsedMajorWrapper?.innerPath == "/eams/courseTableForStd!innerIndex.action?projectId=1" && parsedMajorWrapper?.projectID == "1",
              "major-selected wrapper resolves directly to innerIndex")
        let parsedMinorWrapper = EamsService.parseMultiProjectWrapper(minorSelectedWrapper, modulePath: "/eams/courseTableForStd.action")
        check(parsedMinorWrapper?.switchHref == "/eams/courseTableForStd!index.action?projectId=1" && parsedMinorWrapper?.projectID == "1",
              "minor-selected wrapper requests switch back to 本科")

        // 1. 本科已选中时的多项目课表外壳加载
        var sessionProject = "1"
        var requestedPaths: [String] = []
        FixtureProtocol.handler = { request in
            let url = request.url!
            let pathWithQuery = url.query.map { "\(url.path)?\($0)" } ?? url.path
            requestedPaths.append(pathWithQuery)
            if url.path == "/eams/courseTableForStd.action" {
                return (200, sessionProject == "1" ? majorSelectedWrapper : minorSelectedWrapper)
            }
            if url.path == "/eams/courseTableForStd!index.action" {
                if url.query?.contains("projectId=1") == true { sessionProject = "1" }
                return (200, majorSelectedWrapper)
            }
            if url.path == "/eams/courseTableForStd!innerIndex.action" {
                return (200, sessionProject == "1" ? normalShellHTML : "<p>empty minor</p>")
            }
            if url.path == "/eams/dataQuery.action" {
                return (200, sessionProject)
            }
            return (404, "")
        }
        let majorShell = try await EamsService().loadShell()
        check(majorShell.studentTableID == "10001" && majorShell.classTableID == "20002"
              && majorShell.currentSemesterID == "102" && majorShell.projectID == "1",
              "loadShell resolves multi-project wrapper when 本科 is selected")
        check(requestedPaths.contains("/eams/courseTableForStd!innerIndex.action?projectId=1"),
              "loadShell fetches innerIndex when 本科 is selected")

        // 2. 服务端会话停留在微专业时，必须先调 !index.action?projectId=1 再进内页
        sessionProject = "82"
        requestedPaths = []
        let switchedShell = try await EamsService().loadShell()
        check(switchedShell.studentTableID == "10001" && switchedShell.projectID == "1",
              "loadShell switches session from 微专业 back to 本科")
        check(requestedPaths.firstIndex(of: "/eams/courseTableForStd!index.action?projectId=1") != nil,
              "loadShell calls !index.action?projectId=1 before innerIndex")
        if let switchIndex = requestedPaths.firstIndex(of: "/eams/courseTableForStd!index.action?projectId=1"),
           let innerIndex = requestedPaths.firstIndex(of: "/eams/courseTableForStd!innerIndex.action?projectId=1") {
            check(switchIndex < innerIndex, "project switch precedes innerIndex fetch")
        } else {
            check(false, "missing switch or innerIndex request")
        }

        // 3. 考试 / 成绩 / 培养计划 / 教学计划的多项目外壳均能透传参数并进入内页
        requestedPaths = []
        FixtureProtocol.handler = { request in
            let url = request.url!
            let pathWithQuery = url.query.map { "\(url.path)?\($0)" } ?? url.path
            requestedPaths.append(pathWithQuery)
            switch url.path {
            case "/eams/stdExamTable.action":
                return (200, """
                <div class="navmenu"><ul>
                <li><a class="selected" href="javascript:void(0);">本科</a></li>
                <li><a href="/eams/stdExamTable!index.action?projectId=82">微专业</a></li>
                </ul></div><script>bg.Go('/eams/stdExamTable!innerIndex.action?projectId=1','d');</script>
                """)
            case "/eams/stdExamTable!innerIndex.action":
                return (200, #"<select name="examBatch.id"><option value="0">全部</option><option value="9">期末</option></select>"#)
            case "/eams/stdExamTable!examTable.action":
                return (200, "<tr><th>课程名称</th><th>考试时间</th><th>考场</th></tr><tr><td>编译原理</td><td>2027-01-12 09:00-11:00</td><td>教1-101</td></tr>")
            case "/eams/teach/grade/course/person.action":
                return (200, """
                <div class="navmenu"><ul>
                <li><a class="selected" href="javascript:void(0);">本科</a></li>
                <li><a href="/eams/teach/grade/course/person!index.action?projectId=82">微专业</a></li>
                </ul></div><script>bg.Go('/eams/teach/grade/course/person!innerIndex.action?projectId=1','d');</script>
                """)
            case "/eams/teach/grade/course/person!innerIndex.action":
                return (200, #"semesterCalendar({value:"102"})"#)
            case "/eams/teach/grade/course/person!search.action":
                return (200, header + math)
            case "/eams/myPlanCompl.action":
                return (200, """
                <div class="navmenu"><ul>
                <li><a class="selected" href="javascript:void(0);">本科</a></li>
                <li><a href="/eams/myPlanCompl!index.action?projectId=82">微专业</a></li>
                </ul></div><div class="ajax_container"></div>
                """)
            case "/eams/myPlanCompl!innerIndex.action":
                return (200, """
                姓名: 测试 专业/专业方向: 软件工程 要求学分/实修学分: 179 / 20
                <table><tr class="darkColumn"><td colspan="3">一 通识教育</td><td>40</td><td>20</td></tr></table>
                """)
            case "/eams/myPlan.action":
                return (200, """
                <div class="navmenu"><ul>
                <li><a class="selected" href="javascript:void(0);">本科</a></li>
                <li><a href="/eams/myPlan!index.action?projectId=82">微专业</a></li>
                </ul></div><script>bg.Go('/eams/myPlan!innerIndex.action?projectId=1','d');</script>
                """)
            case "/eams/myPlan!innerIndex.action":
                return (200, """
                <table class="planInfoTable"><tr>
                <td>C001</td><td class="course">1 编译原理</td><td>3.0</td><td>48</td>
                <td></td><td></td><td></td><td></td><td></td><td>5</td><td></td><td>是</td>
                </tr></table>
                """)
            default:
                return (404, "")
            }
        }
        let exams = try await EamsService().fetchExams(semesterID: "102")
        check(exams.count == 1 && exams[0].course == "编译原理", "fetchExams resolves multi-project wrapper")
        check(requestedPaths.contains("/eams/stdExamTable!innerIndex.action?projectId=1&semester.id=102"),
              "fetchExams preserves semester.id when loading innerIndex")
        let grades = try await EamsService().fetchGrades(semesterID: "102")
        check(grades.count == 1 && grades[0].course == "数学", "fetchGrades resolves multi-project wrapper")
        check(requestedPaths.contains("/eams/teach/grade/course/person!innerIndex.action?projectId=1&semester.id=102"),
              "fetchGrades preserves semester.id when loading innerIndex")
        let plan = try await EamsService().fetchPlan()
        check(plan.sections.count == 1 && plan.totalRequired == 179, "fetchPlan resolves multi-project wrapper without inline script URL")
        let catalog = try await EamsService().fetchPlanCatalog()
        check(catalog.count == 1 && catalog[0].name == "编译原理", "fetchPlanCatalog resolves multi-project wrapper")
        FixtureProtocol.handler = nil
        print("Passed \(count) repository regression checks")
    }
}

private final class FixtureProtocol: URLProtocol {
    static var status = 200
    static var html = ""
    static var handler: ((URLRequest) -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (statusCode, body) = Self.handler?(request) ?? (Self.status, Self.html)
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
