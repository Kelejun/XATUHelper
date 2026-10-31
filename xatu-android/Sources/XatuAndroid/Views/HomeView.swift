import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {

    @Environment(AppState.self) var app
    @State var now = Date()
    @State var calendarInfo: CalendarService.Info?
    @State var destination: HomeDestination?

    enum HomeDestination: Hashable {
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
        return app.courseBlocks(in: app.week(of: baseDate))
            .filter { $0.day == todayWeekday }
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
        return app.courseBlocks(in: week)
            .filter { $0.day == weekday }
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
        44
    }

    private func isoWeekday(of date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    // MARK: - 放假/开学

    struct HolidayEvent {
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
                    .font(MD3Type.titleMedium)
                    .lineLimit(1)
                Text(event.days == 0 ? "今天" : "\(event.days) 天")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.teal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(event.dateText)
                    .font(MD3Type.caption)
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
                LazyVStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(greeting).font(MD3Type.headline)
                        Text(statusLine).font(MD3Type.bodyMedium).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    if let exam = nextExam { examCard(exam).md3Card() }
                    scheduleCard.md3Card(prominent: true)
                    HStack(alignment: .top, spacing: 16) {
                        electricityCard.frame(maxWidth: .infinity, alignment: .leading).md3Card()
                        if let holiday = nextHoliday {
                            holidayCard(holiday).frame(maxWidth: .infinity, alignment: .leading).md3Card()
                        }
                    }
                }
                .padding(16)
            }
            .md3Screen()
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $destination) { dest in
                switch dest {
                case .electricity: ElectricityView()
                case .calendar: SchoolCalendarView()
                }
            }
        }
        .task {
            calendarInfo = CalendarCache.load()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { break }
                now = Date()
            }
        }
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
                    .font(MD3Type.titleMedium)
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
            .font(MD3Type.bodyMedium)
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
                    .font(MD3Type.titleMedium)
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
                    .font(MD3Type.bodyMedium)
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
                        .font(MD3Type.titleMedium)
                    if app.electricityLoading {
                        ProgressView()
                    }
                }

                if let balance = app.electricityBalance {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("¥")
                            .font(MD3Type.bodyMedium)
                            .foregroundStyle(.secondary)
                        Text(balance)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(app.isLowBalance ? Color.orange : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(electricityCaption)
                        .font(MD3Type.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if app.dorm == nil {
                    Text("还没选宿舍")
                        .font(MD3Type.bodyMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(app.electricityError == nil ? "还没查到" : "查询失败")
                        .font(MD3Type.bodyMedium)
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
                        .font(MD3Type.bodyMedium)
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
            .font(MD3Type.bodyMedium)
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


#if !os(Android)
#Preview {
    HomeView()
        .environment(AppState())
}
#endif
