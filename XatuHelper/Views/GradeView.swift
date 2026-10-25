import SwiftUI
import UIKit

/// 成绩页。左边课名，右边「成绩 / 绩点」，点开看分项。
struct GradeView: View {
    @EnvironmentObject var app: AppState

    /// 空表示跟当前学期走
    @State private var semesterID = ""
    @State private var expanded: Set<String> = []
    @State private var searchText = ""

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
                        guard scope != app.gradeScope else { return }
                        expanded = []
                        app.grades = []
                        Task { await app.refreshGrades(semesterID: effectiveSemesterID, scope: scope) }
                    }
                )) {
                    ForEach(GradeScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
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
                    ForEach(filteredGrades) { grade in
                        gradeRow(grade)
                    }
                } footer: {
                    Text(filteredGrades.isEmpty ? "没搜到这门课" : "点开一门课可以看各分项得分")
                }
            }
        }
        .navigationTitle("成绩")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索课程名称")
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
                .disabled(app.semesters.isEmpty || app.gradeScope == .all)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await app.refreshGrades(semesterID: effectiveSemesterID, scope: app.gradeScope) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(app.gradesLoading)
            }
        }
        .task {
            if app.grades.isEmpty {
                await app.refreshGrades(semesterID: effectiveSemesterID, scope: app.gradeScope)
            }
        }
    }

    private func gradeRow(_ grade: GradeRecord) -> some View {
        let isOpen = expanded.contains(grade.id)

        let label = HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(grade.course.isEmpty ? "课程" : grade.course)
                    .font(.body.weight(.medium))
                if !grade.subtitle.isEmpty {
                    Text(grade.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(grade.headline)
                    .font(.callout.weight(.semibold))
                Text("成绩 / 绩点")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        // 没有分项就老老实实一行，别给人一个点开是空的箭头
        guard !grade.components.isEmpty else { return AnyView(label) }

        return AnyView(
            DisclosureGroup(isExpanded: Binding(
                get: { isOpen },
                set: { open in
                    if open { expanded.insert(grade.id) } else { expanded.remove(grade.id) }
                }
            )) {
                ForEach(grade.components) { component in
                    HStack {
                        Text(component.name)
                        Spacer(minLength: 8)
                        Text(component.score)
                    }
                    .font(.callout)
                }
            } label: {
                label
            }
        )
    }

    /// 空列表时给现场信息，方便判断是没出分还是没解析出来
    @ViewBuilder
    private var debugSection: some View {
        let raw = EamsService.lastGradeRaw
        Section {
            Text("接口返回 \(raw.count) 个字符")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !raw.isEmpty {
                Button {
                    UIPasteboard.general.string = raw
                } label: {
                    Label("复制原始返回", systemImage: "doc.on.doc")
                }
            }
        } header: {
            Text("排查")
        } footer: {
            Text("复制出来发给我，就能对上真实的页面结构。")
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
