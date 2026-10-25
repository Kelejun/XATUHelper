import SwiftUI
import UIKit

struct TimetableView: View {

    @EnvironmentObject var app: AppState
    @State private var showSettings = false
    @State private var detail: CourseBlock?
    @AppStorage("hideWeekend") private var hideWeekend = false
    /// 横向翻页停在第几周，绑定 ScrollView 的 scrollPosition
    @State private var visibleWeek: Int?

    /// 0 表示"跟着今天走"。非当前学期没有"本周"，落到这学期第一门有课的周。
    private var week: Int {
        if let visibleWeek { return visibleWeek }
        return app.isCurrentSemester ? app.currentWeek : firstWeekWithCourses
    }

    /// 当前学期数据里最早出现课程的周
    private var firstWeekWithCourses: Int {
        let weeks = app.occurrences.flatMap { $0.weeks }
        return weeks.min() ?? 1
    }

    private static let weekRange = 1...30

    private func blocks(for target: Int) -> [CourseBlock] {
        app.occurrences(in: target).courseBlocks()
    }

    /// 表头上显示日期用。只有当前学期知道第一周的周一，往届学期不显示日期。
    private func mondayDate(for target: Int) -> Date? {
        guard app.isCurrentSemester else { return nil }
        return Calendar.current.date(byAdding: .day, value: (target - 1) * 7, to: app.semesterStartMonday)
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
            await app.selectSemester(target.id)
            jump(to: week, animated: false)
        }
    }

    private func selectTerm(_ term: String) {
        let target = app.semesters.first { $0.schoolYear == selectedYear && $0.termName == term }
            ?? app.semesters.first { $0.termName == term }
        guard let target, target.id != app.selectedSemesterID else { return }
        Task {
            await app.selectSemester(target.id)
            jump(to: week, animated: false)
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
                    await app.selectKind(kind)
                    jump(to: week, animated: false)
                }
            }
        )
    }

    // MARK: - 周视图翻页

    /// 系统的分页滚动：手势、惯性、边缘回弹都交给 ScrollView 自己管
    private func pager(width: CGFloat, height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Self.weekRange, id: \.self) { target in
                    weekPage(target, width: width)
                        .frame(width: width, height: height)
                        .id(target)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleWeek)
        .scrollIndicators(.hidden)
    }

    /// 点箭头、选周次时滚过去；不传动画就走系统的定位
    private func jump(to target: Int, animated: Bool = true) {
        let clamped = min(max(target, Self.weekRange.lowerBound), Self.weekRange.upperBound)
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { visibleWeek = clamped }
        } else {
            visibleWeek = clamped
        }
    }

    @ViewBuilder
    private func weekPage(_ target: Int, width: CGFloat) -> some View {
        let pageBlocks = blocks(for: target)
        if Self.weekRange.contains(target) {
            WeekGrid(
                blocks: pageBlocks,
                unitCount: app.unitCount,
                monday: mondayDate(for: target),
                showWeekend: !hideWeekend,
                onSelect: { detail = $0 }
            )
            .frame(width: width)
            .overlay {
                if app.isLoading && pageBlocks.isEmpty {
                    ProgressView()
                } else if !app.isLoading && pageBlocks.isEmpty {
                    ContentUnavailableView(
                        "这一周没有课",
                        systemImage: "calendar",
                        description: Text("翻到别的周看看，或者在设置里校正周次")
                    )
                }
            }
        } else {
            Color.clear.frame(width: width)
        }
    }


    var body: some View {
        NavigationStack {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
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

            GeometryReader { proxy in
                pager(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .onAppear {
            if visibleWeek == nil { visibleWeek = week }
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
                            Label("设置", systemImage: "gearshape")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await app.refresh()
                        jump(to: week, animated: false)
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
            TimetableSettingsSheet()
        }
        .task {
            await app.ensureShell()
            if app.occurrences.isEmpty {
                await app.refresh()
            } else if let fetchedAt = app.fetchedAt,
                      Date().timeIntervalSince(fetchedAt) > 144 * 3600 {
                await app.refresh()
            }
        }
    }

    private var weekBar: some View {
        HStack(spacing: 4) {
            Button {
                jump(to: week - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(week <= Self.weekRange.lowerBound)

            Menu {
                ForEach(Self.weekRange, id: \.self) { value in
                    Toggle("第 \(value) 周", isOn: Binding(
                        get: { value == week },
                        set: { on in
                            if on, value != week { jump(to: value) }
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
                jump(to: week + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(week >= Self.weekRange.upperBound)

            Spacer()

            if app.isCurrentSemester, week != app.currentWeek {
                Button("回到本周") { jump(to: app.currentWeek) }
                    .font(.footnote)
            } else if !app.isCurrentSemester {
                Button("回到现在") {
                    Task {
                        await app.selectSemester(app.currentSemesterID)
                        jump(to: app.currentWeek, animated: false)
                    }
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
    @AppStorage("showDiagnostics") private var showDiagnostics = false

    /// 1.0.0（1）
    static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short)（\(build)）"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账号") {
                    LabeledContent("学号", value: app.studentID.isEmpty ? "—" : app.studentID)
                    Button("退出登录", role: .destructive) {
                        app.logout()
                        dismiss()
                    }
                }

                Section {
                    Toggle("显示诊断数据", isOn: $showDiagnostics)
                } footer: {
                    Text("如果出现解析问题，可复制诊断信息给开发者处理")
                }

                Section {
                    LabeledContent("版本", value: Self.versionText)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

/// 课程表自己的设置：周次校正、隐藏周末、诊断数据都在这
struct TimetableSettingsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draftWeek = 1
    @AppStorage("hideWeekend") private var hideWeekend = false
    @AppStorage("showDiagnostics") private var showDiagnostics = false

    private static let weekRange = 1...30

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("现在实际是第几周", selection: $draftWeek) {
                        ForEach(Self.weekRange, id: \.self) { value in
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
                    if let fetchedAt = app.fetchedAt {
                        LabeledContent(
                            "上次更新",
                            value: fetchedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }

                if showDiagnostics {
                    Section {
                        Button("复制课表诊断数据") {
                            UIPasteboard.general.string = EamsService.diagnosticDump
                        }
                    } header: {
                        Text("诊断")
                    } footer: {
                        Text("把课表外壳页和学期接口的原始返回整个复制出来，学期列表不对时发给开发者。")
                    }
                }
            }
            .navigationTitle("课程表设置")
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
