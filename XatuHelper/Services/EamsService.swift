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
    /// 最近一次培养计划（完成情况）页的原始 HTML
    static var lastPlanRaw = ""
    static var lastPlanCatalogRaw = ""

    /// 成绩页底部/顶部自带的汇总（门数、总学分、平均绩点），有就直接用页面上的，
    /// 没有才退回自己算。
    struct GradeSummary {
        var count: Int?
        var credits: Double?
        var gpa: Double?

        var isEmpty: Bool { count == nil && credits == nil && gpa == nil }
    }

    static var lastGradeSummary: GradeSummary?
    /// 汇总那一小段原文，排查数字为什么不对时用
    static var lastGradeSummaryRaw = ""

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

        ===== 成绩汇总匹配到的原文 =====
        \(lastGradeSummaryRaw.isEmpty ? "(空，没匹配到汇总)" : lastGradeSummaryRaw)

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

    /// 拉培养计划完成情况：myPlanCompl.action 这张表就是「模块 / 要求学分 / 已修学分」。
    func fetchPlan() async throws -> PlanSnapshot {
        var last: PlanSnapshot = .empty
        for path in ["/eams/myPlanCompl.action", "/eams/myPlan.action"] {
            let html = try await examText(path: path, query: [], label: "培养计划")
            EamsService.lastPlanRaw = html
            let parsed = EamsService.parsePlan(html)
            if !parsed.sections.isEmpty { return parsed }
            last = parsed
        }
        return last
    }

    /// 拉「教学计划」：每门课的开课学期、学时、课程性质都在这张表里。
    /// 表头按关键词认列，认不出来就返回空，不影响计划完成情况页。
    func fetchPlanCatalog() async throws -> [PlanCourseInfo] {
        let html = try await examText(path: "/eams/myPlan.action", query: [], label: "教学计划")
        EamsService.lastPlanCatalogRaw = html
        return EamsService.parsePlanCatalog(html)
    }

    /// 教学计划表格解析（myPlan.action 的 planInfoTable）。
    /// 真实结构：表头两行，课程行前面会带若干 `class="group"` 的合并分类格（只有每组第一行才有），
    /// 所以不能按表头下标取列，只能先找到 `class="course"` 的课程名格，再按相对偏移取值：
    /// 课程名 +1 学分、+2 总学时、+8 开课学期、+10 是否必修；课程名前一格是课程代码。
    static func parsePlanCatalog(_ html: String) -> [PlanCourseInfo] {
        var result: [PlanCourseInfo] = []
        var seen = Set<String>()

        for rowMatch in html.regexGroups(#"(<tr[^>]*>)([\s\S]*?)</tr>"#) {
            guard rowMatch.count >= 2 else { continue }
            let cellMatches = rowMatch[1].regexGroups(#"(<td\b[^>]*>)([\s\S]*?)</td>"#)
            guard !cellMatches.isEmpty else { continue }

            var attrs: [String] = []
            var texts: [String] = []
            for cell in cellMatches {
                guard cell.count >= 2 else { attrs.append(""); texts.append(""); continue }
                attrs.append(cell[0].lowercased())
                let raw = cell[1].strippingTags
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                texts.append(raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
            }

            guard let nameIndex = attrs.firstIndex(where: { $0.contains("course") && $0.contains("class") }) else { continue }

            func text(_ offset: Int) -> String {
                let i = nameIndex + offset
                guard i >= 0, i < texts.count else { return "" }
                return texts[i]
            }

            var name = text(0)
            // 课程名格子里带「序号 + 名称」，去掉前面的序号。
            if let stripped = name.firstMatch(#"^(?:\d+)\s+(.+)$"#), !stripped.isEmpty {
                name = stripped
            }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "课程名称", !name.contains("学分小计") else { continue }

            let credit = text(1)
            let hours = text(2)
            guard credit.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { continue }

            var code = nameIndex > 0 ? texts[nameIndex - 1] : ""
            if code.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) == nil {
                code = ""
            }

            let required = text(10)
            let nature = required.contains("是") ? "必修" : (required.contains("否") ? "选修" : "")

            let key = code.isEmpty ? name : code
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            result.append(PlanCourseInfo(
                code: code,
                name: name,
                nature: nature,
                credit: credit,
                hours: hours,
                term: text(8)
            ))
        }
        return result
    }

    /// 培养计划表格解析。
    /// 真实结构：上面一张 infoTable 放「要求学分/实修学分」「GPA」，下面一张 formTable：
    ///   - 模块行：<tr class="darkColumn">，第一个 td colspan=3 是标题，后面依次是要求学分、实修学分、空、缺额说明
    ///   - 课程行：8 个 td —— 序号/课程序号/课程名称/要求学分/实修学分/成绩/是否通过/备注
    /// 模块分两级：一级「一 通识教育」，二级「(一) 通识必修」；有的模块没有二级、课程直接挂在下面。
    static func parsePlan(_ html: String) -> PlanSnapshot {
        var snapshot = PlanSnapshot()

        let plain = html.strippingTags.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        if let name = plain.firstMatch(#"姓名:\s*(\S+)"#) { snapshot.studentName = name }
        if let major = plain.firstMatch(#"专业/专业方向:\s*([^ ]+)"#) { snapshot.major = major }
        if let gpa = plain.firstMatch(#"GPA:\s*([0-9.]+)"#) { snapshot.gpa = gpa }
        if let pair = plain.regexGroups(#"要求学分/实修学分:\s*([0-9.]+)\s*/\s*([0-9.]+)"#).first, pair.count == 2 {
            snapshot.totalRequired = Double(pair[0]) ?? 0
            snapshot.totalEarned = Double(pair[1]) ?? 0
        }

        var top: [PlanSection] = []
        var currentTop: Int?
        var currentChild: Int?
        var currentGrandchild: Int?
        var sequence = 0

        for rowMatch in html.regexGroups(#"(<tr[^>]*>)([\s\S]*?)</tr>"#) {
            guard rowMatch.count >= 2 else { continue }
            let rowTag = rowMatch[0]
            let rowHTML = rowMatch[1]
            let cells = rowHTML.regexGroups(#"<td[^>]*>([\s\S]*?)</td>"#)
                .compactMap { $0.first }
                .map { $0.strippingTags.replacingOccurrences(of: "&nbsp;", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !cells.isEmpty else { continue }

            if rowTag.contains("darkColumn") {
                var title = cells[0]
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // 标题后面常跟一句「(所有子项均应满足要求)」，去掉免得挤
                if let bracket = title.firstIndex(where: { $0 == "(" || $0 == "（" }) {
                    let prefix = String(title[title.startIndex..<bracket]).trimmingCharacters(in: .whitespaces)
                    // 只有前面还有正经标题才截；像「(一) 通识必修」这种括号在开头的不动
                    if !prefix.isEmpty { title = prefix }
                }
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }

                let numbers = cells.dropFirst().compactMap { value -> Double? in
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    guard trimmed.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
                    return Double(trimmed)
                }
                let required = numbers.first ?? 0
                let earned = numbers.count > 1 ? numbers[1] : 0
                let shortfall = max(required - earned, 0)
                sequence += 1
                let section = PlanSection(
                    id: "s\(sequence)",
                    title: title,
                    required: required,
                    earned: earned,
                    shortfall: shortfall
                )

                // 三级标题各有各的写法：一级「一 通识教育」、二级「(一) 通识必修」、三级「1 英语分组」
                let isLevel2 = title.range(of: #"^[（(][一二三四五六七八九十]+[)）]"#, options: .regularExpression) != nil
                let isLevel3 = title.range(of: #"^[0-9]+[ 　]"#, options: .regularExpression) != nil

                if let index = currentTop, index < top.count,
                   let child = currentChild, child < top[index].children.count,
                   isLevel3 {
                    top[index].children[child].children.append(section)
                    currentGrandchild = top[index].children[child].children.count - 1
                } else if let index = currentTop, index < top.count, isLevel2 {
                    top[index].children.append(section)
                    currentChild = top[index].children.count - 1
                    currentGrandchild = nil
                } else {
                    top.append(section)
                    currentTop = top.count - 1
                    currentChild = nil
                    currentGrandchild = nil
                }
                continue
            }

            guard cells.count >= 7,
                  cells[0].range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else { continue }

            let course = PlanCourse(
                id: "c\(sequence)-\(cells[0])",
                code: cells[1],
                name: cells[2],
                required: Double(cells[3]) ?? 0,
                earned: Double(cells[4]) ?? 0,
                score: cells[5],
                passed: cells[6].contains("是")
            )
            guard let index = currentTop, index < top.count else { continue }
            if let child = currentChild, child < top[index].children.count,
               let grandchild = currentGrandchild,
               grandchild < top[index].children[child].children.count {
                top[index].children[child].children[grandchild].courses.append(course)
            } else if let child = currentChild, child < top[index].children.count {
                top[index].children[child].courses.append(course)
            } else {
                top[index].courses.append(course)
            }
        }

        snapshot.sections = top
        if snapshot.totalRequired == 0 {
            snapshot.totalRequired = top.reduce(0) { $0 + $1.required }
            snapshot.totalEarned = top.reduce(0) { $0 + $1.earned }
        }
        return snapshot
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
        EamsService.lastGradeSummary = EamsService.parseGradeSummary(html)
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
        EamsService.lastGradeSummary = EamsService.parseGradeSummary(html)
        return EamsService.parseGrades(html)
    }

    /// 从成绩页抠学校自己算好的汇总数字。
    /// 优先按表格单元格找（标签格 + 数字格），找不到再退回纯文本邻近匹配。
    static func parseGradeSummary(_ html: String) -> GradeSummary {
        var summary = GradeSummary()

        func plausible(_ value: Double, in range: ClosedRange<Double>) -> Double? {
            // 4 位数基本是学年（2024-2025），不是我们要的统计值
            guard value < 1900, range.contains(value) else { return nil }
            return value
        }

        func trailingNumber(_ text: String) -> Double? {
            guard let raw = text.firstMatch(#"([0-9]+(?:\.[0-9]+)?)"#) else { return nil }
            return Double(raw)
        }

        // 1. 表格：标签格自己带数字，或者紧挨着的下一格是数字
        let rows = html.regexGroups(#"<tr[^>]*>([\s\S]*?)</tr>"#).compactMap { $0.first }
        let table = rows.map { row -> [String] in
            row.regexGroups(#"<t[dh][^>]*>([\s\S]*?)</t[dh]>"#)
                .compactMap { $0.first }
                .map { $0.strippingTags }
        }

        func cellValue(_ keywords: [String]) -> Double? {
            for row in table {
                for (index, cell) in row.enumerated() {
                    guard keywords.contains(where: { cell.contains($0) }) else { continue }
                    // 标签后面直接跟数字
                    if let value = trailingNumber(cell) { return value }
                    // 数字在下一格 / 再下一格
                    for offset in 1...2 where index + offset < row.count {
                        if let value = trailingNumber(row[index + offset]) { return value }
                    }
                }
            }
            return nil
        }

        // 2. 纯文本：标签 + 冒号/空格 + 数字
        let plain = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        func textValue(_ keywords: [String]) -> Double? {
            for keyword in keywords {
                let pattern = NSRegularExpression.escapedPattern(for: keyword)
                    + #"[:：\s]{0,4}([0-9]+(?:\.[0-9]+)?)"#
                if let raw = plain.firstMatch(pattern), let value = Double(raw) {
                    return value
                }
            }
            return nil
        }

        func lookup(_ keywords: [String], range: ClosedRange<Double>) -> Double? {
            if let value = cellValue(keywords), let ok = plausible(value, in: range) { return ok }
            if let value = textValue(keywords), let ok = plausible(value, in: range) { return ok }
            return nil
        }

        if let value = lookup(["课程门数", "门数", "课程数"], range: 1...200) {
            summary.count = Int(value)
        }
        summary.credits = lookup(["总学分", "合计学分", "学分合计", "已修学分", "已获学分", "获得学分"],
                                range: 0...500)
        summary.gpa = lookup(["平均学分绩点", "平均绩点", "平均GPA"], range: 0...6)

        EamsService.lastGradeSummaryRaw = plain.firstMatch(#".{0,40}(?:总学分|平均[学分]*绩点|门数).{0,60}"#) ?? ""

        return summary
    }

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
        // 成绩列就一个「总评成绩」，其余「xx成绩」都是分项
        let scoreColumn = header.firstIndex { $0.contains("总评") }
            ?? header.firstIndex { $0.contains("最终") }

        // 分项：除总评外的「xx成绩」列，外加单独一列叫「其他」的分数
        let componentColumns: [(index: Int, name: String)] = header.enumerated().compactMap { index, head in
            guard index != scoreColumn, !head.contains("总评") else { return nil }
            guard head.contains("成绩") || head == "其他" else { return nil }
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
