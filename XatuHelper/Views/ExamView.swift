import SwiftUI

/// 考试安排。数据来自教务「我的考试」，按日期分组排。
struct ExamView: View {
    @EnvironmentObject var app: AppState

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
        let grouped = Dictionary(grouping: app.exams) { $0.dateKey }
        return grouped
            .map { (key: $0.key, items: $0.value.sorted { $0.time < $1.time }) }
            .sorted { lhs, rhs in
                // 认不出日期的排最后
                switch (lhs.key.isEmpty, rhs.key.isEmpty) {
                case (false, false): return lhs.key < rhs.key
                case (false, true): return true
                case (true, false): return false
                default: return false
                }
            }
    }

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
            } else {
                ForEach(groups, id: \.key) { group in
                    Section {
                        ForEach(group.items) { exam in
                            row(exam)
                        }
                    } header: {
                        Text(headerText(for: group.key, count: group.items.count))
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

    private func row(_ exam: ExamRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exam.course.isEmpty ? (exam.name.isEmpty ? "考试" : exam.name) : exam.course)
                .font(.body.weight(.medium))

            if !exam.name.isEmpty && exam.name != exam.course {
                Text(exam.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !exam.time.isEmpty {
                    Label(exam.time, systemImage: "clock")
                }
                if !exam.room.isEmpty {
                    Label(exam.room, systemImage: "mappin.and.ellipse")
                }
                if !exam.seat.isEmpty {
                    Label("座位 \(exam.seat)", systemImage: "chair.lounge")
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
        .padding(.vertical, 2)
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
