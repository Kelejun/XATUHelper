import Foundation

/// 课表类型：学生课表 / 班级课表
enum TableKind: String, Codable, CaseIterable, Identifiable {
    case student = "std"
    case classGroup = "class"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .student: return "学生课表"
        case .classGroup: return "班级课表"
        }
    }
}

/// 树维 EAMS
struct EamsService {
    /// 最近一次学期列表接口的原始响应，设置页里可以复制出来排查
    static var lastSemesterRaw = ""
    /// 最近一次课表外壳页的原始 HTML
    static var lastShellRaw = ""
    /// 最近一次首页的原始 HTML（用来读"现在是第几周"）
    static var lastHomeRaw = ""
    /// 最后一次请求失败的原因（有的话）
    static var lastError = ""
    /// 最近一次课表接口的原始响应
    static var lastTableRaw = ""
    /// 最近一次考试页外壳（stdExamTable.action）的原始 HTML
    static var lastExamShellRaw = ""
    /// 最近一次考试表（stdExamTable!examTable.action）的原始 HTML
    static var lastExamRaw = ""
    /// 最近一次成绩页的原始 HTML
    static var lastGradeRaw = ""
    /// 成绩页外壳（带学期控件那一层）
    static var lastGradeShellRaw = ""

    /// URLSession 报「重定向太多」，基本都是 CAS 在登录页和业务页之间打转，
    /// 说明本校那个会话已经坏了，按登录态失效处理，让上层清 cookie 重登。
    static func isRedirectLoop(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.code == NSURLErrorHTTPTooManyRedirects
    }

    /// 设置页「复制诊断数据」导出的内容
    static var diagnosticDump: String {
        let shell = lastShellRaw.isEmpty ? "(空，外壳页没抓到)" : String(lastShellRaw.prefix(30000))
        let semesters = lastSemesterRaw.isEmpty ? "(空，学期接口没抓到)" : String(lastSemesterRaw.prefix(30000))
        return """
        ===== XATU Helper 诊断数据 =====
        时间: \(Date())
        最后一次错误: \(lastError.isEmpty ? "无" : lastError)

        ===== 课表外壳页 courseTableForStd.action =====
        \(shell)

        ===== 首页 homeExt!main.action =====
        \(lastHomeRaw.isEmpty ? "(空)" : String(lastHomeRaw.prefix(20000)))

        ===== 学期接口 dataQuery.action =====
        \(semesters)

        ===== 课表接口 courseTableForStd!courseTable.action =====
        \(lastTableRaw.isEmpty ? "(空)" : String(lastTableRaw.prefix(6000)))

        ===== 考试页 stdExamTable.action =====
        \(lastExamRaw.isEmpty ? "(空)" : String(lastExamRaw.prefix(20000)))

        ===== 成绩外壳 teach/grade/course/person.action =====
        \(lastGradeShellRaw.isEmpty ? "(空)" : String(lastGradeShellRaw.prefix(8000)))

        ===== 成绩表 person!search.action =====
        \(lastGradeRaw.isEmpty ? "(空)" : String(lastGradeRaw.prefix(20000)))
        """
    }

    private let base = "http://jwgl2018.xatu.edu.cn"

    struct Shell {
        var studentTableID: String
        var classTableID: String?
        var currentSemesterID: String
        var semesterTagID: String
        /// 培养方案/项目 ID，浏览器提交课表表单时会一起带上
        var projectID: String
    }

