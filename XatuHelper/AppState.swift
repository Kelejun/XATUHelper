import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var occurrences: [CourseOccurrence] = [] {
        didSet {
            let keys = occurrences.map(\.courseKey)
            guard !keys.isEmpty else { return }
            CoursePalette.register(keys)
        }
    }
    @Published var unitCount = 12
    @Published var studentID = ""
    @Published var fetchedAt: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isLoggedIn = false

    /// 本次启动是否已经播过首页入场动画（只在进程内有效）
    var hasPlayedIntro = false

    /// 所有学期
    @Published var semesters: [Semester] = []
    /// 当前正在看的学期
    @Published var selectedSemesterID = ""
    /// 学校给的当前学期
    @Published var currentSemesterID = ""
    /// 学生课表 / 班级课表
    @Published var kind: TableKind = .student

    /// 电费：选好的宿舍 + 上次查到的余额
    @Published var dorm: DormSelection?
    @Published var electricityBalance: String?
    @Published var electricityCheckedAt: Date?
    @Published var electricityLoading = false
    @Published var electricityError: String?
    /// 按天的余额存档，画曲线和历史页都用它
    @Published var electricityHistory: [ElectricityRecord] = []

    @Published var exams: [ExamRecord] = []
    @Published var examsFetchedAt: Date?
    @Published var examsLoading = false
    @Published var examsError: String?

    @Published var grades: [GradeRecord] = []
    /// 成绩页看的是当前学期还是所有学期
    @Published var gradeScope: GradeScope = .current
    @Published var gradesFetchedAt: Date?
    @Published var gradesLoading = false
    @Published var plan: PlanSnapshot = .empty
    @Published var planNeedsLogin = false
    @Published var planCatalog: PlanCatalog = PlanCatalogStore.load()
    @Published var planFetchedAt: Date?
    @Published var planLoading = false
    @Published var planError: String?
    @Published var gradesError: String?
    /// 成绩页自带的汇总（门数/总学分/平均绩点），页面里有就用页面的
    @Published var gradeSummary: EamsService.GradeSummary?

    @Published var weekOneMonday: Date = AppState.fallStart
    /// 需要验证码/动态码时弹出网页登录
    @Published var showsWebLogin = false

    /// 2026-09-07 是第 1 周周一
    static let fallStart: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 7
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }()

    private var studentTableID: String?
    private var classTableID: String?
    private var semesterTagID = "semesterCalendar_target"
    private var projectID = ""
    /// 登录页填的账号密码，网页兜底登录成功后存进 Keychain
    private var pendingCredentials: (student: String, password: String)?

    private let store = TimetableStore()
    private let cas = CASService()
    private let eams = EamsService()
    private let pay = PayService()
    private var electricProject: PayProject?

    /// 正在进行的自动登录任务，多个请求共用
    private var reloginTask: Task<Void, Error>?
    private let examStore = ExamStore()
    private let gradeStore = GradeStore()
    private let planStore = PlanStore()

    init() {
        // 先把上次存的登录 cookie 塞回来，再读缓存
        CookieVault.restore()
        studentID = Preferences.studentID ?? ""
        dorm = Preferences.dorm
        electricityBalance = Preferences.electricityBalance
        electricityCheckedAt = Preferences.electricityCheckedAt
        electricityHistory = ElectricityHistoryStore.load()
        if let payload = examStore.load() {
            exams = payload.exams
            examsFetchedAt = payload.fetchedAt
        }
        if let payload = gradeStore.load() {
            grades = payload.grades
            gradesFetchedAt = payload.fetchedAt
        }
        if let payload = planStore.load() {
            plan = payload.plan
            planFetchedAt = payload.fetchedAt
        }
        if let snapshot = store.load() {
            occurrences = snapshot.occurrences
            unitCount = snapshot.unitCount
            weekOneMonday = snapshot.weekOneMonday
            fetchedAt = snapshot.fetchedAt
            studentID = snapshot.studentID.isEmpty ? studentID : snapshot.studentID
            semesters = snapshot.semesters ?? []
            selectedSemesterID = snapshot.selectedSemesterID ?? snapshot.semesterID
            currentSemesterID = snapshot.currentSemesterID ?? snapshot.semesterID
            if let raw = snapshot.kind, let parsed = TableKind(rawValue: raw) {
                kind = parsed
            }
            isLoggedIn = true
        }
    }

    // MARK: - 缓存策略

    /// 某类数据是否已经过期（没数据也算过期）
    func isStale(_ kind: CacheKind) -> Bool {
        switch kind {
        case .timetable:
            guard let fetched = fetchedAt else { return true }
            return Date().timeIntervalSince(fetched) >= kind.lifetime
        case .plan:
            guard !plan.sections.isEmpty, let fetched = planFetchedAt else { return true }
            return Date().timeIntervalSince(fetched) >= kind.lifetime
        case .grades:
            guard !grades.isEmpty, let fetched = gradesFetchedAt else { return true }
            return Date().timeIntervalSince(fetched) >= kind.lifetime
        case .exams:
            guard let fetched = examsFetchedAt else { return true }
            return Date().timeIntervalSince(fetched) >= kind.lifetime
        }
    }

    /// 按类型刷新一份数据
    func refresh(_ kind: CacheKind) async {
        switch kind {
        case .timetable:
            await refresh()
        case .plan:
            await refreshPlan()
        case .grades:
            await refreshGrades()
        case .exams:
            await refreshExams(semesterID: isCurrentSemester ? nil : selectedSemesterID)
        }
    }

    // MARK: - 派生状态

    var currentWeek: Int { week(of: Date()) }

    var isCurrentSemester: Bool {
        selectedSemesterID.isEmpty || selectedSemesterID == currentSemesterID
    }

    var semesterName: String {
        semesters.first(where: { $0.id == selectedSemesterID })?.name ?? "当前学期"
    }

    var hasClassTable: Bool { classTableID != nil }

    /// 当前选中学期的第 1 周周一：优先用学期开学日期，退回落到 weekOneMonday
    var semesterStartMonday: Date {
        guard let semester = semesters.first(where: { $0.id == selectedSemesterID }),
              let raw = semester.startDate,
              let day = AppState.parseDate(raw),
              let monday = AppState.mondayOfWeek(containing: day) else {
            return weekOneMonday
        }
        return monday
    }

    func week(of date: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let from = calendar.startOfDay(for: semesterStartMonday)
        let to = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(1, min(30, days / 7 + 1))
    }

    func occurrences(in week: Int) -> [CourseOccurrence] {
        occurrences.filter { $0.weeks.contains(week) }
    }

    // MARK: - 周次对齐

    static func parseDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw.trimmingCharacters(in: .whitespaces)) {
                return date
            }
        }
        return nil
    }

    /// 取某一天所在那一周的周一
    static func mondayOfWeek(containing date: Date) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start) // 1=周日
        let offset = (weekday + 5) % 7 // 周一=0
        return calendar.date(byAdding: .day, value: -offset, to: start)
    }

    /// 用教务首页的"现在是第几周"反过来校准第 1 周周一
    func applyOfficialWeek(_ week: Int, on date: Date = Date()) {
        guard week > 0, let thisMonday = AppState.mondayOfWeek(containing: date) else { return }
        let calendar = Calendar(identifier: .gregorian)
        if let base = calendar.date(byAdding: .day, value: -(week - 1) * 7, to: thisMonday) {
            weekOneMonday = base
        }
    }

    /// 登录后先问一次教务首页，别按自己猜的校历算
    func calibrateFromServer() async {
        guard let week = await eams.fetchOfficialWeek() else { return }
        applyOfficialWeek(week)
        persist()
    }

    // MARK: - 登录 / 刷新

    func login(student: String, password: String) async {
        isLoading = true
        errorMessage = nil
        pendingCredentials = (student, password)
        do {
            try await cas.login(username: student, password: password)
            recordLoginTime()
            Keychain.savePassword(password, account: student)
            Preferences.studentID = student
            studentID = student
            try await bootstrap()
            selectedSemesterID = currentSemesterID
            await calibrateFromServer()
            try await loadTable()
            CookieVault.pinAndSave()
            isLoggedIn = true
            pendingCredentials = nil
        } catch {
            handle(error)
        }
        isLoading = false
    }

    /// 网页登录成功后，cookie 已经落进共享存储，这里把该拉的都拉一遍
    func completeWebLogin() async {
        showsWebLogin = false
        isLoading = true
        errorMessage = nil
        do {
            try await bootstrap()
            if selectedSemesterID.isEmpty {
                selectedSemesterID = currentSemesterID
            }
            await calibrateFromServer()
            try await loadTable()

            CookieVault.pinAndSave()
            if let credentials = pendingCredentials {
                Keychain.savePassword(credentials.password, account: credentials.student)
                Preferences.studentID = credentials.student
                studentID = credentials.student
                pendingCredentials = nil
            }
            isLoggedIn = true
            await rescheduleNotifications()
        } catch {
            handle(error)
        }
        isLoading = false
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await withRelogin {
                if self.studentTableID == nil || self.semesters.isEmpty {
                    try await self.bootstrap()
                    if self.selectedSemesterID.isEmpty {
                        self.selectedSemesterID = self.currentSemesterID
                    }
                }
                try await self.loadTable()
            }
            isLoggedIn = true
            publishWidgetSnapshot()
        } catch {
            handle(error)
        }
        isLoading = false
    }

    /// 换学期
    func selectSemester(_ id: String) async {
        guard id != selectedSemesterID else { return }
        selectedSemesterID = id
        occurrences = []
        await reloadTable()
    }

    /// 换课表类型
    func selectKind(_ newKind: TableKind) async {
        guard newKind != kind else { return }
        kind = newKind
        occurrences = []
        await reloadTable()
    }

    func logout() {
        if let account = Preferences.studentID {
            Keychain.deletePassword(account: account)
        }
        Preferences.studentID = nil
        CookieVault.clear()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        store.clear()
        examStore.clear()
        gradeStore.clear()
        planStore.clear()
        Task { await NotificationService.clearAll() }
        exams = []
        occurrences = []
        studentID = ""
        semesters = []
        selectedSemesterID = ""
        currentSemesterID = ""
        kind = .student
        studentTableID = nil
        classTableID = nil
        fetchedAt = nil
        weekOneMonday = AppState.fallStart
        isLoggedIn = false
    }

    /// 用当前周次反推第 1 周周一，方便老大手动校正
    func calibrate(currentWeek: Int) {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let offset = (currentWeek - 1) * 7
        weekOneMonday = calendar.date(byAdding: .day, value: -offset, to: today) ?? weekOneMonday
        persist()
    }

    // MARK: - 内部

    private func reloadTable() async {
        isLoading = true
        errorMessage = nil
        do {
            try await withRelogin { try await self.loadTable() }
        } catch {
            handle(error)
        }
        isLoading = false
    }

    private func withRelogin(_ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch let error as AppError {
            guard isRecoverable(error) else { throw error }
            try await reloginAndRetry(operation)
        } catch {
            guard Net.isTransportProblem(error) else { throw error }
            try await reloginAndRetry(operation)
        }
    }

    /// 会话过期、或者网络层被 ATS 之类挡住，都是"清掉 cookie 重登一次"能救回来的
    private func isRecoverable(_ error: AppError) -> Bool {
        switch error {
        case .sessionExpired:
            return true
        case .network(let message):
            return message.contains("App Transport Security") || message.contains("secure connection")
        default:
            return false
        }
    }

    private func clearXatuCookies() {
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.contains("xatu.edu.cn") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func reloginAndRetry(_ operation: () async throws -> Void) async throws {
        try await performRelogin()
        do {
            try await operation()
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.network(Net.describe(error))
        }
    }

    /// 同一时间只允许一次 CAS 登录；并发调用共用同一个 Task，避免一串请求同时换票把账号打成"登录频繁"
    private func performRelogin() async throws {
        if let existing = reloginTask {
            try await existing.value
            return
        }

        // 统一认证那边的票还在的话，静默换一次就够了：不碰密码，也不算一次登录。
        if await CASService.silentRenew() {
            CookieVault.pinAndSave()
            return
        }

        let now = Date()
        let recent = Preferences.loginTimes.filter { now.timeIntervalSince($0) < 3600 }
        if let last = recent.last {
            let wait = 60 - now.timeIntervalSince(last)
            if wait > 0 {
                throw AppError.reloginFailed("刚刚已经登录过一次了，\(Int(wait.rounded(.up))) 秒后再试。连着登会被学校冻结账号")
            }
        }
        if recent.count >= 4 {
            throw AppError.reloginFailed("一小时内已经自动登录过 \(recent.count) 次，先别再试了，免得账号被冻结")
        }
        Preferences.loginTimes = recent + [now]

        let task = Task<Void, Error> { try await self.rawRelogin() }
        reloginTask = task
        do {
            try await task.value
            reloginTask = nil
        } catch {
            reloginTask = nil
            throw error
        }
    }

    private func recordLoginTime() {
        let now = Date()
        Preferences.loginTimes = Preferences.loginTimes.filter { now.timeIntervalSince($0) < 3600 } + [now]
    }

    private func rawRelogin() async throws {
        clearXatuCookies()
        guard let saved = Preferences.studentID,
              let password = Keychain.loadPassword(account: saved), !password.isEmpty else {
            throw AppError.sessionExpired
        }
        do {
            try await cas.login(username: saved, password: password)
            CookieVault.pinAndSave()
        } catch {
            EamsService.lastError = "自动重登失败：\(error.localizedDescription)"
            throw AppError.reloginFailed("登录已过期，自动重新登录没成功（\(error.localizedDescription)），请手动登录一次")
        }
    }

    /// 带返回值版本的 withRelogin
    private func withReloginValue<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as AppError {
            guard isRecoverable(error) else { throw error }
            return try await reloginAndRetryValue(operation)
        } catch {
            guard Net.isTransportProblem(error) else { throw error }
            return try await reloginAndRetryValue(operation)
        }
    }

    private func reloginAndRetryValue<T>(_ operation: () async throws -> T) async throws -> T {
        try await performRelogin()
        do {
            return try await operation()
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.network(Net.describe(error))
        }
    }

    // MARK: - 考试

    func refreshExams(semesterID: String? = nil) async {
        guard !examsLoading else { return }
        examsLoading = true
        examsError = nil
        do {
            let fallback = selectedSemesterID.isEmpty ? currentSemesterID : selectedSemesterID
            let target = semesterID ?? fallback
            exams = try await withReloginValue { try await self.eams.fetchExams(semesterID: target) }
            examsFetchedAt = Date()
            examStore.save(exams, at: examsFetchedAt ?? Date())
            await rescheduleNotifications()
        } catch {
            examsError = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        examsLoading = false
    }

    // MARK: - 成绩

    func refreshGrades(semesterID: String? = nil, scope: GradeScope? = nil) async {
        guard !gradesLoading else { return }
        gradesLoading = true
        gradesError = nil
        gradeSummary = nil
        if let scope { gradeScope = scope }
        do {
            if gradeScope == .all {
                grades = try await withReloginValue { try await self.eams.fetchAllGrades() }
            } else {
                let fallback = selectedSemesterID.isEmpty ? currentSemesterID : selectedSemesterID
                let target = semesterID ?? fallback
                grades = try await withReloginValue { try await self.eams.fetchGrades(semesterID: target) }
            }
            gradeSummary = EamsService.lastGradeSummary
            gradesFetchedAt = Date()
            gradeStore.save(grades, at: gradesFetchedAt ?? Date())
        } catch {
            gradesError = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        gradesLoading = false
    }

    // MARK: - 培养计划

    func refreshPlan() async {
        guard !planLoading else { return }
        planLoading = true
        planError = nil
        planNeedsLogin = false
        do {
            // 不在这里自动重登：培养计划页一进来就拉，自动重登会把 CAS 登录次数打满
            plan = try await eams.fetchPlan()
            planFetchedAt = Date()
            planStore.save(plan, at: planFetchedAt ?? Date())
            await refreshPlanCatalogIfNeeded()
            if plan.sections.isEmpty {
                planError = "没从页面里认出学分要求，可能是页面改了"
            }
        } catch AppError.sessionExpired {
            planNeedsLogin = true
            planError = "教务的登录状态过期了，点下面重新登录一次就好"
        } catch {
            planError = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        planLoading = false
    }

    /// 教学计划里的课程信息（开课学期 / 学时 / 是否必修）取到一次就存本地
    func refreshPlanCatalogIfNeeded(force: Bool = false) async {
        guard force || planCatalog.courses.isEmpty else { return }
        do {
            let courses = try await eams.fetchPlanCatalog()
            guard !courses.isEmpty else { return }
            planCatalog = PlanCatalog(updatedAt: Date(), courses: courses)
            PlanCatalogStore.save(planCatalog)
        } catch {
            // 拿不到就安静留着旧的，计划完成情况照常显示
            EamsService.lastError = "教学计划没取到：\(error.localizedDescription)"
        }
    }

    func courseInfo(for course: PlanCourse) -> PlanCourseInfo? {
        let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty, let hit = planCatalog.courses.first(where: {
            $0.code.trimmingCharacters(in: .whitespacesAndNewlines) == code
        }) {
            return hit
        }
        return planCatalog.courses.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == name
        }
    }

    /// 用户手动点「重新登录」，只走一次，不受自动重登的冷却限制
    func reloginNow() async {
        do {
            try await rawRelogin()
            recordLoginTime()
            planNeedsLogin = false
            await refreshPlanCatalogIfNeeded(force: true)
            await refreshPlan()
        } catch {
            planError = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 电费

    /// 启动时最多做两件事：电费过期先查电费；课表超过 168 小时，隔 60 秒再查
    /// 其他数据（考试、成绩）只在进入对应页面时刷新，首页考试卡片只读缓存
    /// 按当前开关重排本地通知（内容在排期那一刻固定，所以每次数据变了都要重来一遍）
    func rescheduleNotifications() async {
        let classOn = NotificationSettings.classOn
        let examOn = NotificationSettings.examOn
        guard classOn || examOn else {
            await NotificationService.clearAll()
            return
        }
        await NotificationService.reschedule(
            occurrences: classOn ? occurrences : [],
            weekOneMonday: semesterStartMonday,
            exams: examOn ? exams : [],
            classLeadMinutes: NotificationSettings.classLeadMinutes,
            examLeadMinutes: NotificationSettings.examLeadMinutes
        )
    }

    func startupRefreshIfNeeded() async {
        guard isLoggedIn else { return }
        await rescheduleNotifications()

        let electricityIsStale: Bool = {
            guard dorm != nil, electricityBalance != nil else { return dorm != nil }
            guard let checked = electricityCheckedAt else { return true }
            return !Calendar.current.isDateInToday(checked)
        }()
        if electricityIsStale {
            await refreshElectricity()
        }

        // 四份数据错峰过期，启动时最多补一份最该补的，避免一窝蜂联网
        let overdue: [CacheKind] = CacheKind.allCases.filter { isStale($0) }
        guard let target = overdue.max(by: { overdueRatio($0) < overdueRatio($1) }) else { return }

        try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        guard !Task.isCancelled else { return }
        await refresh(target)
    }

    /// 过期了多少（按各自有效期归一化），用来挑最该更新的那一份
    private func overdueRatio(_ kind: CacheKind) -> Double {
        guard let date = lastUpdated(kind) else { return .greatestFiniteMagnitude }
        return Date().timeIntervalSince(date) / kind.lifetime
    }

    private func lastUpdated(_ kind: CacheKind) -> Date? {
        switch kind {
        case .timetable: return fetchedAt
        case .plan: return planFetchedAt
        case .grades: return gradesFetchedAt
        case .exams: return examsFetchedAt
        }
    }

    /// 冷启动/切回前台时顺手查一次，没选过宿舍就什么都不做
    /// 每天第一次打开 app 才自动查一次，其余情况只靠用户手动刷新
    /// 每日自动刷新开关，默认打开
    var autoRefreshElectricity: Bool {
        UserDefaults.standard.object(forKey: "autoRefreshElectricity") as? Bool ?? true
    }

    func refreshElectricityIfNeeded() async {
        guard dorm != nil, autoRefreshElectricity else { return }
        if let checked = electricityCheckedAt,
           Calendar.current.isDateInToday(checked),
           electricityBalance != nil {
            return
        }
        await refreshElectricity()
    }

    func refreshElectricity() async {
        guard let dorm, !electricityLoading else { return }
        electricityLoading = true
        electricityError = nil
        do {
            let balance = try await withPay { project -> String in
                try await self.pay.balance(projectID: project.id, dorm: dorm)
            }
            electricityBalance = balance
            electricityCheckedAt = Date()
            Preferences.electricityBalance = balance
            Preferences.electricityCheckedAt = electricityCheckedAt
            recordElectricity(balance: balance)
            publishWidgetSnapshot()
        } catch {
            electricityError = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        electricityLoading = false
    }

    /// 一天只留一条，刷新多少次都只是覆盖当天这条
    private func recordElectricity(balance: String) {
        guard let value = Double(balance) else { return }
        let record = ElectricityRecord(day: ElectricityRecord.dayString(), balance: value)
        electricityHistory = ElectricityHistoryStore.upserting(record, into: electricityHistory)
        ElectricityHistoryStore.save(electricityHistory)
    }

    /// 最近几天的记录，够画曲线用
    func electricityTrend(days: Int = 7) -> [ElectricityRecord] {
        Array(electricityHistory.suffix(days))
    }

    /// 某天的用量 = 前一天的余额 - 当天的余额（前一天没记录就是 nil）
    func electricityUsage(on record: ElectricityRecord) -> Double? {
        guard let index = electricityHistory.firstIndex(of: record), index > 0 else { return nil }
        let previous = electricityHistory[index - 1]
        guard previous.day != record.day else { return nil }
        return previous.balance - record.balance
    }

    /// 余额低于十块就当快没电了，用橙色提醒一下
    var isLowBalance: Bool {
        guard let text = electricityBalance else { return false }
        let cleaned = text.replacingOccurrences(of: "¥", with: "").trimmingCharacters(in: .whitespaces)
        return (Double(cleaned) ?? .infinity) < 10
    }

    func saveDorm(_ selection: DormSelection) async {
        dorm = selection
        Preferences.dorm = selection
        electricityBalance = nil
        electricityCheckedAt = nil
        Preferences.electricityBalance = nil
        Preferences.electricityCheckedAt = nil
        await refreshElectricity()
    }

    func clearDorm() {
        dorm = nil
        Preferences.dorm = nil
        electricityBalance = nil
        electricityCheckedAt = nil
        Preferences.electricityBalance = nil
        Preferences.electricityCheckedAt = nil
        electricityError = nil
    }

    /// 充值页地址：走缴费平台的 casLogin，用现有 CAS 票据静默登录后停在落地页。
    /// 直接开充值路由/注入 token 都会被页面的登录态校验拦成「系统维护」。
    func chargePage() async -> (url: String, hash: String?)? {
        (url: "https://jfpay.xatu.edu.cn/casLogin/", hash: nil)
    }

    func loadSchools() async throws -> [DormOption] {
        try await withPay { try await self.pay.schools(projectID: $0.id) }
    }

    func loadBuildings(areaID: String) async throws -> [DormOption] {
        try await withPay { try await self.pay.buildings(projectID: $0.id, areaID: areaID) }
    }

    func loadRooms(areaID: String, buildID: String) async throws -> [DormOption] {
        try await withPay { try await self.pay.rooms(projectID: $0.id, areaID: areaID, buildID: buildID) }
    }

    /// 借统一认证的登录态进 jfpay，顺手找到电费项目；会话过期会走一次自动重登
    private func withPay<T>(_ operation: (PayProject) async throws -> T) async throws -> T {
        var value: T?
        try await withRelogin {
            let project = try await self.electricProjectOrLoad()
            value = try await operation(project)
        }
        guard let result = value else {
            throw AppError.loginFailed(PayService.lastError ?? "缴费平台没返回数据")
        }
        return result
    }

    private func electricProjectOrLoad() async throws -> PayProject {
        if let project = electricProject { return project }
        let list = try await pay.electricProjects()
        guard let first = list.first else {
            throw AppError.loginFailed("缴费平台里没找到电费项目，可能学校还没开这个入口")
        }
        electricProject = first
        return first
    }

    /// 冷启动后补一次外壳信息：学生/班级记录 ID、学期 tagId，顺便刷新学期列表
    func ensureShell() async {
        guard studentTableID == nil || semesters.isEmpty else { return }
        do {
            try await bootstrap()
            if selectedSemesterID.isEmpty {
                selectedSemesterID = currentSemesterID
            }
            await calibrateFromServer()
            persist()
        } catch {
            // 真正的错误留给 refresh 去提示
        }
    }

    private func bootstrap() async throws {
        let shell = try await eams.loadShell()
        studentTableID = shell.studentTableID
        classTableID = shell.classTableID
        currentSemesterID = shell.currentSemesterID
        semesterTagID = shell.semesterTagID
        projectID = shell.projectID

        let list = await eams.fetchSemesters(tagID: shell.semesterTagID, current: shell.currentSemesterID)
        semesters = list.isEmpty ? [Semester(id: shell.currentSemesterID, name: "当前学期")] : list
        if selectedSemesterID.isEmpty {
            selectedSemesterID = shell.currentSemesterID
        }
    }

    private func loadTable() async throws {
        let semester = selectedSemesterID.isEmpty ? currentSemesterID : selectedSemesterID
        let ids: String
        switch kind {
        case .student:
            guard let value = studentTableID else { throw AppError.parseFailed }
            ids = value
        case .classGroup:
            guard let value = classTableID else { throw AppError.noClassTable }
            ids = value
        }

        let parsed = try await eams.fetchTable(kind: kind, ids: ids,
                                               semesterID: semester, projectID: projectID)
        occurrences = parsed.occurrences
        unitCount = parsed.unitCount
        fetchedAt = Date()
        CookieVault.save()
        persist()
    }

    private func persist() {
        let snapshot = TimetableSnapshot(
            occurrences: occurrences,
            studentID: studentID,
            semesterID: selectedSemesterID.isEmpty ? currentSemesterID : selectedSemesterID,
            fetchedAt: fetchedAt ?? Date(),
            weekOneMonday: weekOneMonday,
            unitCount: unitCount,
            semesters: semesters,
            selectedSemesterID: selectedSemesterID,
            currentSemesterID: currentSemesterID,
            kind: kind.rawValue
        )
        store.save(snapshot)
    }

    private func handle(_ error: Error) {
        if let appError = error as? AppError {
            if case .needCaptcha = appError {
                // 这种错不该在界面上干挂着，直接开网页
                errorMessage = nil
                showsWebLogin = true
                return
            }
            errorMessage = appError.errorDescription
            switch appError {
            case .sessionExpired, .reloginFailed:
                // 自动重登这条路走不通了，直接退回登录页，别留个报错横幅让人干瞪眼
                isLoggedIn = false
            default:
                break
            }
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
