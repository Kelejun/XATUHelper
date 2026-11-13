import SwiftUI
import UIKit

/// 成绩概览与课程分项。
struct GradeView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("showDiagnostics") private var showDiagnostics = false

    /// 空表示跟当前学期走
    @State private var semesterID = ""
    @State private var expanded: Set<String> = []
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var overviewTitle: String {
        app.gradeScope == .all ? "全部学期" : (selectedSemester?.name ?? "学期成绩")
    }

    private var filteredGrades: [GradeRecord] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return app.grades }
        return app.grades.filter {
            $0.course.localizedCaseInsensitiveContains(keyword)
                || $0.code.localizedCaseInsensitiveContains(keyword)
        }
    }

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

    var body: some View {
        List {
            Section {
                Picker("范围", selection: Binding(
                    get: { app.gradeScope },
                    set: { scope in
                        guard scope != app.gradeScope, !app.gradesLoading else { return }
                        expanded = []
                        app.gradeScope = scope
                        guard !app.isDemoMode else { return }
                        app.grades = []
                        Task { await app.refreshGrades(semesterID: effectiveSemesterID, scope: scope) }
                    }
                )) {
                    ForEach(GradeScope.allCases) { scope in
                        Text(scope == .current ? "学期成绩" : "全部成绩").tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(app.gradesLoading)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }
            .listSectionSpacing(.custom(12))

            if !app.grades.isEmpty && !isSearching {
                overview
            }

            if let error = app.gradesError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if app.grades.isEmpty {
                if app.gradesLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在查成绩…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if app.gradesError == nil {
                    Section {
                        ContentUnavailableView(
                            "还没有成绩",
                            systemImage: "chart.bar.doc.horizontal",
                            description: Text("出成绩后会出现在这里")
                        )
                    }
                    debugSection
                }
            } else {
                Section {
                    if filteredGrades.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ForEach(filteredGrades) { grade in
                            gradeRow(grade)
                        }
                    }
                } header: {
                    HStack {
                        Text(isSearching ? "搜索结果" : "课程成绩")
                        Spacer()
                        Text("\(filteredGrades.count) 门").monospacedDigit()
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("成绩")
        .navigationBarTitleDisplayMode(.large)
        .modifier(CourseNativeSearch(text: $searchText))
        .modifier(CourseSearchToolbarBehavior())
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await app.refreshGrades(semesterID: effectiveSemesterID, scope: app.gradeScope) }
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
                .accessibilityLabel("切换学期")
                .disabled(app.semesters.isEmpty || app.gradeScope == .all || app.gradesLoading)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await app.refreshGrades(semesterID: effectiveSemesterID, scope: app.gradeScope) }
                } label: {
                    if app.gradesLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel("刷新成绩")
                .disabled(app.gradesLoading)
            }
        }
        .task {
            if !app.hasGradeContext(effectiveSemesterID) || app.isStale(.grades) {
                await app.refreshGrades(semesterID: effectiveSemesterID, scope: app.gradeScope)
            }
        }
    }

    // MARK: - 统计

    /// 教务页面自己带着汇总就用它的，算不出来才退回本地计算
    private var hasPageSummary: Bool {
        !(app.gradeSummary?.isEmpty ?? true)
    }

    private var displayCount: String {
        if let count = app.gradeSummary?.count { return "\(count)" }
        return "\(stats.count)"
    }

    private var displayCredits: String {
        if let credits = app.gradeSummary?.credits {
            return credits == credits.rounded() ? "\(Int(credits))" : String(format: "%.1f", credits)
        }
        return stats.creditsText
    }

    private var displayGPA: String {
        if let gpa = app.gradeSummary?.gpa { return String(format: "%.2f", gpa) }
        return stats.gpaText
    }

    private var stats: GradeStats {
        var credits = 0.0
        var weighted = 0.0
        var weight = 0.0
        var plain = 0.0
        var plainCount = 0

        for record in app.grades {
            let credit = Double(record.credit.trimmingCharacters(in: .whitespaces)) ?? 0
            credits += credit
            guard let gpa = Double(record.gpa.trimmingCharacters(in: .whitespaces)) else { continue }
            plain += gpa
            plainCount += 1
            if credit > 0 {
                weighted += gpa * credit
                weight += credit
            }
        }

        let average: Double?
        if weight > 0 {
            average = weighted / weight
        } else if plainCount > 0 {
            average = plain / Double(plainCount)
        } else {
            average = nil
        }

        return GradeStats(count: app.grades.count, credits: credits, averageGPA: average)
    }

    private struct GradeStats {
        var count: Int
        var credits: Double
        var averageGPA: Double?

        var creditsText: String {
            credits == credits.rounded() ? "\(Int(credits))" : String(format: "%.1f", credits)
        }

        var gpaText: String {
            guard let averageGPA else { return "-" }
            return String(format: "%.2f", averageGPA)
        }
    }

    private var overview: some View {
        let tint: Color = .purple
        return Section {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Text(overviewTitle)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 48, height: 48)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("平均绩点")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(tint)
                    Text(displayGPA)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
                .accessibilityElement(children: .combine)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    overviewMetric("课程", value: "\(displayCount) 门")
                    Spacer(minLength: 0)
                    overviewMetric("总学分", value: displayCredits)
                }
            }
            .padding(.vertical, 8)
            .listRowBackground(
                LinearGradient(colors: [tint.opacity(0.09), Color(uiColor: .secondarySystemGroupedBackground)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        } footer: {
            Text(hasPageSummary ? "数据取自教务页面" : "平均绩点按学分加权")
        }
    }

    private func overviewMetric(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func gradeRow(_ grade: GradeRecord) -> some View {
        if grade.components.isEmpty {
            gradeLabel(grade)
        } else {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded.contains(grade.id) },
                set: { open in
                    if open { expanded.insert(grade.id) } else { expanded.remove(grade.id) }
                }
            )) {
                if !grade.code.isEmpty {
                    gradeDetail("课程序号", value: grade.code)
                }
                ForEach(grade.components) { component in
                    gradeDetail(component.name, value: component.score)
                }
            } label: {
                gradeLabel(grade)
            }
            .tint(.purple)
        }
    }

    private func gradeLabel(_ grade: GradeRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(grade.course.isEmpty ? "课程" : grade.course)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                let subtitle = [grade.term, grade.credit.isEmpty ? "" : "\(grade.credit) 学分"]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Text(grade.score.isEmpty ? "—" : grade.score)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("绩点 \(grade.gpa.isEmpty ? "—" : grade.gpa)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func gradeDetail(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    /// 空列表时给现场信息，方便判断是没出分还是没解析出来
    @ViewBuilder
    private var debugSection: some View {
        let raw = EamsService.lastGradeRaw
        if showDiagnostics {
            Section {
                Text("接口返回 \(raw.count) 个字符")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !raw.isEmpty {
                    DiagnosticExportButton(filenamePrefix: "XATune-grade-diagnostics") { raw }
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("可导出诊断文件给开发者排查页面解析问题。")
            }
        }
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
        expanded = []
        guard !app.isDemoMode else { return }
        app.grades = []
        Task { await app.refreshGrades(semesterID: id, scope: .current) }
    }
}

#Preview {
    NavigationStack {
        GradeView()
            .environmentObject(AppState())
    }
}