    /// 拉课表页外壳，取出学生记录 ID、班级 ID、当前学期 ID、学期控件的 tagId
    func loadShell() async throws -> Shell {
        guard let url = URL(string: base + "/eams/courseTableForStd.action") else {
            throw AppError.badURL
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Net.session.data(from: url)
        } catch {
            EamsService.lastError = "课表外壳页请求失败：\(Net.describe(error))\(Net.redirectTrail)"
            if EamsService.isRedirectLoop(error) { throw AppError.sessionExpired }
            throw AppError.network(Net.describe(error))
        }
        let host = response.url?.host ?? ""
        let html = String(data: data, encoding: .utf8) ?? ""
        EamsService.lastShellRaw = html
        EamsService.lastError = ""

        if host.contains("authserver") || html.contains("id=\"pwdEncryptSalt\"") {
            throw AppError.sessionExpired
        }
        // 树维自己的登录页（不是金智那张），说明会话已经没了
        if html.contains("loginExt.action") || html.contains("name=\"password\"") {
            EamsService.lastError = "课表外壳页回到了树维登录页"
            throw AppError.sessionExpired
        }

        // searchTable() 里两个分支：学生课表传学生记录 ID，班级课表传班级 ID，顺序固定
        let ids = html.regexGroups(#""ids"\s*,\s*"(\d+)""#).compactMap { $0.first }
        guard let studentID = ids.first else { throw AppError.parseFailed }
        let classID = ids.count > 1 ? ids[1] : nil

        guard let semester = html.firstMatch(#"semesterCalendar\(\{[^}]*value:"(\d+)"\}"#) else {
            throw AppError.parseFailed
        }
        let tagID = html.firstMatch(#"id="(semesterBar\d+Semester)""#) ?? "semesterCalendar_target"
        let project = await fetchProjectID()

        return Shell(
            studentTableID: studentID,
            classTableID: classID,
            currentSemesterID: semester,
            semesterTagID: tagID,
            projectID: project
        )
    }

    /// 培养方案/项目 ID，外壳页里是 jQuery.post 现取的，我们也照样取一次
    func fetchProjectID() async -> String {
        guard let url = URL(string: base + "/eams/dataQuery.action") else { return "" }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Net.formBody([("dataType", "projectId")]).utf8)
        guard let (data, _) = try? await Net.session.data(for: request),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// 学年学期列表。数据源是 dataQuery.action 的 semesterCalendar。
    func fetchSemesters(tagID: String, current: String) async -> [Semester] {
        guard let url = URL(string: base + "/eams/dataQuery.action") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Net.formBody([
            ("tagId", tagID),
            ("dataType", "semesterCalendar"),
            ("value", current),
            ("empty", "false")
        ]).utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Net.session.data(for: request)
        } catch {
            EamsService.lastSemesterRaw = "(请求失败：\(Net.describe(error)))"
            EamsService.lastError = "dataQuery 请求失败：\(Net.describe(error))"
            return []
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        EamsService.lastSemesterRaw = text
        EamsService.lastError = "dataQuery 状态 \(response.url?.path ?? "?") / \(text.count) 字节"

        guard !text.isEmpty, !text.contains("pwdEncryptSalt") else {
            EamsService.lastError += "（返回了登录页，会话可能过期）"
            return []
        }

        let fromJSON = EamsService.parseSemestersJSON(data)
        if !fromJSON.isEmpty { return fromJSON }

        let fromHTML = EamsService.parseSemestersHTML(text)
        if !fromHTML.isEmpty { return fromHTML }

        return current.isEmpty ? [] : [Semester(id: current, name: "当前学期")]
    }

    /// 拉指定学期、指定类型的课表
    func fetchTable(kind: TableKind, ids: String, semesterID: String,
                    projectID: String = "") async throws -> TimetableParser.Parsed {
        guard let url = URL(string: base + "/eams/courseTableForStd!courseTable.action") else {
            throw AppError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Net.formBody([
            ("ignoreHead", "1"),
            ("setting.kind", kind.rawValue),
            ("startWeek", ""),
            ("project.id", projectID),
            ("semester.id", semesterID),
            ("ids", ids)
        ]).utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Net.session.data(for: request)
        } catch {
            EamsService.lastError = "课表接口请求失败：\(Net.describe(error))"
            throw AppError.network(Net.describe(error))
        }
        let finalHost = response.url?.host ?? ""
        let table = String(data: data, encoding: .utf8) ?? ""
        EamsService.lastTableRaw = table

        if finalHost.contains("authserver") || table.contains("id=\"pwdEncryptSalt\"") {
            throw AppError.sessionExpired
        }
        // 历史学期可能真的没课，别把"空"当成"掉登录"
        let parsed = TimetableParser.parse(table)
        // 线上教室和占位课会被剔掉，所以不能用 occurrences 判断有没有拿到数据
        return parsed
    }

    /// 从教务首页读"现在是第几周"，作为周次校准的第一手依据
    func fetchOfficialWeek() async -> Int? {
        guard let url = URL(string: base + "/eams/homeExt!main.action") else { return nil }
        guard let (data, response) = try? await Net.session.data(from: url),
              let html = String(data: data, encoding: .utf8) else { return nil }
        if (response.url?.host ?? "").contains("authserver") { return nil }
        EamsService.lastHomeRaw = html

        let patterns = [
            #"<span>\s*([0-9]{1,2})\s*</span>\s*<i>\s*/\s*[0-9]{1,2}\s*</i>[\s\S]{0,80}?当前教学周"#,
            #"当前教学周[\s\S]{0,80}?<span>\s*([0-9]{1,2})\s*</span>"#,
            #"第\s*([0-9]{1,2})\s*周"#,
            #"currentWeek\s*[:=]\s*['"]?([0-9]{1,2})"#,
            #""week"\s*:\s*([0-9]{1,2})"#,
            #"教学周[^0-9]{0,10}([0-9]{1,2})"#
        ]
        for pattern in patterns {
            if let raw = html.firstMatch(pattern), let value = Int(raw), (1...30).contains(value) {
                return value
            }
        }
        return nil
    }

    /// 拉指定学期的考试安排。
    /// 这页是两层的：stdExamTable.action 只出外壳（批次下拉 + 学期表单 + 空的 contentDiv），
    /// 真正的表格由 bg.Go 再请求 stdExamTable!examTable.action?examBatch.id=0 填进去。
    func fetchExams(semesterID: String) async throws -> [ExamRecord] {
        let semesterQuery = semesterID.isEmpty
            ? []
            : [URLQueryItem(name: "semester.id", value: semesterID)]

        let shell = try await examText(
            path: "/eams/stdExamTable.action",
            query: semesterQuery,
            label: "考试页外壳"
        )
        EamsService.lastExamShellRaw = shell

        let batches = EamsService.parseExamBatches(shell)
        // 0 = 全部；整批取不到就逐个批次再试一遍
        var batchIDs = ["0"]
        batchIDs += batches.map(\.id).filter { $0 != "0" }

        var collected: [ExamRecord] = []
        var lastTable = ""
        for batch in batchIDs {
            var query = [URLQueryItem(name: "examBatch.id", value: batch)]
            query += semesterQuery
            let table = try await examText(
                path: "/eams/stdExamTable!examTable.action",
                query: query,
                label: "考试表"
            )
            if !table.isEmpty { lastTable = table }
            let parsed = EamsService.parseExams(table)
            if !parsed.isEmpty {
                collected += parsed
                break
            }
        }

        EamsService.lastExamRaw = lastTable
        return collected
    }

    /// 统一的文字请求，顺便判掉登录页
    private func examText(path: String, query: [URLQueryItem], label: String) async throws -> String {
        var components = URLComponents(string: base + path)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw AppError.badURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Net.session.data(from: url)
        } catch {
            EamsService.lastError = "\(label)请求失败：\(Net.describe(error))\(Net.redirectTrail)"
            // 重定向打转基本都是登录态坏了：清掉 cookie 重登一次就好了
            if EamsService.isRedirectLoop(error) { throw AppError.sessionExpired }
            throw AppError.network(Net.describe(error))
        }

        let html = String(data: data, encoding: .utf8) ?? ""
        if (response.url?.host ?? "").contains("authserver") || html.contains("id=\"pwdEncryptSalt\"") {
            throw AppError.sessionExpired
        }
        return html
    }

    /// 外壳页里的考试批次下拉
    static func parseExamBatches(_ html: String) -> [(id: String, name: String)] {
        guard let block = html.firstMatch(#"<select[^>]*name="examBatch\.id"[^>]*>([\s\S]*?)</select>"#) else {
            return []
        }
        return block.regexGroups(#"<option[^>]*value="([0-9]+)"[^>]*>([^<]*)</option>"#)
            .compactMap { groups in
                guard let id = groups.first, !id.isEmpty else { return nil }
                let name = groups.count > 1 ? groups[1].strippingTags : ""
                return (id: id, name: name)
            }
    }

    /// 「我的考试」是服务端直出的表格，按表头找列，认不出来就当没数据
    static func parseExams(_ html: String) -> [ExamRecord] {
        let rows = html.regexGroups(#"<tr[^>]*>([\s\S]*?)</tr>"#).compactMap { $0.first }
        guard !rows.isEmpty else { return [] }

        let table = rows.map { row -> [String] in
            row.regexGroups(#"<t[dh][^>]*>([\s\S]*?)</t[dh]>"#)
                .compactMap { $0.first }
                .map { $0.strippingTags }
        }

        guard let headerIndex = table.firstIndex(where: { row in
            row.contains { $0.contains("时间") || $0.contains("考场") }
        }) else { return [] }

        let header = table[headerIndex]
        func column(_ keywords: [String]) -> Int? {
            header.firstIndex { head in keywords.contains { head.contains($0) } }
        }

        // 表头里「课程名称」和「课程序号」都带"课程"，得分开认
        let codeColumn = header.firstIndex { $0.contains("课程序号") || $0.contains("课程号") }
        let courseColumn = header.firstIndex { $0.contains("课程名称") }
            ?? column(["科目", "课程"])
        let timeColumn = column(["时间", "日期"])
        let roomColumn = column(["考场", "教室", "地点"])
        let seatColumn = column(["座位"])
        let noteColumn = column(["备注", "说明"])
        let nameColumn = header.firstIndex { $0.contains("考试名称") }
            ?? column(["考试名称", "名称", "考试"])

        guard timeColumn != nil || roomColumn != nil else { return [] }

        var result: [ExamRecord] = []
        for (offset, row) in table[(headerIndex + 1)...].enumerated() {
            guard row.count > 1 else { continue }
            func cell(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                let value = row[index]
                return (value == "-" || value == "—" || value == "--") ? "" : value
            }

            var time = cell(timeColumn)
            // 有的版本时间不单独成列，整行只有一处带日期，就在整行里找
            if ExamRecord.dateKey(in: time).isEmpty {
                if let located = row.first(where: { !ExamRecord.dateKey(in: $0).isEmpty }) {
                    time = located
                }
            }
            // 日期和时间分两列时，把钟点补上
            if !time.isEmpty && !time.contains(":"),
               let clock = row.first(where: { $0.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil }),
               clock != time {
                time += " " + clock
            }
            let room = cell(roomColumn)
            if time.isEmpty && room.isEmpty { continue }

            let course = cell(courseColumn)
            let name = cell(nameColumn)

            result.append(
                ExamRecord(
                    id: "\(offset)-\(course)-\(time)-\(room)",
                    course: course,
                    code: cell(codeColumn),
                    name: name == course ? "" : name,
                    time: time,
                    room: room,
                    seat: cell(seatColumn),
                    note: cell(noteColumn)
                )
            )
        }
        return result
    }

    /// 拉指定学期的成绩。
    /// 成绩页和考试页一样是两层：外壳 person.action 只给学期控件，
    /// 真正的表格由 bg.Go('person!search.action?semesterId=…&looked=yes') 拉进来。
    /// 外壳里的 semesterId 是教务自己的编号，可能和我们学期列表里的 id 不是一个体系，
    /// 所以先用外壳给的默认值，换学期时再用调用方传进来的 id。
    func fetchGrades(semesterID: String) async throws -> [GradeRecord] {
        // 把学期带给外壳，外壳会把它的选择回显在 value:"…" 里，
        // 顺便完成一次"我们的学期编号 → 教务内部编号"的翻译
        let query = semesterID.isEmpty
            ? []
            : [URLQueryItem(name: "semester.id", value: semesterID)]
        let shell = try await examText(
            path: "/eams/teach/grade/course/person.action",
            query: query,
            label: "成绩外壳"
        )
        EamsService.lastGradeShellRaw = shell

        let resolved = shell.firstMatch(#"semesterCalendar\(\{[^}]*value:"([0-9]+)""#)
            ?? semesterID

        let html = try await examText(
            path: "/eams/teach/grade/course/person!search.action",
            query: [
                URLQueryItem(name: "semesterId", value: resolved),
                URLQueryItem(name: "projectType", value: ""),
                URLQueryItem(name: "looked", value: "yes"),
            ],
            label: "成绩表"
        )

        EamsService.lastGradeRaw = html
        return EamsService.parseGrades(html)
    }

    /// 「所有学期成绩」，对应成绩页工具栏上那个 historyCourseGrade
    func fetchAllGrades() async throws -> [GradeRecord] {
        let html = try await examText(
            path: "/eams/teach/grade/course/person!historyCourseGrade.action",
            query: [URLQueryItem(name: "projectType", value: "MAJOR")],
            label: "所有学期成绩"
        )
        EamsService.lastGradeRaw = html
        return EamsService.parseGrades(html)
    }

    /// 成绩页也是服务端直出的表格。表头里的「平时成绩」「期末成绩」这类都当分项，
    /// 「总成绩」才是最终成绩，「绩点」单独一列。
    static func parseGrades(_ html: String) -> [GradeRecord] {
        let rows = html.regexGroups(#"<tr[^>]*>([\s\S]*?)</tr>"#).compactMap { $0.first }
        guard !rows.isEmpty else { return [] }

        let table = rows.map { row -> [String] in
            row.regexGroups(#"<t[dh][^>]*>([\s\S]*?)</t[dh]>"#)
                .compactMap { $0.first }
                .map { $0.strippingTags }
        }

        // 成绩页里可能有好几张表，认那种同时有课程列和成绩列的表头
        guard let headerIndex = table.firstIndex(where: { row in
            let joined = row.joined(separator: "|")
            let hasCourse = row.contains { $0.contains("课程") || $0.contains("科目") }
            let hasScore = joined.contains("成绩") || joined.contains("绩点")
            return hasCourse && hasScore
        }) else { return [] }

        let header = table[headerIndex]
        func column(_ keywords: [String]) -> Int? {
            header.firstIndex { head in keywords.contains { head.contains($0) } }
        }

        let courseColumn = header.firstIndex { $0.contains("课程名称") } ?? column(["科目", "课程"])
        let codeColumn = header.firstIndex { $0.contains("课程序号") || $0.contains("课程号") || $0.contains("课程代码") }
        let termColumn = header.firstIndex { $0.contains("学期") || $0.contains("学年") }
        let creditColumn = column(["学分"])
        let gpaColumn = column(["绩点"])
        // 教务里这个列有的叫「总评成绩」，有的叫「总成绩」「成绩」
        let scoreColumn = header.firstIndex { $0.contains("总评") }
            ?? header.firstIndex { $0.contains("总成绩") }
            ?? header.firstIndex { $0 == "成绩" }
            ?? header.firstIndex { $0.contains("成绩") && !$0.contains("绩点") }

        // 除总成绩以外的「xx成绩」列都当分项
        let componentColumns: [(index: Int, name: String)] = header.enumerated().compactMap { index, head in
            guard head.contains("成绩"), index != scoreColumn else { return nil }
            return (index, head)
        }

        guard courseColumn != nil || scoreColumn != nil else { return [] }

        var result: [GradeRecord] = []
        for (offset, row) in table[(headerIndex + 1)...].enumerated() {
            guard row.count > 1 else { continue }
            func cell(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                let value = row[index]
                return (value == "-" || value == "—" || value == "--") ? "" : value
            }

            let course = cell(courseColumn)
            let score = cell(scoreColumn)
            if course.isEmpty && score.isEmpty { continue }

            let components = componentColumns.compactMap { item -> GradeComponent? in
                let value = cell(item.index)
                guard !value.isEmpty else { return nil }
                return GradeComponent(id: "\(offset)-\(item.name)", name: item.name, score: value)
            }

            result.append(
                GradeRecord(
                    id: "\(offset)-\(course)-\(score)",
                    course: course,
                    code: cell(codeColumn),
                    credit: cell(creditColumn),
                    score: score,
                    gpa: cell(gpaColumn),
                    term: cell(termColumn),
                    components: components
                )
            )
        }
        return result
    }

    // MARK: - 学期列表解析

    /// 响应是 JavaScript 对象字面量：{semesters:{y0:[{id,schoolYear,name},...],y1:[...]}, yearIndex:0}
    /// 有的版本还会套一层 <script> 或者前后带杂字，所以先截出花括号，再层层降级解析。
    private static func parseSemestersJSON(_ data: Data) -> [Semester] {
        var text = String(data: data, encoding: .utf8) ?? ""
        text = text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        var result: [Semester] = []

        if let object = jsonObject(from: text),
           let groups = object["semesters"] as? [String: Any] {
            result = semesters(fromGroups: groups)
        }

        if result.isEmpty {
            result = semestersFromBlocks(text)
        }

        return sortedSemesters(result)
    }

    private static func semesters(fromGroups groups: [String: Any]) -> [Semester] {
        var result: [Semester] = []
        for key in groups.keys.sorted() {
            guard let items = groups[key] as? [[String: Any]] else { continue }
            for (offset, item) in items.enumerated() {
                guard let rawID = item["id"] else { continue }
                let id = "\(rawID)"
                guard !id.isEmpty, !result.contains(where: { $0.id == id }) else { continue }
                result.append(makeSemester(id: id,
                                           schoolYear: stringValue(item, keys: ["schoolYear", "school_year", "academicYear", "year"]),
                                           rawName: stringValue(item, keys: ["name", "termName", "term", "title"]),
                                           startDate: stringValue(item, keys: ["startDate", "start_date", "beginDate", "start"]),
                                           fallbackIndex: offset))
            }
        }
        return result
    }

    /// JSON 走不通时，直接扫文本里每个扁平的 {id:...,schoolYear:"...",name:"..."}
    private static func semestersFromBlocks(_ text: String) -> [Semester] {
        var result: [Semester] = []
        for groups in text.regexGroups(#"(\{[^{}]*\})"#) {
            guard let block = groups.first else { continue }
            guard let id = block.firstMatch(#"id\s*:\s*"?([0-9]+)"?"#), !id.isEmpty else { continue }
            let schoolYear = block.firstMatch(#"schoolYear\s*:\s*"([^"]*)""#) ?? ""
            let rawName = block.firstMatch(#"name\s*:\s*"([^"]*)""#) ?? ""
            guard !schoolYear.isEmpty || !rawName.isEmpty else { continue }
            guard !result.contains(where: { $0.id == id }) else { continue }
            result.append(makeSemester(id: id,
                                       schoolYear: schoolYear,
                                       rawName: rawName,
                                       startDate: block.firstMatch(#"startDate\s*:\s*"([^"]*)""#) ?? "",
                                       fallbackIndex: result.count))
        }
        return result
    }

    private static func makeSemester(id: String, schoolYear: String, rawName: String,
                                     startDate: String, fallbackIndex: Int) -> Semester {
        let termName = normalizedTerm(rawName, fallbackIndex: fallbackIndex)
        let display = schoolYear.isEmpty ? termName : "\(schoolYear)学年\(termName)"
        return Semester(
            id: id,
            name: display,
            schoolYear: schoolYear.isEmpty ? nil : schoolYear,
            termName: termName,
            startDate: startDate.isEmpty ? nil : startDate
        )
    }

    private static func sortedSemesters(_ list: [Semester]) -> [Semester] {
        list.sorted {
            let y0 = $0.schoolYear ?? ""
            let y1 = $1.schoolYear ?? ""
            if y0 != y1 { return y0 > y1 }
            return (Int($0.id) ?? 0) > (Int($1.id) ?? 0)
        }
    }

    /// dataQuery 回来的是 JS 对象字面量，键名不带引号，还可能有尾逗号，先补成合法 JSON
    private static func jsonObject(from text: String) -> [String: Any]? {
        var body = text
        if let first = body.firstIndex(of: "{"), let last = body.lastIndex(of: "}"), first < last {
            body = String(body[first...last])
        }

        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }

        var normalized = body.replacingOccurrences(of: "'", with: "\"")
        normalized = normalized.replacingOccurrences(
            of: #"([{,])\s*([A-Za-z_][A-Za-z0-9_]*)\s*:"#,
            with: #"$1"$2":"#,
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #",\s*([}\]])"#,
            with: #"$1"#,
            options: .regularExpression
        )

        guard let data = normalized.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func stringValue(_ item: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = item[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = item[key] as? NSNumber {
                return value.stringValue
            }
        }
        return ""
    }

    /// 学期名字段各校不一样，可能是 "1"、""、"1学期"、"第一学期"
    private static func normalizedTerm(_ raw: String, fallbackIndex: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "\(fallbackIndex + 1)学期" }
        if trimmed.contains("学期") { return trimmed }
        return "\(trimmed)学期"
    }

    /// 最后的兜底：直接从 HTML 里抠。学期格子常写成「学期<span>1</span>」，要把 span 一起拼上
    private static func parseSemestersHTML(_ text: String) -> [Semester] {
        var result: [Semester] = []
        let pattern = #"val=['"]?([0-9]+)['"]?[^>]*>([^<]{0,20})(?:<span>\s*([^<]{1,20})\s*</span>)?"#
        for groups in text.regexGroups(pattern) {
            guard groups.count >= 2 else { continue }
            let id = groups[0]
            let head = groups[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = groups.count >= 3 ? groups[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let name = normalizedTerm(head + tail, fallbackIndex: result.count)
            guard !result.contains(where: { $0.id == id }) else { continue }
            result.append(Semester(id: id, name: name))
        }
        return result
    }
}
