import SwiftUI
import UIKit

struct TimetableView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.campusNavigation) private var navigate
    @State private var showSettings = false
    @State private var showNotificationSetup = false
    @State private var selection: TimetableSelection?
    @State private var showAddCourse = false
    @State private var showTimetableEdits = false
    @AppStorage("hideWeekend") private var hideWeekend = false
    /// 周次由主导航持有，折叠／展开重建布局时继续停留在所选周。
    @Binding var visibleWeek: Int?

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

    private static let weekRange = TimetableDates.weeks

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
    private func pager(width: CGFloat, height: CGFloat, visibleHeight: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Self.weekRange, id: \.self) { target in
                    weekPage(target, width: width, visibleHeight: visibleHeight)
                        .frame(width: width, height: height)
                        .id(target)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleWeek, anchor: .leading)
        .scrollIndicators(.hidden)
        // Duo 的系统侧栏会改变安全区；将分页视口限制在测量宽度内。
        .frame(width: width, height: height)
        .clipped()
        .id(width)
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
    private func weekPage(_ target: Int, width: CGFloat, visibleHeight: CGFloat) -> some View {
        let pageBlocks = blocks(for: target)
        if Self.weekRange.contains(target) {
            WeekGrid(
                blocks: pageBlocks,
                unitCount: app.unitCount,
                monday: mondayDate(for: target),
                showWeekend: !hideWeekend,
                visibleHeight: visibleHeight,
                onSelect: { selection = TimetableSelection(week: target, blocks: $0) }
            )
            .frame(width: width)
            .overlay(alignment: .top) {
                if pageBlocks.isEmpty {
                    Group {
                        if app.isLoading {
                            ProgressView()
                        } else {
                            ContentUnavailableView(
                                "这一周没有课",
                                systemImage: "calendar",
                                description: Text("翻到别的周看看，或者在设置里校正周次")
                            )
                        }
                    }
                    .frame(height: visibleHeight)
                }
            }
        } else {
            Color.clear.frame(width: width)
        }
    }


    var body: some View {
        NavigationStack {
            content
                .campusSidebarToolbar()
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

            GeometryReader { visible in
                GeometryReader { full in
                    pager(width: full.size.width, height: full.size.height, visibleHeight: visible.size.height)
                }
                .ignoresSafeArea(.container, edges: navigate == nil ? .bottom : [])
            }
        }
        // iPad 没有底部标签栏，让课表视口延伸到手势区底边，避免残留白条。
        .ignoresSafeArea(.container, edges: UIDevice.current.userInterfaceIdiom == .pad ? .bottom : [])
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
                        if app.canEditTimetable {
                            Button {
                                showTimetableEdits = true
                            } label: {
                                Label(app.pendingTimetableEdits.isEmpty ? "我的课表修改" : "我的课表修改 · 待确认",
                                      systemImage: "clock.arrow.circlepath")
                            }
                        }
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

            ToolbarItemGroup(placement: .topBarTrailing) {
                if app.canEditTimetable {
                    Button {
                        showAddCourse = true
                    } label: {
                        Label("添加课程", systemImage: "plus")
                    }
                }
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
        .sheet(item: $selection) { selection in
            CourseDetailSheet(selection: selection)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddCourse) {
            TimetableEditSheet(operation: .add, week: week)
        }
        .sheet(isPresented: $showTimetableEdits) {
            TimetableHistorySheet()
        }
        .sheet(isPresented: $showSettings) {
            TimetableSettingsSheet()
        }
        .sheet(isPresented: $showNotificationSetup) {
            NotificationSetupSheet()
        }
        .task {
            // 平时靠启动流程按有效期补；这里只在数据过期时兜一次
            if app.isStale(.timetable) {
                await app.refresh()
            }
            if !app.isDemoMode && !NotificationSettings.hasPrompted {
                showNotificationSetup = true
            }
        }
    }

    private var weekBar: some View {
        HStack(spacing: 4) {
            Button {
                jump(to: week - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(week <= Self.weekRange.lowerBound)
            .accessibilityLabel("上一周")

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
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(week >= Self.weekRange.upperBound)
            .accessibilityLabel("下一周")

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

struct TimetableSelection: Identifiable {
    let id = UUID()
    let week: Int
    let blocks: [CourseBlock]
}

struct CourseDetailSheet: View {
    let selection: TimetableSelection
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: TimetableEditSheet.Operation?

    var body: some View {
        NavigationStack {
            List {
                ForEach(selection.blocks) { selected in
                    let block = app.occurrences.courseBlocks().first {
                        $0.occurrenceIDs == selected.occurrenceIDs && $0.weeks.contains(selection.week)
                    } ?? selected
                    Section(block.name) {
                        LabeledContent("时间", value: "周\(block.weekdayLabel) \(block.periodText)")
                        LabeledContent("周次", value: block.weeksText)
                        LabeledContent("教室", value: block.room.isEmpty ? "—" : block.room)
                        LabeledContent("教师", value: block.teacher.isEmpty ? "—" : block.teacher)
                        if !block.courseKey.hasPrefix("local-"), !block.courseKey.isEmpty {
                            LabeledContent("课程号", value: block.courseKey)
                        }
                        if app.canEditTimetable {
                            Button("修改课程") { editMode = .move(block) }
                            Button(block.courseKey.hasPrefix("local-") ? "删除课程" : "从我的课表移除",
                                   role: .destructive) { editMode = .remove(block) }
                        }
                    }
                }
            }
            .navigationTitle(selection.blocks.count > 1 ? "课程冲突" : "课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $editMode) { mode in
                TimetableEditSheet(operation: mode, week: selection.week, onSaved: { dismiss() })
            }
        }
    }
}

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsContent()
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

/// 不带 NavigationStack 的总设置，课程表设置里也能跳进来
struct SettingsContent: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject private var announcements: AnnouncementCenter
    @State private var announcementBlocker = UUID()
    @State private var selectedAnnouncement: ReceivedAnnouncement?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showDiagnostics") private var showDiagnostics = false
    @AppStorage(CheckinLocationSettings.revealedKey) private var showCheckinLocation = false
    @State private var versionTapCount = 0

    /// 显示版本与构建时的 Git 提交。
    static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let commit = BuildInfo.commit.isEmpty || BuildInfo.commit == "dev" ? build : BuildInfo.commit
        return "\(short)（\(commit)）"
    }

    var body: some View {
        Form {
            Section("账号") {
                LabeledContent("学号", value: app.studentID.isEmpty ? "—" : app.studentID)
                Button("退出登录", role: .destructive) {
                    app.logout()
                    dismiss()
                }
            }

            AnnouncementSettingsSection { selectedAnnouncement = $0 }

            if !app.isDemoMode {
                ElectricityRefreshSettingsSection()
                ClassNotificationSection()
            }

            Section {
                NavigationLink("查看更多课程表设置...") {
                    TimetableSettingsContent()
                }
            }

            if !app.isDemoMode { ExamNotificationSection() }

            Section {
                Toggle("显示诊断数据", isOn: $showDiagnostics)
                if showDiagnostics {
                    Button("复制诊断数据") {
                        UIPasteboard.general.string = EamsService.diagnosticDump
                    }
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("如果出现解析问题，可复制诊断信息给开发者处理")
            }

            if showCheckinLocation {
                CheckinLocationSettingsSection()
            }

            Section {
                Button {
                    versionTapCount += 1
                    if versionTapCount >= 5 {
                        showCheckinLocation = true
                        versionTapCount = 0
                    }
                } label: {
                    LabeledContent("版本", value: Self.versionText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                PrivacyPolicyLink()
                Link(destination: URL(string: "https://github.com/Kelejun/XATUHelper")!) {
                    LabeledContent("GitHub 仓库", value: "Kelejun/XATUHelper")
                }
            } header: {
                Text("App")
            } footer: {
                if !BuildInfo.builtAt.isEmpty {
                    Text("构建于 \(BuildInfo.builtAt)")
                }
            }
        }
        .sheet(item: $selectedAnnouncement) { record in
            AnnouncementDetailView(announcement: record.announcement, receivedAt: record.receivedAt) {
                announcements.acknowledge(record)
                selectedAnnouncement = nil
            }
        }
        .onAppear { announcements.presentationBlockers.insert(announcementBlocker) }
        .onDisappear { announcements.presentationBlockers.remove(announcementBlocker) }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 课程表自己的设置：周次校正、隐藏周末、诊断数据都在这
struct TimetableSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimetableSettingsContent()
                .navigationTitle("课程表设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}

/// 抽出来一份不带 NavigationStack 的，总设置里也能跳进来
struct TimetableSettingsContent: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draftWeek = 1
    @AppStorage("hideWeekend") private var hideWeekend = false
    @AppStorage("showDiagnostics") private var showDiagnostics = false

    private static let weekRange = TimetableDates.weeks

    var body: some View {
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

            Section {
                NavigationLink("查看课程表通知设置...") {
                    SettingsContent()
                }
            } header: {
                Text("通知")
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
        }
        .navigationTitle("课程表设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draftWeek = app.currentWeek
        }
    }
}
