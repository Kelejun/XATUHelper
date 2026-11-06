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
    }
}

// MARK: - 数据

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    var preview: WidgetSnapshot

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: WidgetStore.read() ?? preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: Date(), snapshot: WidgetStore.read() ?? preview)
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
            nextExam: nil,
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
            snapshot: WidgetStore.read() ?? PreviewData.snapshot,
            showTomorrow: configuration.showTomorrow
        )
    }

    func timeline(for configuration: CourseWidgetConfigIntent, in context: Context) async -> Timeline<CourseEntry> {
        let entry = CourseEntry(
            date: Date(),
            snapshot: WidgetStore.read() ?? PreviewData.snapshot,
            showTomorrow: configuration.showTomorrow
        )
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(refresh))
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
        .supportedFamilies([.systemSmall, .systemMedium])
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
        .supportedFamilies([.systemSmall])
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
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 视图

struct CourseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CourseEntry

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
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
        return entry.snapshot.courses.filter { $0.endMinutes >= minutes }
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

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
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
                Label(course.room, systemImage: "mappin")
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
            Image(systemName: "sun.max")
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
            return palette[index % palette.count]
        }
        var hash = 5381
        for scalar in course.name.unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count]
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
    let entry: TodayEntry

    private var isLow: Bool { (entry.snapshot.balance ?? .infinity) < 10 }
    private var tint: Color { isLow ? .orange : .primary }

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill").foregroundStyle(.orange)
                    Text("宿舍电量").foregroundStyle(.secondary)
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
                .font(.system(size: 11, weight: .medium))

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
}

struct BreakWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "sun.horizon.fill").foregroundStyle(.teal)
                    Text("假期倒计时").foregroundStyle(.secondary)
                }
                .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 8)

                if let item = entry.snapshot.upcomingBreak {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(item.days <= 0 ? "今天" : "\(item.days)")
                            .font(.system(size: item.days <= 0 ? 36 : 48, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.teal)
                            .minimumScaleFactor(0.6)
                        if item.days > 0 {
                            Text("天")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Text(item.date, format: .dateTime.month().day().weekday(.abbreviated))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(.teal)
                    Text("期待下一次放假")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.top, 8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Text("打开 App 查看校历后显示")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct EmptyHint: View {
    var body: some View {
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

/// 使用系统语义底色，浅色与深色模式共享轻量的主题渐变。
struct WidgetBackdrop: View {
    let tint: Color

    var body: some View {
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
