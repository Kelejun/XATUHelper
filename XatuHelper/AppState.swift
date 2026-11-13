import Foundation
import SwiftUI
import Combine

// MARK: - 应用内通知

/// 拿到新数据时顶部弹的那条横幅
enum InAppNoticeKind: String, Identifiable {
    case exam
    case grade
    case loginFailure
    case sessionExpired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exam: return "有新的考试安排"
        case .grade: return "有新的成绩公布"
        case .loginFailure: return "登录失败"
        case .sessionExpired: return "登录已过期"
        }
    }
}

struct InAppNotice: Identifiable, Equatable {
    var kind: InAppNoticeKind
    var message: String
    var id = UUID()
}

/// 点横幅后要打开的页面
enum DeepLink: String, Identifiable {
    case exam
    case grade

    var id: String { rawValue }
}

@MainActor
final class AppState: ObservableObject {
    let isDemoMode: Bool
    @Published var showsDemoAccount = false
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
    @Published var backgroundElectricityScheduleError: String?
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
    @Published var planCatalog = PlanCatalog(updatedAt: .distantPast, courses: [])
    @Published var inAppNotice: InAppNotice?
    @Published var deepLink: DeepLink?
    @Published var planFetchedAt: Date?
    @Published var planLoading = false
    @Published var planError: String?
    @Published var gradesError: String?
    /// 成绩页自带的汇总（门数/总学分/平均绩点），页面里有就用页面的
    @Published var gradeSummary: EamsService.GradeSummary?

    @Published var weekOneMonday: Date = AppState.fallStart
    /// 需要验证码/动态码时弹出网页登录
    @Published var showsWebLogin = false
    @Published var webLoginSessionID = UUID()

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
    private var pendingPasswordVerified = false

    private let store = TimetableStore()
    private let editStore = TimetableEditStore()
    private var officialOccurrences: [CourseOccurrence] = []
    private var manualWeekAnchor: TimetableSnapshot.WeekAnchor?
    @Published private(set) var timetableEdits: [TimetableEdit] = []
    @Published private(set) var pendingTimetableEdits: [UUID: [Int]] = [:]
    private var notificationRefresh: Task<Void, Never>?
    private let cas = CASService()
    private let eams = EamsService()
    private let pay = PayService()
    private var electricProject: PayProject?

    /// 正在进行的自动登录任务，多个请求共用
    private var reloginTask: Task<Void, Error>?
    private let examStore = ExamStore()
    private let gradeStore = GradeStore()
    private let planStore = PlanStore()

    init(isDemo: Bool = false) {
        isDemoMode = isDemo
        if isDemo {
            configureDemoAccount()
            return
        }
        // 先把上次存的登录 cookie 塞回来，再读缓存
        CookieVault.restore()
        planCatalog = PlanCatalogStore.load()
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
        if let snapshot = store.load(),
           studentID.isEmpty || snapshot.studentID.isEmpty || snapshot.studentID == studentID {
            officialOccurrences = snapshot.occurrences
            manualWeekAnchor = snapshot.manualWeekAnchor
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
            rebuildTimetable()
            isLoggedIn = true
        }
    }

    // MARK: - 缓存策略

