import SwiftUI
import UIKit

/// 考试安排。数据来自教务「我的考试」，按日期分组排。
struct ExamView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("showDiagnostics") private var showDiagnostics = false

    /// 空表示跟当前学期走；选了历史学期就钉住那一个
    @State private var semesterID = ""

    private var effectiveSemesterID: String {
        semesterID.isEmpty ? app.currentSemesterID : semesterID
    }

    private var selectedSemester: Semester? {
        app.semesters.first { $0.id == effectiveSemesterID }
    }

    private var selectedYear: String? { selectedSemester?.schoolYear }
    private var selectedTerm: String? { selectedSemester?.termName }

    private var years: [String] {
        Array(Set(app.semesters.compactMap { $0.schoolYear })).sorted(by: >)
    }

    private var terms: [String] {
        let names = Set(app.semesters
            .filter { $0.schoolYear == selectedYear }
            .compactMap { $0.termName })
        let ordered = ["1学期", "2学期"].filter { names.contains($0) }
        return ordered + names.subtracting(ordered).sorted()
    }

    private var groups: [(key: String, items: [ExamRecord])] {
        Dictionary(grouping: app.exams) { $0.dateKey }
            .map { (key: $0.key, items: $0.value.sorted { $0.time < $1.time }) }
            .sorted { $0.key < $1.key }
    }

    /// 今天及以后、而且认得出日期的，正常排在前面
    private var upcomingGroups: [(key: String, items: [ExamRecord])] {
        groups.filter { !$0.key.isEmpty && $0.key >= todayKey }
    }

    /// 已经考完的、以及日期都认不出来的，统一压到最后
    private var bottomExams: [ExamRecord] {
        app.exams
            .filter { $0.dateKey.isEmpty || $0.dateKey < todayKey }
            .sorted { lhs, rhs in
                if lhs.dateKey.isEmpty != rhs.dateKey.isEmpty { return !lhs.dateKey.isEmpty }
                if lhs.dateKey != rhs.dateKey { return lhs.dateKey > rhs.dateKey }
                return lhs.time < rhs.time
            }
    }

    private var todayKey: String { ExamView.dayFormatter.string(from: Date()) }

    var body: some View {
        List {
            if let error = app.examsError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if app.exams.isEmpty {
                if app.examsLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在查考试安排…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if app.examsError == nil {
                    Section {
                        ContentUnavailableView(
                            "还没有考试安排",
                            systemImage: "calendar.badge.clock",
                            description: Text("学校排考后会出现在这里")
                        )
                    }
                }

                if app.exams.isEmpty {
                    debugSection
                }
            } else {
                ForEach(upcomingGroups, id: \.key) { group in
                    Section {
                        ForEach(group.items) { exam in
                            row(exam)
                        }
                    } header: {
                        Text(headerText(for: group.key, count: group.items.count))
                    }
                }

                if !bottomExams.isEmpty {
                    Section {
                        ForEach(bottomExams) { exam in
                            row(exam)
                        }
                    } header: {
                        Text("已结束 / 待定")
                    }
                }
            }
        }
        .navigationTitle("考试安排")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await app.refreshExams() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Menu("学年") {
                        ForEach(years, id: \.self) { year in
                            Toggle("\(year)学年", isOn: isYearOn(year))
                        }
                    }

                    Menu("学期") {
                        ForEach(terms, id: \.self) { term in
                            Toggle(term, isOn: isTermOn(term))
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .disabled(app.semesters.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await app.refreshExams() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(app.examsLoading)
            }
        }
        .task {
            if app.exams.isEmpty { await app.refreshExams(semesterID: effectiveSemesterID) }
        }
    }

    /// 空列表时给一点现场信息，方便判断是"真没考试"还是"没解析出来"
    @ViewBuilder
    private var debugSection: some View {
        let raw = EamsService.lastExamRaw
        let shell = EamsService.lastExamShellRaw
        if showDiagnostics {
            Section {
                Text("外壳 \(shell.count) 字符 · 考试表 \(raw.count) 字符")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !raw.isEmpty {
                    Button {
                        UIPasteboard.general.string = """
                        ===== 外壳 stdExamTable.action =====
                        \(shell)

                        ===== 考试表 stdExamTable!examTable.action =====
                        \(raw)
                        """
                    } label: {
                        Label("复制原始返回", systemImage: "doc.on.doc")
                    }

                    Text(summary(of: raw))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("复制出来发给我，就能对上真实的页面结构。")
            }
        }
    }

    private func summary(of raw: String) -> String {
        var parts: [String] = []
        if raw.contains("pwdEncryptSalt") || raw.contains("authserver") { parts.append("像是登录页") }
        if raw.contains("gridtable") { parts.append("有 gridtable") }
        if raw.contains("<table") { parts.append("有表格") }
        if raw.contains("没有") && raw.contains("考试") { parts.append("页面里写了没有考试") }
        return parts.isEmpty ? "没看出明显特征" : parts.joined(separator: "、")
    }

    private func row(_ exam: ExamRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(exam.course.isEmpty ? (exam.name.isEmpty ? "考试" : exam.name) : exam.course)
                    .font(.body.weight(.medium))

                if !subtitle(for: exam).isEmpty {
                    Text(subtitle(for: exam))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    if !exam.time.isEmpty {
                        meta("clock", exam.time)
                    }
                    if !exam.room.isEmpty {
                        meta("mappin.and.ellipse", exam.room)
                    }
                    if !exam.seat.isEmpty {
                        Text("座位 \(exam.seat)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !exam.note.isEmpty {
                    Text(exam.note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            if !remainingText(for: exam).isEmpty {
                Text(remainingText(for: exam))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 2)
    }

    /// 课程序号在前、考试名称在后
    private func subtitle(for exam: ExamRecord) -> String {
        [exam.code, exam.name]
            .filter { !$0.isEmpty && $0 != exam.course }
            .joined(separator: " · ")
    }

    /// 图标和文字的间距，系统的 Label 默认留得太宽
    private func meta(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .regular))
            Text(text)
        }
    }

    /// 课程名右边的「还有几天」
    private func remainingText(for exam: ExamRecord) -> String {
        let key = exam.dateKey
        guard !key.isEmpty,
              let date = ExamView.parser.date(from: key),
              let today = ExamView.parser.date(from: ExamView.dayFormatter.string(from: Date())) else {
            return ""
        }
        let days = Calendar.current.dateComponents([.day], from: today, to: date).day ?? 0
        if days > 0 { return "还有 \(days) 天" }
        if days == 0 { return "今天" }
        return ""
    }

    // MARK: - 学期菜单

    private func isYearOn(_ year: String) -> Binding<Bool> {
        Binding(
            get: { selectedYear == year },
            set: { on in
                guard on, year != selectedYear else { return }
                selectYear(year)
            }
        )
    }

    private func isTermOn(_ term: String) -> Binding<Bool> {
        Binding(
            get: { selectedTerm == term },
            set: { on in
                guard on, term != selectedTerm else { return }
                selectTerm(term)
            }
        )
    }

    private func selectYear(_ year: String) {
        let candidates = app.semesters.filter { $0.schoolYear == year }
        guard !candidates.isEmpty else { return }
        let target = candidates.first { $0.termName == selectedTerm }
            ?? candidates.min { $0.id < $1.id }
        guard let target else { return }
        select(target.id)
    }

    private func selectTerm(_ term: String) {
        let target = app.semesters.first { $0.schoolYear == selectedYear && $0.termName == term }
            ?? app.semesters.first { $0.termName == term }
        guard let target else { return }
        select(target.id)
    }

    private func select(_ id: String) {
        guard id != effectiveSemesterID else { return }
        semesterID = id
        app.exams = []
        Task { await app.refreshExams(semesterID: id) }
    }

    private func headerText(for key: String, count: Int) -> String {
        guard !key.isEmpty else { return "待定（\(count)）" }
        guard let date = ExamView.parser.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        ExamView()
            .environmentObject(AppState())
    }
}
