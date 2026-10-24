import SwiftUI
import UIKit

struct TimetableView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedWeek = 0
    @State private var showSettings = false
    @State private var detail: CourseBlock?
    @AppStorage("hideWeekend") private var hideWeekend = false

    /// 0 表示"跟着今天走"。非当前学期没有"本周"，落到这学期第一门有课的周。
    private var week: Int {
        if selectedWeek != 0 { return selectedWeek }
        return app.isCurrentSemester ? app.currentWeek : firstWeekWithCourses
    }

    /// 当前学期数据里最早出现课程的周
    private var firstWeekWithCourses: Int {
        let weeks = app.occurrences.flatMap { $0.weeks }
        return weeks.min() ?? 1
    }

    /// 左右滑动切前后周，边界卡在 1...30
    private func stepWeek(_ delta: Int) {
        let target = min(max(week + delta, 1), 30)
        guard target != week else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedWeek = target
        }
    }

    private var blocks: [CourseBlock] {
        app.occurrences(in: week).courseBlocks()
    }

    /// 表头上显示日期用。只有当前学期知道第一周的周一，往届学期不显示日期。
    private var mondayDate: Date? {
        guard app.isCurrentSemester else { return nil }
        return Calendar.current.date(byAdding: .day, value: (week - 1) * 7, to: app.semesterStartMonday)
    }

    // MARK: - 学年 / 学期拆成两个一级菜单

    private var selectedSemester: Semester? {
        app.semesters.first { $0.id == app.selectedSemesterID }
    }

    private var selectedYear: String { selectedSemester?.schoolYear ?? "" }
    private var selectedTerm: String { selectedSemester?.termName ?? "" }

    private var years: [String] {
        Array(Set(app.semesters.compactMap { $0.schoolYear })).sorted(by: >)
    }

    /// 只列当前学年真实存在的学期
    private var terms: [String] {
        let names = Set(app.semesters
            .filter { $0.schoolYear == selectedYear }
            .compactMap { $0.termName })
        let ordered = ["1学期", "2学期"].filter { names.contains($0) }
        return ordered + names.subtracting(ordered).sorted()
    }

    private func selectYear(_ year: String) {
        let candidates = app.semesters.filter { $0.schoolYear == year }
        guard !candidates.isEmpty else { return }
        let target = candidates.first { $0.termName == selectedTerm }
            ?? candidates.min { $0.id < $1.id }
        guard let target, target.id != app.selectedSemesterID else { return }
        Task {
            selectedWeek = 0
            await app.selectSemester(target.id)
        }
    }

    private func selectTerm(_ term: String) {
        let target = app.semesters.first { $0.schoolYear == selectedYear && $0.termName == term }
            ?? app.semesters.first { $0.termName == term }
        guard let target, target.id != app.selectedSemesterID else { return }
        Task {
            selectedWeek = 0
            await app.selectSemester(target.id)
        }
    }

    private func isYearOn(_ year: String) -> Binding<Bool> {
        Binding(
            get: { year == selectedYear },
            set: { on in if on { selectYear(year) } }
        )
    }

    private func isTermOn(_ term: String) -> Binding<Bool> {
        Binding(
            get: { term == selectedTerm },
            set: { on in if on { selectTerm(term) } }
        )
    }

    private func isKindOn(_ kind: TableKind) -> Binding<Bool> {
        Binding(
            get: { kind == app.kind },
            set: { on in
                guard on, kind != app.kind else { return }
                Task {
                    selectedWeek = 0
                    await app.selectKind(kind)
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekBar

                if let message = app.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }

                WeekGrid(
                    blocks: blocks,
                    unitCount: app.unitCount,
                    monday: mondayDate,
                    showWeekend: !hideWeekend,
                    onSelect: { detail = $0 }
                )
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard abs(dx) > abs(dy) else { return }
                            if dx < -60 {
                                stepWeek(1)
                            } else if dx > 60 {
                                stepWeek(-1)
                            }
                        }
                )
                .overlay {
                    if app.isLoading && blocks.isEmpty {
                        ProgressView()
                    } else if !app.isLoading && blocks.isEmpty {
                        ContentUnavailableView(
                            "这一周没有课",
                            systemImage: "calendar",
                            description: Text("翻到别的周看看，或者在设置里校正周次")
                        )
                    }
                }
            }
            .navigationTitle(app.semesterName)
            .navigationBarTitleDisplayMode(.inline)
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

                        Menu("课表") {
                            ForEach(TableKind.allCases) { kind in
                                Toggle(kind.title, isOn: isKindOn(kind))
                            }
                        }

                        Section {
                            Button {
                                showSettings = true
                            } label: {
                                Label("设置", systemImage: "slider.horizontal.3")
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            selectedWeek = 0
                            await app.refresh()
                        }
                    } label: {
                        if app.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(app.isLoading)
                }
            }
            .sheet(item: $detail) { block in
                CourseDetailSheet(block: block)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .task {
                await app.ensureShell()
                if app.occurrences.isEmpty {
                    await app.refresh()
                } else if let fetchedAt = app.fetchedAt,
                          Date().timeIntervalSince(fetchedAt) > 6 * 3600 {
                    await app.refresh()
                }
            }
        }
    }

    private var weekBar: some View {
        HStack(spacing: 4) {
            Button {
                selectedWeek = max(1, week - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(week <= 1)

            Menu {
                ForEach(1...26, id: \.self) { value in
                    Toggle("第 \(value) 周", isOn: Binding(
                        get: { value == week },
                        set: { on in
                            if on, value != week { selectedWeek = value }
                        }
                    ))
                }
            } label: {
                HStack(spacing: 3) {
                    Text("第 \(week) 周")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .frame(minWidth: 84)
            }

            Button {
                selectedWeek = min(26, week + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(week >= 26)

            Spacer()

            if app.isCurrentSemester, selectedWeek != 0 {
                Button("回到本周") { selectedWeek = 0 }
                    .font(.footnote)
            } else if !app.isCurrentSemester {
                Button("回到现在") {
                    selectedWeek = 0
                    Task { await app.selectSemester(app.currentSemesterID) }
                }
                .font(.footnote)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct CourseDetailSheet: View {
    let block: CourseBlock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("时间", value: "周\(block.weekdayLabel) \(block.periodText)")
                    LabeledContent("周次", value: block.weeksText)
                    LabeledContent("教室", value: block.room.isEmpty ? "—" : block.room)
                    LabeledContent("教师", value: block.teacher.isEmpty ? "—" : block.teacher)
                } header: {
                    HStack(spacing: 6) {
                        Text(block.name)
                        if block.isRemote { Text("线上").font(.caption2) }
                        if block.isPlaceholder { Text("占位").font(.caption2) }
                    }
                }

                Section("课程") {
                    LabeledContent("课程号", value: block.courseKey.isEmpty ? "—" : block.courseKey)
                }
            }
            .navigationTitle(block.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draftWeek = 1
    @AppStorage("hideWeekend") private var hideWeekend = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("现在实际是第几周", selection: $draftWeek) {
                        ForEach(1...26, id: \.self) { value in
                            Text("第 \(value) 周").tag(value)
                        }
                    }
                    Button("按这个周次校正") {
                        app.calibrate(currentWeek: draftWeek)
                        dismiss()
                    }
                } header: {
                    Text("周次校正")
                } footer: {
                    Text("学校校历如果和默认的不一样，在这里改一次就行。")
                }

                Section("课表") {
                    Toggle("隐藏周末", isOn: $hideWeekend)
                }

                Section {
                    Button("复制诊断数据") {
                        UIPasteboard.general.string = EamsService.diagnosticDump
                    }
                } header: {
                    Text("诊断")
                } footer: {
                    Text("把课表外壳页和学期接口的原始返回整个复制出来，学期列表不对时发给开发者。")
                }

                Section("账号") {
                    LabeledContent("学号", value: app.studentID.isEmpty ? "—" : app.studentID)
                    LabeledContent("课表", value: app.kind.title)
                    if let fetchedAt = app.fetchedAt {
                        LabeledContent(
                            "上次更新",
                            value: fetchedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    Button("退出登录", role: .destructive) {
                        app.logout()
                        dismiss()
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                draftWeek = app.currentWeek
            }
        }
    }
}