    /// 某类数据是否已经过期（没数据也算过期）
    func isStale(_ kind: CacheKind) -> Bool {
        guard !isDemoMode else { return false }
        if !AcademicRefreshSettings.reduced {
            let now = Date()
            switch kind {
            case .timetable:
                return AcademicRefreshPolicy.needsDailyRefresh(fetchedAt, now: now)
            case .plan:
                return false
            case .grades:
                return AcademicRefreshPolicy.gradesEnabled(terms: refreshTerms, now: now) &&
                    AcademicRefreshPolicy.needsDailyRefresh(gradesFetchedAt, now: now)
            case .exams:
                return !AcademicRefreshPolicy.isVacation(terms: refreshTerms, now: now) &&
                    AcademicRefreshPolicy.needsDailyRefresh(examsFetchedAt, now: now)
            }
        }
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

    private var refreshTerms: [AcademicRefreshPolicy.Term] {
        let spans = CalendarCache.scheduleSpans
        var terms = spans.compactMap { span -> AcademicRefreshPolicy.Term? in
            guard let start = Self.parseDate(span.start), let end = Self.parseDate(span.end), end >= start else { return nil }
            return .init(start: start, end: end)
        }
        // School metadata supplies dates when no calendar is cached, including a newly started term.
        for semester in semesters {
            guard let raw = semester.startDate, let start = Self.parseDate(raw),
                  !terms.contains(where: { abs($0.start.timeIntervalSince(start)) < 30 * 86400 }) else { continue }
            terms.append(.init(start: start, end: nil))
        }
        if let first = CalendarCache.load()?.semesters.sorted(by: { $0.start < $1.start }).first,
           let start = Self.parseDate(first.start),
           let nextStart = Calendar.current.date(byAdding: .day, value: 364, to: start),
           !terms.contains(where: { abs($0.start.timeIntervalSince(nextStart)) < 30 * 86400 }) {
            terms.append(.init(start: nextStart, end: nil))
        }
        if terms.isEmpty { terms = [.init(start: weekOneMonday, end: nil)] }
        return terms
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

    /// 当前学期第 1 周的周一，优先使用手动校正，其次使用教务开学日期。
    var semesterStartMonday: Date {
        if let anchor = manualWeekAnchor, anchor.semesterID == timetableSemesterID {
            return anchor.monday
        }
        guard let semester = semesters.first(where: { $0.id == timetableSemesterID }),
              let raw = semester.startDate,
              let day = AppState.parseDate(raw),
              let monday = AppState.mondayOfWeek(containing: day) else {
            return weekOneMonday
        }
        return monday
    }

    func week(of date: Date) -> Int {
        let week = TimetableDates.week(of: date, monday: semesterStartMonday)
        return min(max(week, TimetableDates.weeks.lowerBound), TimetableDates.weeks.upperBound)
    }

    func occurrences(in week: Int) -> [CourseOccurrence] {
        occurrences.compactMap { occurrence in
            guard occurrence.weeks.contains(week) else { return nil }
            var item = occurrence
            item.weeks = [week]
            return item
        }
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
            rebuildTimetable()
        }
    }

    /// 登录后先问一次教务首页，别按自己猜的校历算
    func calibrateFromServer() async {
        guard !isDemoMode else { return }
        guard let week = await eams.fetchOfficialWeek() else { return }
        applyOfficialWeek(week)
        persist()
    }

    // MARK: - 登录 / 刷新

    func login(student: String, password: String) async {
        guard !isLoading, !isDemoMode else { return }
        pendingPasswordVerified = false
        isLoading = true
        errorMessage = nil
        pendingCredentials = (student, password)
        do {
            try await cas.login(username: student, password: password)
            pendingPasswordVerified = true
            Keychain.savePassword(password, account: student)
            Preferences.studentID = student
            setTimetableAccount(student)
            try await bootstrap()
            selectedSemesterID = currentSemesterID
            await calibrateFromServer()
            try await loadTable()
            CookieVault.pinAndSave()
            showsWebLogin = false
            dismissNotice()
            isLoggedIn = true
            pendingCredentials = nil
        } catch {
            presentLoginFailure()
        }
        isLoading = false
    }

    /// 网页登录成功后，cookie 已经落进共享存储，这里把该拉的都拉一遍
    func completeWebLogin() async {
        guard !isLoading, !isDemoMode else { return }
        isLoading = true
        let session = webLoginSessionID
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await bootstrap()
            try Task.checkCancellation()
            guard session == webLoginSessionID else { return }
            if selectedSemesterID.isEmpty {
                selectedSemesterID = currentSemesterID
            }
            if let credentials = pendingCredentials {
                setTimetableAccount(credentials.student)
            }
            await calibrateFromServer()
            try await loadTable()

            try Task.checkCancellation()
            guard session == webLoginSessionID else { return }
            CookieVault.pinAndSave()
            if let credentials = pendingCredentials {
                if pendingPasswordVerified {
                    Keychain.savePassword(credentials.password, account: credentials.student)
                }
                Preferences.studentID = credentials.student
                pendingCredentials = nil
            }
            showsWebLogin = false
            dismissNotice()
            isLoggedIn = true
            await rescheduleNotifications()
        } catch {
            guard !Task.isCancelled, session == webLoginSessionID else { return }
            presentLoginFailure()
        }
    }

