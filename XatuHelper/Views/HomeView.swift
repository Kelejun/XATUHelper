import SwiftUI
import UIKit

struct HomeView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.campusNavigation) private var navigate
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var now = Date()
    @State private var calendarInfo: CalendarService.Info?
    @State private var destination: HomeDestination?
    @State private var showsGreeting = false
    @State private var showsContent = false

    private enum HomeDestination: Hashable {
        case electricity
        case calendar
        case exam
    }

    private var usesWorkspace: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    private func openHomePage(_ page: CampusPage) {
        if usesWorkspace {
            navigate?(page)
        } else {
            switch page {
            case .electricity: destination = .electricity
            case .calendar: destination = .calendar
            case .exam: destination = .exam
            default: navigate?(page)
            }
        }
    }

    // MARK: - 问候语

    /// 按时间段换问候语。分界点：5:00 早起、11:30 午饭、13:30 下午、18:00 晚上、22:30 晚安。
    private var greeting: String {
        CampusGreeting.text(at: now)
    }

    private var nowMinutes: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - 今天的课

    /// 卡片按哪一天算。零点一过就算新的一天
    private var baseDate: Date { now }

    /// 周一 = 1 … 周日 = 7
    private var todayWeekday: Int { isoWeekday(of: baseDate) }

    private var todayBlocks: [CourseBlock] {
        guard app.isCurrentSemester else { return [] }
        return app.occurrences(in: app.week(of: baseDate))
            .filter { $0.day == todayWeekday }
            .courseBlocks()
            .sorted { $0.startPeriod < $1.startPeriod }
    }

    /// 这会儿正在上的课（深夜不算，那天已经过完了）
    private var currentBlock: CourseBlock? {
        todayBlocks.first {
            PeriodSchedule.startMinutes(of: $0) <= nowMinutes
                && nowMinutes < PeriodSchedule.endMinutes(of: $0)
        }
    }

    /// 还没开始的课
    private var remainingToday: [CourseBlock] {
        todayBlocks.filter { PeriodSchedule.startMinutes(of: $0) > nowMinutes }
    }

    /// 今天没有正在上的、也没有剩下的，就翻到明天
    private var showingTomorrow: Bool {
        currentBlock == nil && remainingToday.isEmpty
    }

    /// 从卡片基准日往后推一天。深夜时基准日还是昨天，推出来就是刚到的今天
    private var nextDay: Date? {
        Calendar.current.date(byAdding: .day, value: 1, to: baseDate)
    }

    private var tomorrowBlocks: [CourseBlock] {
        guard app.isCurrentSemester, let nextDay else { return [] }
        let weekday = isoWeekday(of: nextDay)
        let week = app.week(of: nextDay)
        return app.occurrences(in: week)
            .filter { $0.day == weekday }
            .courseBlocks()
            .sorted { $0.startPeriod < $1.startPeriod }
    }

    private var tomorrowWeekdayLabel: String {
        guard let nextDay else { return "" }
        return "周" + weekdayNames[isoWeekday(of: nextDay) - 1]
    }

    private var todayWeekdayLabel: String { "周" + weekdayNames[todayWeekday - 1] }

    private let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    private func isoWeekday(of date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    // MARK: - 放假/开学

    private struct HolidayEvent {
        let title: String
        let date: Date
        let dateText: String
        let days: Int
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayTextFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()

    /// 校历里缓存的下一个「开学 / 放假」
    private var nextHoliday: HolidayEvent? {
        guard let info = calendarInfo, !info.semesters.isEmpty else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        var candidates: [(String, Date)] = []

        for (index, span) in info.semesters.enumerated() {
            if let start = Self.dayKeyFormatter.date(from: span.start) {
                candidates.append(("\(span.label)开学", start))
            }
            if index < info.semesters.count - 1,
               let end = Self.dayKeyFormatter.date(from: span.end),
               let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: end) {
                candidates.append((index == 0 ? "放寒假" : "放暑假", dayAfter))
            }
        }
        if let last = info.semesters.last, let end = Self.dayKeyFormatter.date(from: last.end),
           let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: end) {
            candidates.append(("放暑假", dayAfter))
        }

        return candidates
            .filter { $0.1 >= today }
            .sorted { $0.1 < $1.1 }
            .first
            .map { title, date in
                HolidayEvent(
                    title: title,
                    date: date,
                    dateText: Self.dayTextFormatter.string(from: date),
                    days: Calendar.current.dateComponents([.day], from: today, to: date).day ?? 0
                )
            }
    }

    private func holidayCard(_ event: HolidayEvent) -> some View {
        Button {
            openHomePage(.calendar)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(event.title)还有")
                    .font(.headline)
                    .lineLimit(1)
                Text(event.days == 0 ? "今天" : "\(event.days) 天")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.teal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(event.dateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - 视图

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                homeOverview(width: proxy.size.width, height: proxy.size.height)
            }
            .background {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                    homeBackground
                }
                .ignoresSafeArea()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .campusSidebarToolbar()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $destination) { dest in
                switch dest {
                case .electricity: ElectricityView()
                case .calendar: SchoolCalendarView()
                case .exam: ExamView()
                }
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .onAppear { calendarInfo = CalendarCache.load() }
        .task {
            guard !app.hasPlayedIntro else {
                showsGreeting = true
                showsContent = true
                return
            }
            app.hasPlayedIntro = true
            withAnimation(.smooth(duration: 0.8)) { showsGreeting = true }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.smooth(duration: 0.8)) { showsContent = true }
        }
    }

    // MARK: - 首页

    private func homeOverview(width: CGFloat, height: CGFloat) -> some View {
        let wide = width >= 740 && !dynamicTypeSize.isAccessibilitySize
        let layout = wide
            ? AnyLayout(AlignedHomeColumns())
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showsGreeting {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(greeting)
                            .font(.largeTitle.bold())
                        Text(statusLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.offset(y: 40).combined(with: .opacity))
                }

                if showsContent {
                    layout {
                        scheduleOverview(fillHeight: wide)
                            .overviewPanel(fillHeight: wide)

                        supportingCards(fillHeight: wide)

                    }
                    .transition(.offset(y: 40).combined(with: .opacity))

                    if let fetchedAt = app.fetchedAt {
                        Label("课表更新于 \(fetchedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(width >= 600 ? 28 : 20)
            .padding(.top, height < 500 ? 24 : 100)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func supportingCards(fillHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if !usesWorkspace && !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 12) {
                    electricityCard.overviewPanel(fillHeight: true)
                    if let holiday = nextHoliday {
                        holidayCard(holiday).overviewPanel(fillHeight: true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                examOverview(fillHeight: false)
            } else {
                electricityCard.overviewPanel(fillHeight: fillHeight)
                examOverview(fillHeight: fillHeight)
                if let holiday = nextHoliday {
                    holidayCard(holiday).overviewPanel(fillHeight: fillHeight)
                }
            }
        }
    }

    @ViewBuilder
    private func examOverview(fillHeight: Bool) -> some View {
        if let exam = nextExam {
            Button { openHomePage(.exam) } label: {
                examCard(exam)
            }
            .buttonStyle(.plain)
            .overviewPanel(fillHeight: fillHeight)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("考试安排").font(.headline)
                Text("暂无待考科目").font(.subheadline).foregroundStyle(.secondary)
                Button("查看全部考试") { openHomePage(.exam) }
                    .font(.subheadline)
            }
            .overviewPanel(fillHeight: fillHeight)
        }
    }

    private var scheduleTitle: String {
        if showingTomorrow {
            return tomorrowBlocks.isEmpty ? "明天没有课，好好休息下吧" : "明天要上这些课："
        }
        if currentBlock != nil { return "今天还有这些课：" }
        return remainingToday.count == todayBlocks.count ? "今天要上这些课：" : "今天还有这些课："
    }

    private func scheduleOverview(fillHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(scheduleTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(showingTomorrow ? tomorrowWeekdayLabel : todayWeekdayLabel)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()

            let displayed = showingTomorrow ? tomorrowBlocks : todayBlocks.filter { PeriodSchedule.endMinutes(of: $0) > nowMinutes }
            if displayed.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sun.horizon")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.teal)
                        .frame(width: 60, height: 60)
                        .background(Color.teal.opacity(0.08), in: Circle())
                    Text("明天没有课程安排").font(.headline)
                    Text("本周的其他课程可在课程表中查看")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                ForEach(displayed) { block in
                    courseOverviewRow(block)
                    if block.id != displayed.last?.id { Divider() }
                }
            }

            if fillHeight {
                Spacer(minLength: 0)
            }

            Button { openHomePage(.timetable) } label: {
                HStack {
                    Text("查看完整课表")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    private func courseOverviewRow(_ block: CourseBlock) -> some View {
        let tint = CoursePalette.color(for: block)
        let active = !showingTomorrow && currentBlock?.id == block.id
        let next = !showingTomorrow && currentBlock == nil && remainingToday.first?.id == block.id
        let badge: String? = active ? "正在上" : next ? "下一节" : nil

        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(PeriodSchedule.isJiaoSanEarly(block) ? "10:10" : PeriodSchedule.startTime(block.startPeriod))
                    .font(.headline)
                Text(PeriodSchedule.isJiaoSanEarly(block) ? "11:40" : PeriodSchedule.endTime(block.endPeriod))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(width: 54, alignment: .leading)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(block.name).font(.headline)
                    if !block.room.isEmpty {
                        Label(block.shortRoom, systemImage: "mappin.and.ellipse")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !block.teacher.isEmpty {
                        Text(block.teacher).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.15), in: Capsule())
                        .fixedSize()
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(badge == nil ? Color.clear : tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    /// 顶部那片浅蓝渐变，往下化到页面底色，跟健康 App 的摘要页一个意思
    private var homeBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.16, green: 0.44, blue: 0.94).opacity(0.34), location: 0),
                .init(color: Color(red: 0.40, green: 0.66, blue: 0.98).opacity(0.16), location: 0.55),
                .init(color: Color(.systemGroupedBackground).opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    // MARK: - 顶部那行状态

    /// 第 N 周 · 今天还有 2 节课 · 下次考试还有 6 天
    private var statusLine: String {
        var parts: [String] = []
        if app.isCurrentSemester, app.currentWeek > 0 {
            parts.append("第 \(app.currentWeek) 周")
        }
        if remainingCount == 0 {
            parts.append("今天没课了")
        } else {
            parts.append("今天还有 \(remainingCount) 节课")
        }
        if let exam = nextExam, let days = daysUntil(exam) {
            parts.append(days <= 0 ? "今天有考试" : "下次考试还有 \(days) 天")
        }
        return parts.joined(separator: " · ")
    }

    private var remainingCount: Int {
        remainingToday.count + (currentBlock == nil ? 0 : 1)
    }

    private var nextExam: ExamRecord? {
        Self.examCandidates(app.exams, from: now).first
    }

    private func daysUntil(_ exam: ExamRecord) -> Int? {
        guard let date = Self.examDateFormatter.date(from: exam.dateKey) else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        return Calendar.current.dateComponents([.day], from: today, to: date).day
    }

    /// 今天及以后的考试，按日期升序
    static func examCandidates(_ exams: [ExamRecord], from now: Date) -> [ExamRecord] {
        let today = Calendar.current.startOfDay(for: now)
        return exams
            .compactMap { exam -> (ExamRecord, Date)? in
                guard let date = examDateFormatter.date(from: exam.dateKey) else { return nil }
                return date >= today ? (exam, date) : nil
            }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    private static let examDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private func examCard(_ exam: ExamRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("下一场考试")
                    .font(.headline)
                Spacer(minLength: 8)
                if let days = daysUntil(exam) {
                    Text(days <= 0 ? "今天" : "还有 \(days) 天")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.orange)
                }
            }

            Text(exam.course)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                if !exam.time.isEmpty {
                    Text(exam.time)
                }
                HStack(spacing: 6) {
                    if !exam.room.isEmpty { Text(exam.room) }
                    if !exam.seat.isEmpty {
                        if !exam.room.isEmpty { Text("·") }
                        Text("座位 \(exam.seat)")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// 电费卡片：余额低于 10 度变黄
    private var electricityCard: some View {
        Button {
            openHomePage(.electricity)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("剩余电量")
                        .font(.headline)
                    if app.electricityLoading {
                        ProgressView().controlSize(.mini)
                    }
                }

                if let balance = app.electricityBalance {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(balance)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(app.isLowBalance ? Color.orange : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("度")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(electricityCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if app.dorm == nil {
                    Text("还没选宿舍")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(app.electricityError == nil ? "还没查到" : "查询失败")
                        .font(.caption)
                        .foregroundStyle(app.electricityError == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var electricityCaption: String {
        var parts: [String] = []
        if let dorm = app.dorm { parts.append(dorm.buildName.isEmpty ? dorm.roomName : dorm.buildName) }
        if let checked = app.electricityCheckedAt {
            parts.append(checked.formatted(date: .omitted, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }


}


#Preview {
    HomeView()
        .environmentObject(AppState())
}

/// 统一的卡片外观，跟课程表那边一套
private extension View {
    func overviewPanel(fillHeight: Bool = false) -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

}

/// 两列使用各自的自然高度测量，再共同填充较高的一列，保持卡片组上下对齐。
private struct AlignedHomeColumns: Layout {
    private let spacing: CGFloat = 20

    private func widths(_ width: CGFloat) -> (main: CGFloat, secondary: CGFloat) {
        let secondary = min(260, width * 0.35)
        return (max(0, width - secondary - spacing), secondary)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        let columns = widths(width)
        let main = subviews[0].sizeThatFits(ProposedViewSize(width: columns.main, height: nil))
        let secondary = subviews[1].sizeThatFits(ProposedViewSize(width: columns.secondary, height: nil))
        return CGSize(width: width, height: max(main.height, secondary.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = widths(bounds.width)
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: columns.main, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + columns.main + spacing, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: columns.secondary, height: bounds.height))
    }
}
