import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var occurrences: [CourseOccurrence] = []
    @Published var unitCount = 12
    @Published var studentID = ""
    @Published var fetchedAt: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isLoggedIn = false

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

    init() {
        studentID = Preferences.studentID ?? ""
        dorm = Preferences.dorm
        electricityBalance = Preferences.electricityBalance
        electricityCheckedAt = Preferences.electricityCheckedAt
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
            Keychain.savePassword(password, account: student)
            Preferences.studentID = student
            studentID = student
            try await bootstrap()
            selectedSemesterID = currentSemesterID
            await calibrateFromServer()
            try await loadTable()
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

            if let credentials = pendingCredentials {
                Keychain.savePassword(credentials.password, account: credentials.student)
                Preferences.studentID = credentials.student
                studentID = credentials.student
                pendingCredentials = nil
            }
            isLoggedIn = true
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
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        store.clear()
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
        clearXatuCookies()
        do {
            guard let saved = Preferences.studentID,
                  let password = Keychain.loadPassword(account: saved), !password.isEmpty else {
                throw AppError.sessionExpired
            }
            do {
                try await cas.login(username: saved, password: password)
            } catch {
                EamsService.lastError = "自动重登失败：\(error.localizedDescription)"
                throw AppError.reloginFailed("登录已过期，自动重新登录没成功（\(error.localizedDescription)），请手动登录一次")
            }
            try await operation()
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.network(Net.describe(error))
        }
    }

    // MARK: - 电费

    /// 冷启动/切回前台时顺手查一次，没选过宿舍就什么都不做
    /// 每天第一次打开 app 才自动查一次，其余情况只靠用户手动刷新
    func refreshElectricityIfNeeded() async {
        guard dorm != nil else { return }
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
        } catch {
            electricityError = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        electricityLoading = false
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
            try await self.pay.loginWithExistingSession()
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
