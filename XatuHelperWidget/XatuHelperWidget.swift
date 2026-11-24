import AppIntents
import SwiftUI
import UIKit
import WidgetKit

@main
struct XatuHelperWidgetBundle: WidgetBundle {
    var body: some Widget {
        CourseWidget()
        ElectricityWidget()
        BreakWidget()
        ExamWidget()
        CourseLiveActivityWidget()
    }
}

// MARK: - 数据

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    var preview: WidgetSnapshot
    var schedulesExamChanges = false

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let now = Date()
        let snapshot = WidgetStore.read() ?? (context.isPreview ? preview : .empty)
        completion(TodayEntry(date: now, snapshot: snapshot.resolved(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetStore.read() ?? .empty
        if schedulesExamChanges {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            let ends = snapshot.upcomingExams?.compactMap(\.end).filter { $0 > now && $0 < tomorrow } ?? []
            let entries = Set([now, tomorrow] + ends).sorted().map {
                TodayEntry(date: $0, snapshot: snapshot.resolved(at: $0))
            }
            completion(Timeline(entries: entries, policy: .atEnd))
            return
        }
        let entry = TodayEntry(date: now, snapshot: snapshot.resolved(at: now))
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

enum PreviewData {
    static let snapshot: WidgetSnapshot = {
        let courses = [
            WidgetSnapshot.Course(id: "1", name: "计算机网络", room: "教3-109",
                                  startMinutes: 8 * 60 + 20, endMinutes: 10 * 60),
            WidgetSnapshot.Course(id: "2", name: "计算机组成与体系结构", room: "教2-210",
                                  startMinutes: 14 * 60, endMinutes: 15 * 60 + 40)
        ]
        let exams = [
            WidgetSnapshot.Exam(title: "数据结构", date: Date().addingTimeInterval(7 * 86400),
                                days: 7, startTime: "09:00", room: "教3-402", seat: "28"),
            WidgetSnapshot.Exam(title: "大学英语", date: Date().addingTimeInterval(9 * 86400),
                                days: 9, startTime: "14:00"),
            WidgetSnapshot.Exam(title: "计算机网络", date: Date().addingTimeInterval(12 * 86400),
                                days: 12, startTime: "09:00")
        ]
        return WidgetSnapshot(
            generatedAt: Date(),
            week: 8,
            weekday: 3,
            courses: courses,
            balance: 52.77,
            balanceUpdatedAt: Date(),
            roomName: "320宿舍",
            upcomingBreak: WidgetSnapshot.Break(title: "放寒假",
                                                date: Date().addingTimeInterval(83 * 86400),
                                                days: 83),
            nextExam: exams.first, upcomingExams: exams,
            loggedIn: true
        )
    }()
}

// MARK: - 课程小组件的配置

struct CourseWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "课程表"
    static var description = IntentDescription("选择课程卡显示今天还是明天的课")

    @Parameter(title: "上完课后显示明天的课", default: false)
    var showTomorrow: Bool
}

struct CourseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let showTomorrow: Bool
}

struct CourseProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CourseEntry {
        CourseEntry(date: Date(), snapshot: PreviewData.snapshot, showTomorrow: false)
    }

    func snapshot(for configuration: CourseWidgetConfigIntent, in context: Context) async -> CourseEntry {
        CourseEntry(
            date: Date(),
            snapshot: (WidgetStore.read() ?? (context.isPreview ? PreviewData.snapshot : .empty)).resolved(at: Date()),
            showTomorrow: configuration.showTomorrow
        )
    }

    func timeline(for configuration: CourseWidgetConfigIntent, in context: Context) async -> Timeline<CourseEntry> {
        let now = Date()
        let snapshot = WidgetStore.read() ?? .empty
        var dates = (0...24).map { now.addingTimeInterval(Double($0) * 3600) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        for offset in 0...1 {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            dates.append(day)
            for course in snapshot.resolved(at: day).courses {
                dates.append(day.addingTimeInterval(Double(course.startMinutes * 60)))
                dates.append(day.addingTimeInterval(Double(course.endMinutes * 60)))
            }
        }
        let entries = Set(dates.filter { $0 >= now }).sorted().map { date in
            CourseEntry(date: date, snapshot: snapshot.resolved(at: date), showTomorrow: configuration.showTomorrow)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(12 * 3600)))
    }
}

// MARK: - 小组件

