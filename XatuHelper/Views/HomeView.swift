import SwiftUI
import UIKit

struct HomeView: View {

    @EnvironmentObject var app: AppState
    @State private var now = Date()
    @State private var calendarInfo: CalendarService.Info?
    @State private var destination: HomeDestination?
    @State private var showsContent = false

    private enum HomeDestination: Hashable {
        case electricity
        case calendar
    }

    // MARK: - 问候语

    /// 按时间段换问候语。分界点：5:00 早起、11:30 午饭、13:30 下午、18:00 晚上、22:30 晚安。
    private var greeting: String {
        switch nowMinutes {
        case 300..<690: return "早，"
        case 690..<810: return "吃饭没？"
        case 810..<1080: return "下午好，"
        case 1080..<1350: return "晚上好，"
        default: return "晚安。"
        }
    }

    private var nowMinutes: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - 今天的课

    /// 深夜（0 点到 5 点）：只影响问候语和「早点睡吧」这一句，日期照常按零点翻篇
    private var isLateNight: Bool {
        Calendar.current.component(.hour, from: now) < 5
    }

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

    /// 大标题那一行的高度，用来给卡片让出位置（跟着动态字体缩放）
    private var titleHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .largeTitle).lineHeight
    }

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
        Button { destination = .calendar } label: {
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
ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear
                        .frame(height: 150)

                    Text(greeting)
                        .font(.largeTitle.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showsContent {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(statusLine)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let exam = nextExam {
                                examCard(exam)
                                    .cardStyle()
                            }

                            scheduleCard
                                .cardStyle()

                            HStack(alignment: .top, spacing: 12) {
                                electricityCard
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .cardStyle()
                                if let holiday = nextHoliday {
                                    holidayCard(holiday)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .cardStyle()
                                }
                            }
                        }
                        .transition(.offset(y: 40).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(alignment: .top) { homeBackground }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $destination) { dest in
                switch dest {
                case .electricity: ElectricityView()
                case .calendar: SchoolCalendarView()
                }
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .onAppear { calendarInfo = CalendarCache.load() }
        .task {
            guard !app.hasPlayedIntro else {
                showsContent = true
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.smooth(duration: 0.8)) { showsContent = true }
            app.hasPlayedIntro = true
        }
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
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - 顶部那行状态

    /// 第 N 周 · 今天还有 2 节 · 下次考试还有 6 天
    private var statusLine: String {
        var parts: [String] = []
        if app.isCurrentSemester, app.currentWeek > 0 {
            parts.append("第 \(app.currentWeek) 周")
        }
        if remainingCount == 0 {
            parts.append("今天没课了")
        } else {
            parts.append("今天还有 \(remainingCount) 节")
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

    /// 卡片标题：还没开课 / 上到一半 / 没课了翻明天 / 明天也没课
    private var cardTitle: String {
        if showingTomorrow {
            return tomorrowBlocks.isEmpty ? "明天没有课，好好休息下吧" : "明天要上这些课："
        }
        if currentBlock != nil { return "今天还有这些课：" }
        return remainingToday.count == todayBlocks.count ? "今天要上这些课：" : "今天还有这些课："
    }

    private var scheduleCard: some View {
        cardContent
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cardTitle)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(showingTomorrow ? tomorrowWeekdayLabel : todayWeekdayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if showingTomorrow {
                if !tomorrowBlocks.isEmpty {
                    ForEach(tomorrowBlocks) { row($0) }
                }
            } else {
                if let currentBlock {
                    highlightedRow(currentBlock, badge: "正在上")
                    ForEach(remainingToday) { row($0) }
                } else if let next = remainingToday.first {
                    highlightedRow(next, badge: "下一节")
                    ForEach(remainingToday.dropFirst()) { row($0) }
                }
            }

            if isLateNight {
                Text("早点睡吧，已经很晚了")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 电费卡片：余额低于 10 元变黄
    private var electricityCard: some View {
        Button { destination = .electricity } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("电费还剩")
                        .font(.headline)
                    if app.electricityLoading {
                        ProgressView().controlSize(.mini)
                    }
                }

                if let balance = app.electricityBalance {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("¥")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(balance)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(app.isLowBalance ? Color.orange : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
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

    private func row(_ block: CourseBlock) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timeText(block))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CoursePalette.color(for: block))
                .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.name)
                    .font(.subheadline)
                if !block.shortRoom.isEmpty {
                    Text(block.shortRoom)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func highlightedRow(_ block: CourseBlock, badge: String) -> some View {
        let tint = CoursePalette.color(for: block)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.15)))
                    .foregroundStyle(tint)
                Text(block.name)
                    .font(.subheadline.weight(.medium))
            }
            HStack(spacing: 8) {
                Text(timeText(block))
                if !block.shortRoom.isEmpty { Text(block.shortRoom) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private func timeText(_ block: CourseBlock) -> String {
        PeriodSchedule.range(for: block)
    }
}


#Preview {
    HomeView()
        .environmentObject(AppState())
}

/// 统一的卡片外观，跟课程表那边一套
private extension View {
    func cardStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
    }
}
