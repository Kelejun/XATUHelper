import SwiftUI
import UIKit

/// 考试安排。数据来自教务「我的考试」，按日期分组排。
struct ExamView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("showDiagnostics") private var showDiagnostics = false

    /// 空表示跟当前学期走；选了历史学期就钉住那一个
    @State private var semesterID = ""
    @State private var showNotificationSetup = false
    @State private var showsCompleted = false

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

    private var nextExam: ExamRecord? { upcomingGroups.first?.items.first }

    private var laterGroups: [(key: String, items: [ExamRecord])] {
        upcomingGroups.compactMap { group in
            let items = group.items.filter { $0.id != nextExam?.id }
            return items.isEmpty ? nil : (key: group.key, items: items)
        }
    }

    private var pendingExams: [ExamRecord] {
        app.exams.filter { $0.dateKey.isEmpty }
    }

    private var completedExams: [ExamRecord] {
        app.exams.filter { !$0.dateKey.isEmpty && $0.dateKey < todayKey }
            .sorted { $0.dateKey == $1.dateKey ? $0.time < $1.time : $0.dateKey > $1.dateKey }
    }

    private var todayKey: String { ExamView.dayFormatter.string(from: Date()) }

    var body: some View {
        List {
            if let error = app.examsError {
                Section {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if app.exams.isEmpty {
                if app.examsLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在查考试安排…").foregroundStyle(.secondary)
                        }
                    }
                } else if app.examsError == nil {
                    Section {
                        ContentUnavailableView(
                            "还没有考试安排", systemImage: "calendar.badge.clock",
                            description: Text("学校排考后会出现在这里")
                        )
                    }
                }
                debugSection
            } else {
                if let exam = nextExam {
                    Section {
                        nextExamCard(exam)
                            .listRowBackground(
                                LinearGradient(
                                    colors: [Color.yellow.opacity(0.09), Color(uiColor: .secondarySystemGroupedBackground)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                if !laterGroups.isEmpty {
                    Section {
                        ForEach(laterGroups, id: \.key) { group in
                            dateGroup(group.key, exams: group.items)
                        }
                    } header: {
                        sectionHeading("后续考试", count: laterGroups.reduce(0) { $0 + $1.items.count })
                    }
                }
                if !pendingExams.isEmpty {
                    Section {
                        ForEach(pendingExams) { exam in
                            examDetails(exam, pending: true)
                        }
                    } header: {
                        sectionHeading("时间待定", count: pendingExams.count)
                    }
                }
                if !completedExams.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showsCompleted) {
                            ForEach(completedExams) { exam in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(dateText(exam.dateKey, format: "M月d日 EEEE"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    examDetails(exam)
                                }
                                .padding(.vertical, 5)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("已结束").foregroundStyle(.primary)
                                Text("\(completedExams.count) 场")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("考试安排")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await app.refreshExams(semesterID: effectiveSemesterID) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                semesterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await app.refreshExams(semesterID: effectiveSemesterID) }
                } label: {
                    if app.examsLoading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .accessibilityLabel("刷新考试安排")
                .disabled(app.examsLoading)
            }
        }
        .task {
            if app.isStale(.exams) { await app.refreshExams(semesterID: effectiveSemesterID) }
            if !app.isDemoMode && !NotificationSettings.hasPromptedExam {
                showNotificationSetup = true
            }
        }
        .sheet(isPresented: $showNotificationSetup) {
            ExamNotificationSetupSheet()
        }
    }

    private var semesterMenu: some View {
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
        .accessibilityLabel("切换学期")
        .disabled(app.semesters.isEmpty || app.examsLoading)
    }

    private func sectionHeading(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count) 场").monospacedDigit()
        }
        .textCase(nil)
    }

    private func nextExamCard(_ exam: ExamRecord) -> some View {
        let tint: Color = .yellow

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("下一场考试")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(courseTitle(exam))
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(remainingText(for: exam))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text([dateText(exam.dateKey, format: "M月d日 EEEE"), exam.timeWithoutDate]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if !subtitle(for: exam).isEmpty {
                    Text(subtitle(for: exam)).font(.caption).foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    locationField("考场", value: exam.room.isEmpty ? "待公布" : exam.room)
                    Spacer(minLength: 12)
                    locationField("座位号", value: exam.seat.isEmpty ? "待公布" : exam.seat, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 12) {
                    locationField("考场", value: exam.room.isEmpty ? "待公布" : exam.room)
                    locationField("座位号", value: exam.seat.isEmpty ? "待公布" : exam.seat)
                }
            }
            if !exam.note.isEmpty {
                Text(exam.note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func locationField(_ title: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dateGroup(_ key: String, exams: [ExamRecord]) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(dateText(key, format: "M.dd")).font(.headline).monospacedDigit()
                Text(dateText(key, format: "EEE")).font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 48, alignment: .leading)
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(exams.enumerated()), id: \.element.id) { index, exam in
                    if index > 0 { Divider() }
                    examDetails(exam, countdown: index == 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func courseTitle(_ exam: ExamRecord) -> String {
        exam.course.isEmpty ? (exam.name.isEmpty ? "考试" : exam.name) : exam.course
    }

    private func dateText(_ key: String, format: String) -> String {
        guard let date = Self.parser.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter.string(from: date)
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
                    DiagnosticExportButton(filenamePrefix: "XATune-exam-diagnostics") {
                        """
                        ===== 外壳 stdExamTable.action =====
                        \(shell)

                        ===== 考试表 stdExamTable!examTable.action =====
                        \(raw)
                        """
                    }

                    Text(summary(of: raw))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("可导出诊断文件给开发者排查页面解析问题。")
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

    private func examDetails(_ exam: ExamRecord, pending: Bool = false, countdown: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(courseTitle(exam)).font(.body.weight(.medium))
                    Spacer(minLength: 0)
                    if countdown {
                        Text(remainingText(for: exam)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(courseTitle(exam)).font(.body.weight(.medium))
                    if countdown {
                        Text(remainingText(for: exam)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if !subtitle(for: exam).isEmpty {
                Text(subtitle(for: exam)).font(.caption).foregroundStyle(.secondary)
            }
            if !exam.timeWithoutDate.isEmpty {
                Text(exam.timeWithoutDate).font(.subheadline).monospacedDigit()
            } else if pending {
                Text("考试时间待公布").font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(exam.room.isEmpty ? "考场待公布" : exam.room)
                    Spacer(minLength: 0)
                    Text(exam.seat.isEmpty ? "座位待公布" : "座位 \(exam.seat)")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(exam.room.isEmpty ? "考场待公布" : exam.room)
                    Text(exam.seat.isEmpty ? "座位待公布" : "座位 \(exam.seat)")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if !exam.note.isEmpty {
                Text(exam.note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// 课程序号在前、考试名称在后
    private func subtitle(for exam: ExamRecord) -> String {
        [exam.code, exam.name]
            .filter { !$0.isEmpty && $0 != exam.course }
            .joined(separator: " · ")
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
        if days == 1 { return "明天" }
        if days > 1 { return "\(days)天后" }
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
        showsCompleted = false
        app.exams = []
        Task { await app.refreshExams(semesterID: id) }
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