struct CourseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "CourseWidget",
            intent: CourseWidgetConfigIntent.self,
            provider: CourseProvider()
        ) { entry in
            CourseWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(tint: .blue) }
        }
        .configurationDisplayName("课程")
        .description("查看下一节课与今日安排，可设置课后显示明天的课程。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct ElectricityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ElectricityWidget", provider: SnapshotProvider(preview: PreviewData.snapshot)) { entry in
            ElectricityWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(tint: .orange) }
        }
        .configurationDisplayName("电费")
        .description("宿舍还剩多少电费。")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct BreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BreakWidget", provider: SnapshotProvider(preview: PreviewData.snapshot)) { entry in
            BreakWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(tint: .teal) }
        }
        .configurationDisplayName("放假倒计时")
        .description("离放假还有多少天。")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct ExamWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ExamWidget", provider: SnapshotProvider(preview: PreviewData.snapshot, schedulesExamChanges: true)) { entry in
            ExamWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(tint: CampusFeatureColors.exam) }
        }
        .configurationDisplayName("考试倒计时")
        .description("查看下一场考试的科目、日期和剩余天数。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - 视图

struct CourseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CourseEntry

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint(showsLeadingRule: true)
        } else if family == .accessoryRectangular {
            lockScreenLayout
        } else if family == .systemSmall {
            smallLayout
        } else {
            mediumLayout
        }
    }

    /// 今天还没上完的课
    private var todayRemaining: [WidgetSnapshot.Course] {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: entry.date) * 60
            + calendar.component(.minute, from: entry.date)
        return entry.snapshot.courses.filter { $0.endMinutes > minutes }
    }

    /// 开关打开 && 今天已经没课了，才切到明天
    private var showingTomorrow: Bool {
        entry.showTomorrow && todayRemaining.isEmpty
    }

    private var visibleCourses: [WidgetSnapshot.Course] {
        showingTomorrow ? (entry.snapshot.tomorrowCourses ?? []) : todayRemaining
    }

    private var emptyText: String {
        if showingTomorrow { return "明天没课" }
        return entry.snapshot.courses.isEmpty ? "今天没课" : "今天的课上完了"
    }

    private var lockScreenLayout: some View {
        Group {
            if let course = visibleCourses.first {
                LockScreenRows(
                    icon: "location.fill",
                    heading: course.room.isEmpty ? "教室待定" : course.room,
                    title: course.name,
                    subtitle: lockScreenTime(course),
                    showsLeadingRule: true,
                    allowsTwoLineTitle: true
                )
            } else {
                LockScreenRows(icon: "book.closed.fill", heading: "课程",
                               title: emptyText, subtitle: headerText, showsLeadingRule: true)
            }
        }
        .privacySensitive()
    }

    private func lockScreenTime(_ course: WidgetSnapshot.Course) -> String {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: entry.date) * 60
            + calendar.component(.minute, from: entry.date)
        if !showingTomorrow && minutes >= course.startMinutes {
            return "\(WidgetSnapshot.clock(course.endMinutes)) 下课"
        }
        let prefix = showingTomorrow ? "明天 " : ""
        return "\(prefix)\(WidgetSnapshot.clock(course.startMinutes))–\(WidgetSnapshot.clock(course.endMinutes))"
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallWidgetHeader(icon: "calendar", title: headerText, tint: .blue)
            Spacer(minLength: 6)
            if let course = visibleCourses.first {
                featuredCourse(course, compact: true)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Circle().fill(Self.color(for: course)).frame(width: 5, height: 5)
                    Text(courseStatus(course, compact: true))
                    Spacer(minLength: 0)
                    if visibleCourses.count > 1 {
                        Text("另有 \(visibleCourses.count - 1) 节")
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                emptyCourses
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let course = visibleCourses.first {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        featuredCourse(course, compact: false)
                        Text(courseStatus(course))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Self.color(for: course))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(width: 1)

                    VStack(alignment: .leading, spacing: 9) {
                        if visibleCourses.count > 1 {
                            ForEach(visibleCourses.dropFirst().prefix(2)) { next in
                                upcomingCourse(next)
                            }
                            if visibleCourses.count > 3 {
                                Text("还有 \(visibleCourses.count - 3) 节课")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("之后没有课程")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                emptyCourses
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func featuredCourse(_ course: WidgetSnapshot.Course, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WidgetSnapshot.clock(course.startMinutes))
                .font(.system(size: compact ? 26 : 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Self.color(for: course))
            Text(course.name)
                .font(.system(size: compact ? 14 : 15, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if !course.room.isEmpty {
                Label(course.room, systemImage: "location.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func upcomingCourse(_ course: WidgetSnapshot.Course) -> some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.color(for: course))
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(WidgetSnapshot.clock(course.startMinutes))
                        .foregroundStyle(Self.color(for: course))
                    if !course.room.isEmpty {
                        Text(course.room).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                Text(course.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        }
    }

    private func courseStatus(_ course: WidgetSnapshot.Course, compact: Bool = false) -> String {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: entry.date) * 60
            + calendar.component(.minute, from: entry.date)
        if compact {
            return !showingTomorrow && minutes >= course.startMinutes
                ? "正在上课" : "\(WidgetSnapshot.clock(course.endMinutes)) 下课"
        }
        return !showingTomorrow && minutes >= course.startMinutes
            ? "正在上课 · \(WidgetSnapshot.clock(course.endMinutes)) 下课"
            : "下一节 · \(WidgetSnapshot.clock(course.endMinutes)) 下课"
    }

    private var emptyCourses: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.blue)
            Text(emptyText)
                .font(.system(size: 18, weight: .semibold))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text("留点时间给自己")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// 和 app 里 CoursePalette 同一套颜色，下标由 App 端算好写进快照
    private static let palette: [Color] = [
        Color(red: 0.20, green: 0.47, blue: 0.90),
        Color(red: 0.85, green: 0.42, blue: 0.20),
        Color(red: 0.18, green: 0.60, blue: 0.45),
        Color(red: 0.58, green: 0.35, blue: 0.75),
        Color(red: 0.82, green: 0.55, blue: 0.12),
        Color(red: 0.12, green: 0.53, blue: 0.68),
        Color(red: 0.74, green: 0.30, blue: 0.45),
        Color(red: 0.35, green: 0.50, blue: 0.25),
        Color(red: 0.45, green: 0.38, blue: 0.80),
        Color(red: 0.72, green: 0.52, blue: 0.30),
        Color(red: 0.16, green: 0.58, blue: 0.58),
        Color(red: 0.62, green: 0.42, blue: 0.62),
        Color(red: 0.30, green: 0.45, blue: 0.62),
        Color(red: 0.78, green: 0.38, blue: 0.32)
    ]

    private static func color(for course: WidgetSnapshot.Course) -> Color {
        if let index = course.colorIndex {
            return palette[abs(index % palette.count)]
        }
        var hash = 5381
        for scalar in course.name.unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }
        return palette[abs(hash % palette.count)]
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
            Text(headerText)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if family == .systemMedium {
                Text(showingTomorrow ? "明日课程" : "今日课程")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var headerText: String {
        if showingTomorrow {
            let label = WidgetSnapshot.weekdayLabel(entry.snapshot.tomorrowWeekday ?? 0)
            return label.isEmpty ? "明天" : "\(label) · 明天"
        }
        return entry.snapshot.week > 0
            ? "\(entry.snapshot.weekdayLabel) · 第 \(entry.snapshot.week) 周"
            : entry.snapshot.weekdayLabel
    }
}

struct ElectricityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var isLow: Bool { (entry.snapshot.balance ?? .infinity) < 10 }
    private var tint: Color { isLow ? .orange : .primary }

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
        } else if family == .accessoryRectangular {
            LockScreenRows(icon: "bolt.fill", heading: isLow ? "宿舍电量偏低" : "宿舍电量",
                           title: entry.snapshot.balance.map { String(format: "%.2f 度", $0) } ?? "待查询",
                           subtitle: lockScreenDetail, titleFont: .system(size: 22, weight: .bold, design: .rounded))
                .privacySensitive()
        } else if family == .accessoryCircular {
            LockScreenCompactValue(icon: "bolt.fill",
                                   value: entry.snapshot.balance.map { String(format: "%.2f", $0) } ?? "—",
                                   caption: entry.snapshot.balance == nil ? "待查询" : isLow ? "度 · 偏低" : "度")
                .privacySensitive()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SmallWidgetHeader(icon: "bolt.fill", title: "宿舍电量", tint: .orange)

                Spacer(minLength: 6)

                if let balance = entry.snapshot.balance {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.2f", balance))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.55)
                            .layoutPriority(1)
                        Text("度")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    Text(isLow ? "电量偏低，记得充值" : "剩余可用电量")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isLow ? Color.orange : Color.secondary)
                        .lineLimit(1)
                } else {
                    Text("待查询")
                        .font(.system(size: 27, weight: .semibold))
                    Text("打开 App 查询宿舍电量")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(alignment: .bottom, spacing: 4) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let room = entry.snapshot.roomName, !room.isEmpty {
                            Label(room, systemImage: "building.2")
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        Text(updateText)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(intent: RefreshElectricityIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(.primary.opacity(0.06), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新电量")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var updateText: String {
        guard let updated = entry.snapshot.balanceUpdatedAt else { return "尚无查询记录" }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(updated, inSameDayAs: entry.date)
            ? "HH:mm 更新" : "M/d HH:mm 更新"
        return formatter.string(from: updated)
    }

    private var lockScreenDetail: String {
        guard let room = entry.snapshot.roomName, !room.isEmpty else { return updateText }
        return "\(room) · \(updateText)"
    }
}

struct BreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
        } else if family == .accessoryRectangular {
            if let item = entry.snapshot.upcomingBreak {
                LockScreenRows(icon: "sun.horizon.fill", heading: item.title,
                               title: item.days <= 0 ? "今天" : "\(item.days) 天",
                               subtitle: item.date.formatted(.dateTime.month().day().weekday(.abbreviated)),
                               titleFont: .system(size: 22, weight: .bold, design: .rounded))
            } else {
                LockScreenRows(icon: "calendar", heading: "假期倒计时",
                               title: "期待下一次放假", subtitle: "打开 App 更新校历")
            }
        } else if family == .accessoryCircular {
            LockScreenCompactValue(icon: "sun.horizon.fill",
                                   value: entry.snapshot.upcomingBreak.map { $0.days <= 0 ? "今天" : "\($0.days)天" } ?? "—",
                                   caption: entry.snapshot.upcomingBreak?.title ?? "待更新")
        } else {
            let item = entry.snapshot.upcomingBreak
            SmallCountdownCard(icon: "sun.horizon.fill", title: "假期倒计时", tint: .teal,
                               days: item?.days, name: item?.title,
                               detail: item?.date.formatted(.dateTime.month().day().weekday(.abbreviated)),
                               emptyIcon: "calendar.badge.plus", emptyTitle: "期待下一次放假",
                               emptyDetail: "打开 App 查看校历后显示")
        }
    }
}

struct ExamWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private let icon = "pencil.and.list.clipboard"
    private var exam: WidgetSnapshot.Exam? { entry.snapshot.nextExam }
    private var countdown: String {
        guard let days = exam?.days else { return "—" }
        return days <= 0 ? "今天" : "\(days) 天"
    }

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
        } else {
            layout.privacySensitive()
        }
    }

    @ViewBuilder private var layout: some View {
        switch family {
        case .systemMedium:
            if exam != nil {
                HStack(spacing: 16) {
                    countdownCard(showsVenue: !following.isEmpty)
                    Divider()
                    schedule
                }
            } else {
                countdownCard()
            }
        case .accessoryRectangular:
            LockScreenRows(icon: icon, heading: exam == nil ? "考试倒计时" : "考试 · " + countdown,
                           title: exam?.title ?? "暂无待考科目", subtitle: exam.flatMap(detail) ?? "打开 App 查看考试安排",
                           allowsTwoLineTitle: true, headingDetail: venueText)
        case .accessoryCircular:
            LockScreenCompactValue(icon: icon, value: countdown, caption: exam == nil ? "暂无考试" : "考试")
        case .accessoryInline:
            Label(exam.map { countdown + " · " + $0.title } ?? "暂无待考科目", systemImage: icon)
        default:
            countdownCard()
        }
    }

    private var following: ArraySlice<WidgetSnapshot.Exam> {
        (entry.snapshot.upcomingExams ?? []).dropFirst().prefix(2)
    }

    private var seatText: String? {
        guard let seat = exam?.seat?.trimmingCharacters(in: .whitespacesAndNewlines), !seat.isEmpty else { return nil }
        return "座位 " + seat
    }

    private var roomText: String? {
        guard let room = exam?.room?.trimmingCharacters(in: .whitespacesAndNewlines), !room.isEmpty else { return nil }
        return room
    }

    private var venueText: String? {
        let parts = [roomText, seatText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func countdownCard(showsVenue: Bool = true) -> some View {
        SmallCountdownCard(icon: icon, title: "考试倒计时", tint: CampusFeatureColors.exam,
                           days: exam?.days, name: exam?.title, detail: exam.flatMap(detail),
                           emptyIcon: "calendar.badge.checkmark", emptyTitle: "暂无待考科目",
                           emptyDetail: "打开 App 查看考试安排",
                           room: showsVenue && exam != nil ? (roomText ?? "考场待定") : nil,
                           seat: showsVenue ? seatText : nil)
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(following.isEmpty ? "本场考试" : "后续考试")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            if following.isEmpty {
                Label(roomText ?? "考场待定", systemImage: "location.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                if let seatText {
                    Text(seatText).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(following.indices), id: \.self) { index in
                    let item = following[index]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail(item) ?? "").font(.system(size: 10, weight: .medium)).foregroundStyle(CampusFeatureColors.exam)
                        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func detail(_ exam: WidgetSnapshot.Exam) -> String? {
        guard let date = exam.date else { return nil }
        var format = Date.FormatStyle.dateTime.month().day()
        format.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return [date.formatted(format), exam.startTime].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct SmallWidgetHeader: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(tint)
                .frame(width: 13, height: 14)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 18)
    }
}

private struct SmallCountdownCard: View {
    let icon: String
    let title: String
    let tint: Color
    let days: Int?
    let name: String?
    let detail: String?
    let emptyIcon: String
    let emptyTitle: String
    let emptyDetail: String
    var room: String?
    var seat: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallWidgetHeader(icon: icon, title: title, tint: tint)
            Spacer(minLength: 6)
            if let days, let name {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(days <= 0 ? "今天" : "\(days)")
                        .font(.system(size: days <= 0 || room != nil ? 36 : 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.6)
                    if days > 0 {
                        Text("天")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            } else {
                Image(systemName: emptyIcon)
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(tint)
                Text(emptyTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            Text(detail ?? emptyDetail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let room {
                HStack(spacing: 4) {
                    Text(room)
                    if let seat {
                        Text(seat).layoutPriority(1)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct EmptyHint: View {
    @Environment(\.widgetFamily) private var family
    var showsLeadingRule = false

    var body: some View {
        if family == .accessoryInline {
            Label("打开 App 登录", systemImage: "lock.fill")
        } else if family == .accessoryRectangular {
            LockScreenRows(icon: "lock.fill", heading: "XATune",
                           title: "打开 App 登录", subtitle: "同步校园数据", showsLeadingRule: showsLeadingRule)
        } else if family == .accessoryCircular {
            LockScreenCompactValue(icon: "lock.fill", value: "登录", caption: "XATune")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2.fill").foregroundStyle(.blue)
                    Text("XATune").foregroundStyle(.secondary)
                }
                .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 10)
                Text("校园日常\n一眼掌握")
                    .font(.system(size: 21, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 10)
                Label("打开 App 登录", systemImage: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct LockScreenRows: View {
    let icon: String
    let heading: String
    let title: String
    let subtitle: String
    var titleFont: Font = .headline
    var showsLeadingRule = false
    var allowsTwoLineTitle = false
    var headingDetail: String?

    var body: some View {
        HStack(spacing: 7) {
            if showsLeadingRule {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 5)
                    .widgetAccentable()
                    .accessibilityHidden(true)
            }
            ViewThatFits(in: .vertical) {
                if allowsTwoLineTitle {
                    rows(titleLines: 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                rows(titleLines: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func rows(titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                if let headingDetail {
                    ViewThatFits(in: .horizontal) {
                        Text(heading + " · " + headingDetail).fixedSize()
                        Text(heading)
                    }
                } else {
                    Text(heading)
                }
            }
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .widgetAccentable()
            .layoutPriority(1)
            Text(title)
                .font(titleFont)
                .monospacedDigit()
                .lineLimit(titleLines)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LockScreenCompactValue: View {
    let icon: String
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .widgetAccentable()
                .accessibilityHidden(true)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 使用系统语义底色，浅色与深色模式共享轻量的主题渐变。
struct WidgetBackdrop: View {
    @Environment(\.widgetFamily) private var family
    let tint: Color

    var body: some View {
        if family == .accessoryRectangular || family == .accessoryCircular || family == .accessoryInline {
            Color.clear
        } else {
            ZStack {
                Color(uiColor: .systemBackground)
                LinearGradient(
                    colors: [tint.opacity(0.13), tint.opacity(0.02), .clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
        }
    }
}