    func cancelWebLogin() {
        webLoginSessionID = UUID()
        showsWebLogin = false
        pendingCredentials = nil
        pendingPasswordVerified = false
        if inAppNotice?.kind == .loginFailure { dismissNotice() }
    }

    private func presentLoginFailure() {
        errorMessage = nil
        webLoginSessionID = UUID()
        showsWebLogin = true
        showNotice(InAppNotice(kind: .loginFailure, message: "可能是因为密码错误、触发验证码等原因"))
    }

    func refresh() async {
        guard !isDemoMode else { return }
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
            if isCurrentSemester && kind == .student { await rescheduleNotifications() }
        } catch {
            handle(error)
        }
        isLoading = false
    }

    /// 换学期
    func selectSemester(_ id: String) async {
        guard !isLoading, id != selectedSemesterID else { return }
        selectedSemesterID = id
        officialOccurrences = []
        fetchedAt = nil
        rebuildTimetable()
        await reloadTable()
    }

    /// 换课表类型
    func selectKind(_ newKind: TableKind) async {
        guard !isLoading, newKind != kind else { return }
        kind = newKind
        officialOccurrences = []
        fetchedAt = nil
        rebuildTimetable()
        await reloadTable()
    }

    func logout() {
        if isDemoMode {
            isLoggedIn = false
            return
        }
        pendingCredentials = nil
        pendingPasswordVerified = false
        showsWebLogin = false
        dismissNotice()
        ElectricityRefreshSettings.resetAttempts()
        BackgroundElectricityRefresh.clearExitReminder()
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
        exams = []
        examsFetchedAt = nil
        grades = []
        gradesFetchedAt = nil
        plan = PlanSnapshot.empty
        planFetchedAt = nil
        planCatalog = PlanCatalog(updatedAt: Date(), courses: [])
        PlanCatalogStore.clear()
        officialOccurrences = []
        manualWeekAnchor = nil
        timetableEdits = []
        pendingTimetableEdits = [:]
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
        Task { await rescheduleNotifications() }
        PhoneWatchBridge.shared.start(app: self)
        PhoneWatchBridge.shared.publish(force: true)
        scheduleBackgroundElectricityRefresh()
    }

    /// 用当前周次反推第 1 周周一，方便老大手动校正
    func calibrate(currentWeek: Int) {
        guard let monday = Self.mondayOfWeek(containing: Date()) else { return }
        manualWeekAnchor = .init(semesterID: timetableSemesterID,
                                 monday: TimetableDates.date(week: 2 - currentWeek, day: 1, monday: monday))
        rebuildTimetable()
        persist()
        publishWidgetSnapshot()
        Task { await rescheduleNotifications() }
    }

    // MARK: - 内部

    private func reloadTable() async {
        isLoading = true
        errorMessage = nil
        do {
            try await withRelogin { try await self.loadTable() }
            publishWidgetSnapshot()
            if isCurrentSemester && kind == .student { await rescheduleNotifications() }
        } catch {
            handle(error)
        }
        isLoading = false
    }

    private func withRelogin(_ operation: () async throws -> Void) async throws {
        try await withReloginValue(operation)
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

    /// 并发请求共用完整的会话恢复过程，包括静默续期。
    private func performRelogin() async throws {
        if let existing = reloginTask {
            try await existing.value
            return
        }

        let task = Task<Void, Error> {
            if await CASService.silentRenew() {
                CookieVault.pinAndSave()
                return
            }
            try await self.rawRelogin()
        }
        reloginTask = task
        defer { reloginTask = nil }
        try await task.value
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
            do {
                return try await operation()
            } catch let error as AppError {
                guard isRecoverable(error) else { throw error }
            } catch {
                guard Net.isTransportProblem(error) else { throw error }
            }
            try await performRelogin()
            return try await operation()
        } catch {
            _ = contentErrorDescription(error)
            throw error
        }
    }

    /// 重登失败或重试后仍过期时返回登录页，保留本地数据和已保存的账号。
    private func contentErrorDescription(_ error: Error) -> String? {
        if let appError = error as? AppError {
            switch appError {
            case .sessionExpired, .reloginFailed:
                let wasLoggedIn = isLoggedIn
                errorMessage = nil
                planError = nil
                examsError = nil
                gradesError = nil
                electricityError = nil
                showsWebLogin = false
                deepLink = nil
                isLoggedIn = false
                if wasLoggedIn {
                    showNotice(InAppNotice(kind: .sessionExpired,
                                           message: "自动重新登录未成功，请手动重新登录"))
                }
                return nil
            default:
                return appError.errorDescription
            }
        }
        return error.localizedDescription
    }

    // MARK: - 考试

    func refreshExams(semesterID: String? = nil) async {
        guard !isDemoMode else { return }
        guard !examsLoading else { return }
        examsLoading = true
        examsError = nil
        do {
            let fallback = selectedSemesterID.isEmpty ? currentSemesterID : selectedSemesterID
            let target = semesterID ?? fallback
            let previous = exams
            exams = try await withReloginValue { try await self.eams.fetchExams(semesterID: target) }
            examsFetchedAt = Date()
            examStore.save(exams, at: examsFetchedAt ?? Date())
            notifyIfNewExams(previous: previous, current: exams, semesterID: target)
            await rescheduleNotifications()
        } catch {
            examsError = contentErrorDescription(error)
        }
        examsLoading = false
    }

    // MARK: - 成绩

    func refreshGrades(semesterID: String? = nil, scope: GradeScope? = nil) async {
        guard !isDemoMode else { return }
        guard !gradesLoading else { return }
        gradesLoading = true
        gradesError = nil
        gradeSummary = nil
        if let scope { gradeScope = scope }
        do {
            let previous = grades
            if gradeScope == .all {
                grades = try await withReloginValue { try await self.eams.fetchAllGrades() }
            } else {
                let fallback = selectedSemesterID.isEmpty ? currentSemesterID : selectedSemesterID
                let target = semesterID ?? fallback
                grades = try await withReloginValue { try await self.eams.fetchGrades(semesterID: target) }
            }
            notifyIfNewGrades(previous: previous, current: grades)
            gradeSummary = EamsService.lastGradeSummary
            gradesFetchedAt = Date()
            gradeStore.save(grades, at: gradesFetchedAt ?? Date())
            if !AcademicRefreshSettings.reduced {
                let scopeKey = gradeScope == .all ? "all" : (semesterID ?? (selectedSemesterID.isEmpty ? currentSemesterID : selectedSemesterID))
                let key = "academic.gradeFingerprint.\(studentID).\(scopeKey)"
                let fingerprint = try GradeRecord.refreshFingerprint(grades)
                let previousFingerprint = UserDefaults.standard.data(forKey: key)
                if previousFingerprint != fingerprint && (!grades.isEmpty || previousFingerprint != nil) {
                    UserDefaults.standard.set(true, forKey: pendingPlanRefreshKey)
                }
                UserDefaults.standard.set(fingerprint, forKey: key)
                await refreshPlanAfterGradeChangeIfNeeded()
            }
        } catch {
            gradesError = contentErrorDescription(error)
        }
        gradesLoading = false
    }

    // MARK: - 新内容提示

    /// 考试：这次多了几场以前没见过的（按 id + 时间 + 考场认）
    private func notifyIfNewExams(previous: [ExamRecord], current: [ExamRecord], semesterID: String) {
        guard !previous.isEmpty, semesterID == selectedSemesterID else { return }
        let fresh = current.filter { exam in
            !previous.contains { $0.id == exam.id && $0.time == exam.time && $0.room == exam.room }
        }
        guard !fresh.isEmpty else { return }
        let names = fresh.prefix(2).map(\.course).joined(separator: "、")
        let tail = fresh.count > 2 ? " 等 \(fresh.count) 场" : ""
        showNotice(InAppNotice(kind: .exam, message: names + tail))
    }

    /// 成绩：以前没分或者分数变了
    private func notifyIfNewGrades(previous: [GradeRecord], current: [GradeRecord]) {
        guard !previous.isEmpty else { return }
        let fresh = current.filter { grade in
            guard !grade.score.isEmpty, grade.score != "--" else { return false }
            guard let old = previous.first(where: { $0.id == grade.id }) else { return true }
            return old.score.isEmpty || old.score == "--" || old.score != grade.score
        }
        guard !fresh.isEmpty else { return }
        let names = fresh.prefix(2).map { "\($0.course) \($0.score)" }.joined(separator: "、")
        let tail = fresh.count > 2 ? " 等 \(fresh.count) 门" : ""
        showNotice(InAppNotice(kind: .grade, message: names + tail))
    }

    private func showNotice(_ notice: InAppNotice) {
        withAnimation {
            inAppNotice = notice
        }
    }

    func dismissNotice() {
        withAnimation {
            inAppNotice = nil
        }
    }

    // MARK: - 培养计划

    func refreshPlan() async {
        guard !isDemoMode else { return }
        guard !planLoading else { return }
        planLoading = true
        planError = nil
        do {
            plan = try await withReloginValue { try await self.eams.fetchPlan() }
            planFetchedAt = Date()
            planStore.save(plan, at: planFetchedAt ?? Date())
            await refreshPlanCatalogIfNeeded()
            if !plan.sections.isEmpty { UserDefaults.standard.removeObject(forKey: pendingPlanRefreshKey) }
            if plan.sections.isEmpty {
                planError = "没从页面里认出学分要求，可能是页面改了"
            }
        } catch {
            planError = contentErrorDescription(error)
        }
        planLoading = false
    }

    /// 教学计划里的课程信息（开课学期 / 学时 / 是否必修）取到一次就存本地
    func refreshPlanCatalogIfNeeded(force: Bool = false) async {
        guard !isDemoMode else { return }
        guard force || planCatalog.courses.isEmpty else { return }
        do {
            let courses = try await withReloginValue { try await self.eams.fetchPlanCatalog() }
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

    // MARK: - 电费

    /// Data changes rebuild the scheduled local reminders.
    func rescheduleNotifications() async {
        guard !isDemoMode else { return }
        let previous = notificationRefresh
        let next = Task {
            await previous?.value
            await applyNotificationSchedule()
        }
        notificationRefresh = next
        await next.value
    }

    private func applyNotificationSchedule() async {
        let classOn = NotificationSettings.classOn
        let examOn = NotificationSettings.examOn
        guard isLoggedIn, classOn || examOn else {
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
        guard !isDemoMode else { return }
        guard isLoggedIn else { return }
        await rescheduleNotifications()

        await refreshElectricityIfNeeded()

        if AcademicRefreshSettings.reduced {
            let overdue = [CacheKind.timetable, .grades, .exams].filter { isStale($0) }
            guard let target = overdue.max(by: { overdueRatio($0) < overdueRatio($1) }) else { return }
            guard await waitForRefreshSlot() else { return }
            if isStale(target) { await refresh(target) }
            return
        }

        var attemptedGrades = false
        for kind in [CacheKind.timetable, .grades, .exams] {
            guard isLoggedIn, !Task.isCancelled, !AcademicRefreshSettings.reduced else { return }
            guard isStale(kind) else { continue }
            guard await waitForRefreshSlot() else { return }
            guard !AcademicRefreshSettings.reduced else { return }
            if isStale(kind) {
                if kind == .grades { attemptedGrades = true }
                await refresh(kind)
            }
        }
        if !attemptedGrades { await refreshPlanAfterGradeChangeIfNeeded() }
        await refreshCalendarIfNeeded()
    }

    private func waitForRefreshSlot() async -> Bool {
        do { try await Task.sleep(for: .seconds(3)) } catch { return false }
        return isLoggedIn && !Task.isCancelled
    }

    private var pendingPlanRefreshKey: String { "academic.pendingPlanRefresh.\(studentID)" }

    private func refreshPlanAfterGradeChangeIfNeeded() async {
        guard !AcademicRefreshSettings.reduced,
              UserDefaults.standard.bool(forKey: pendingPlanRefreshKey), !planLoading,
              await waitForRefreshSlot() else { return }
        guard !AcademicRefreshSettings.reduced else { return }
        await refreshPlan()
    }

    @Published var calendarRefreshError: String?
    private var calendarRefreshing = false

    func refreshCalendarIfNeeded() async {
        guard !isDemoMode, isLoggedIn, !AcademicRefreshSettings.reduced, !calendarRefreshing else { return }
        let defaults = UserDefaults.standard
        let now = Date()
        let cached = CalendarCache.load()
        let spans = (cached?.semesters ?? []).sorted { $0.start < $1.start }
        let starts = spans.compactMap { Self.parseDate($0.start) }
        let pendingKey = "academic.calendar.targetYear"
        let pendingYear = defaults.integer(forKey: pendingKey)
        let target: Int
        switch AcademicRefreshPolicy.calendarDecision(starts: starts, pendingYear: pendingYear > 0 ? pendingYear : nil, now: now) {
        case .wait:
            defaults.removeObject(forKey: pendingKey)
            return
        case .bootstrap:
            target = pendingYear
        case .update(let year):
            target = year
            defaults.set(year, forKey: pendingKey)
        }
        let attemptKey = "academic.calendar.lastAttempt"
        guard AcademicRefreshPolicy.needsDailyRefresh(defaults.object(forKey: attemptKey) as? Date, now: now) else { return }
        calendarRefreshing = true
        defer { calendarRefreshing = false }
        guard await waitForRefreshSlot(), !AcademicRefreshSettings.reduced else { return }
        defaults.set(Date(), forKey: attemptKey)
        calendarRefreshError = nil
        switch await CalendarCache.refresh() {
        case .failure(let error): calendarRefreshError = error.localizedDescription
        case .success(let info):
            if let first = info.semesters.sorted(by: { $0.start < $1.start }).first,
               let date = Self.parseDate(first.start), info.semesters.count >= 2,
               target > 0, Calendar.current.component(.year, from: date) >= target {
                defaults.removeObject(forKey: pendingKey)
            }
        }
        publishWidgetSnapshot()
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

    var autoRefreshElectricity: Bool { ElectricityRefreshSettings.automaticEnabled }

    func scheduleBackgroundElectricityRefresh() {
        guard !isDemoMode else { return }
        backgroundElectricityScheduleError = BackgroundElectricityRefresh.schedule(
            isLoggedIn: isLoggedIn, hasDorm: dorm != nil,
            checkedAt: electricityCheckedAt, hasBalance: electricityBalance != nil
        )
    }

    /// SwiftUI 后台任务到期会取消当前 Task；尝试标记先落盘，避免中断后重复请求。
    func performBackgroundElectricityRefresh() async {
        guard !isDemoMode else { return }
        defer {
            CookieVault.pinAndSave()
            scheduleBackgroundElectricityRefresh()
        }
        guard isLoggedIn, dorm != nil, !electricityLoading,
              ElectricityRefreshSettings.backgroundEnabled, !Task.isCancelled,
              ElectricityRefreshPolicy.canAttempt(
                now: Date(), checkedAt: electricityCheckedAt, hasBalance: electricityBalance != nil,
                lastAttempt: ElectricityRefreshSettings.lastBackgroundAttempt,
                awaitingForeground: ElectricityRefreshSettings.awaitingForeground
              ) else { return }
        ElectricityRefreshSettings.lastBackgroundAttempt = Date()
        ElectricityRefreshSettings.awaitingForeground = true
        await refreshElectricity(source: .background)
    }

    /// 前台补查允许重试后台失败；当天已有成功记录则直接使用缓存。
    func refreshElectricityIfNeeded() async {
        guard !isDemoMode else { return }
        guard isLoggedIn, dorm != nil, autoRefreshElectricity, !Task.isCancelled else { return }
        guard !ElectricityRefreshPolicy.hasRefreshedToday(
            checkedAt: electricityCheckedAt, hasBalance: electricityBalance != nil, now: Date()
        ) else {
            // 若上次在保存余额后、清理标记前中断，已有成功记录即可恢复排期。
            ElectricityRefreshSettings.awaitingForeground = false
            scheduleBackgroundElectricityRefresh()
            return
        }
        await refreshElectricity(source: .automatic)
    }

    @discardableResult
    func refreshElectricity(source: ElectricityRefreshSource = .manual) async -> Bool {
        guard !isDemoMode else { return true }
        guard let dorm, isLoggedIn, !electricityLoading, source.isAllowed, !Task.isCancelled else { return false }
        if source != .manual, ElectricityRefreshPolicy.hasRefreshedToday(
            checkedAt: electricityCheckedAt, hasBalance: electricityBalance != nil, now: Date()
        ) {
            ElectricityRefreshSettings.awaitingForeground = false
            scheduleBackgroundElectricityRefresh()
            return true
        }
        electricityLoading = true
        electricityError = nil
        defer {
            electricityLoading = false
            scheduleBackgroundElectricityRefresh()
        }
        do {
            let balance = try await withPay { project -> String in
                try Task.checkCancellation()
                return try await self.pay.balance(projectID: project.id, dorm: dorm)
            }
            try Task.checkCancellation()
            // 查询途中关掉自动刷新、退出账号或更换宿舍，不能把旧结果写回去。
            guard isLoggedIn, self.dorm == dorm, source.isAllowed else { return false }
            electricityBalance = balance
            electricityCheckedAt = Date()
            Preferences.electricityBalance = balance
            Preferences.electricityCheckedAt = electricityCheckedAt
            recordElectricity(balance: balance)
            ElectricityRefreshSettings.awaitingForeground = false
            CookieVault.pinAndSave()
            publishWidgetSnapshot()
            return true
        } catch {
            if !Task.isCancelled {
                electricityError = contentErrorDescription(error)
            }
            return false
        }
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

    /// 余额低于十度就当快没电了，用橙色提醒一下
    var isLowBalance: Bool {
        guard let text = electricityBalance else { return false }
        let cleaned = text.replacingOccurrences(of: "¥", with: "").trimmingCharacters(in: .whitespaces)
        return (Double(cleaned) ?? .infinity) < 10
    }

    func saveDorm(_ selection: DormSelection) async {
        if isDemoMode { dorm = selection; return }
        ElectricityRefreshSettings.resetAttempts()
        dorm = selection
        Preferences.dorm = selection
        electricityBalance = nil
        electricityCheckedAt = nil
        Preferences.electricityBalance = nil
        Preferences.electricityCheckedAt = nil
        await refreshElectricity()
    }

    func clearDorm() {
        if isDemoMode { dorm = nil; return }
        ElectricityRefreshSettings.resetAttempts()
        BackgroundElectricityRefresh.clearExitReminder()
        dorm = nil
        Preferences.dorm = nil
        electricityBalance = nil
        electricityCheckedAt = nil
        Preferences.electricityBalance = nil
        Preferences.electricityCheckedAt = nil
        electricityError = nil
        scheduleBackgroundElectricityRefresh()
    }

    /// 充值页地址：走缴费平台的 casLogin，用现有 CAS 票据静默登录后停在落地页。
    /// 直接开充值路由/注入 token 都会被页面的登录态校验拦成「系统维护」。
    func chargePage() async -> (url: String, hash: String?)? {
        guard !isDemoMode else { return nil }
        return (url: "https://jfpay.xatu.edu.cn/casLogin/", hash: nil)
    }

    func loadSchools() async throws -> [DormOption] {
        if isDemoMode { return [DormOption(id: "demo-area", name: "未央校区")] }
        return try await withPay { try await self.pay.schools(projectID: $0.id) }
    }

    func loadBuildings(areaID: String) async throws -> [DormOption] {
        if isDemoMode { return [DormOption(id: "demo-build", name: "9号公寓")] }
        return try await withPay { try await self.pay.buildings(projectID: $0.id, areaID: areaID) }
    }

    func loadRooms(areaID: String, buildID: String) async throws -> [DormOption] {
        if isDemoMode { return [DormOption(id: "demo-room", name: "320宿舍")] }
        return try await withPay { try await self.pay.rooms(projectID: $0.id, areaID: areaID, buildID: buildID) }
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
        guard !isDemoMode else { return }
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

        let account = studentID
        let requestedKind = kind
        let parsed = try await eams.fetchTable(kind: requestedKind, ids: ids,
                                               semesterID: semester, projectID: projectID)
        try Task.checkCancellation()
        guard account == studentID, requestedKind == kind,
              semester == timetableSemesterID else { throw CancellationError() }
        officialOccurrences = parsed.occurrences
        unitCount = parsed.unitCount
        rebuildTimetable()
        fetchedAt = Date()
        CookieVault.save()
        persist()
    }

    private func persist() {
        guard !isDemoMode, let fetchedAt else { return }
        let snapshot = TimetableSnapshot(
            occurrences: officialOccurrences,
            studentID: studentID,
            semesterID: selectedSemesterID.isEmpty ? currentSemesterID : selectedSemesterID,
            fetchedAt: fetchedAt,
            weekOneMonday: weekOneMonday,
            unitCount: unitCount,
            semesters: semesters,
            selectedSemesterID: selectedSemesterID,
            currentSemesterID: currentSemesterID,
            kind: kind.rawValue,
            manualWeekAnchor: manualWeekAnchor
        )
        store.save(snapshot)
    }

    private var timetableSemesterID: String {
        selectedSemesterID.isEmpty ? currentSemesterID : selectedSemesterID
    }

    var canEditTimetable: Bool {
        isLoggedIn && !isDemoMode && kind == .student && !studentID.isEmpty && !timetableSemesterID.isEmpty
    }

    var canUseTimetableDates: Bool {
        isCurrentSemester || manualWeekAnchor?.semesterID == timetableSemesterID
            || semesters.contains { $0.id == timetableSemesterID && $0.startDate.flatMap(Self.parseDate) != nil }
    }

    private func setTimetableAccount(_ account: String) {
        guard account != studentID else { return }
        studentID = account
        selectedSemesterID = currentSemesterID
        kind = .student
        weekOneMonday = Self.fallStart
        officialOccurrences = []
        manualWeekAnchor = nil
        fetchedAt = nil
        rebuildTimetable()
    }

    private func rebuildTimetable() {
        let edits: [TimetableEdit]
        if kind == .student, !studentID.isEmpty, !timetableSemesterID.isEmpty {
            edits = (try? editStore.load())?[studentID]?[timetableSemesterID] ?? []
        } else {
            edits = []
        }
        timetableEdits = edits
        applyTimetable(editedTimetable(edits))
    }

    func editedTimetable(_ edits: [TimetableEdit]) -> EditedTimetable {
        EditedTimetable(base: officialOccurrences, edits: edits, monday: semesterStartMonday, unitCount: unitCount)
    }

    private func applyTimetable(_ result: EditedTimetable) {
        occurrences = result.occurrences
        pendingTimetableEdits = result.pending
    }

    func saveTimetableEdits(_ edits: [TimetableEdit]) throws {
        guard canEditTimetable else { throw TimetableEditError.unavailable }
        var accounts = try editStore.load()
        accounts[studentID, default: [:]][timetableSemesterID] = edits
        try editStore.save(accounts)
        timetableEdits = edits
        applyTimetable(editedTimetable(edits))
        publishWidgetSnapshot()
        if isCurrentSemester { Task { await rescheduleNotifications() } }
    }

    private func handle(_ error: Error) {
        if let appError = error as? AppError {
            if case .needCaptcha = appError {
                // 这种错不该在界面上干挂着，直接开网页
                errorMessage = nil
                showsWebLogin = true
                return
            }
            errorMessage = contentErrorDescription(appError)
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
