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
            roomName: "9号公寓",
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
                .containerBackground(for: .widget) { WidgetBackdrop() }
        }
        .configurationDisplayName("课程")
        .description("今天还没上完的课；今天的课上完后接着显示明天的。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ElectricityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ElectricityWidget", provider: SnapshotProvider(preview: PreviewData.snapshot)) { entry in
            ElectricityWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop() }
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
                .containerBackground(for: .widget) { WidgetBackdrop() }
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
        VStack(alignment: .leading, spacing: 5) {
            header
            Spacer(minLength: 0)
            if visibleCourses.isEmpty {
                Text(emptyText)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(visibleCourses.prefix(3)) { course in
                    courseRow(course, showsRoom: false)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if visibleCourses.isEmpty {
                Text(emptyText)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(visibleCourses.prefix(4)) { course in
                    courseRow(course, showsRoom: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 一节课 = 一根色条 + 淡渐变底，和 app 里首页的课程行一个路数
    private func courseRow(_ course: WidgetSnapshot.Course, showsRoom: Bool) -> some View {
        let tint = Self.color(for: course)
        return HStack(spacing: 6) {
            Capsule()
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(course.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if showsRoom, !course.room.isEmpty {
                    Text(course.room)
                        .font(.system(size: 9))
                        .foregroundStyle(tint.opacity(0.75))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text(WidgetSnapshot.clock(course.startMinutes))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(tint.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.20), tint.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
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
        Text(headerText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
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

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("电费还剩")
                        .font(.headline)
                    Spacer(minLength: 0)
                    Button(intent: RefreshElectricityIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.blue)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.blue.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                if let balance = entry.snapshot.balance {
                    Text("¥\(String(format: "%.2f", balance))")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(balance < 10 ? Color.orange : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("还没查过")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(footerText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var footerText: String {
        var parts: [String] = []
        if let room = entry.snapshot.roomName, !room.isEmpty {
            parts.append(room)
        }
        if let updated = entry.snapshot.balanceUpdatedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            parts.append(formatter.string(from: updated))
        }
        return parts.isEmpty ? "打开 App 查一次" : parts.joined(separator: " · ")
    }
}

struct BreakWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
        } else if let item = entry.snapshot.upcomingBreak {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.title)还有")
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(item.days == 0 ? "今天" : "\(item.days) 天")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.teal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 0)

                Text(dateText(item.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("放假倒计时")
                    .font(.headline)
                Spacer(minLength: 0)
                Text("先把校历打开一次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

struct EmptyHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("XATU Helper")
                .font(.headline)
            Text("打开 App 登录一次，这里就有数据了。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}


/// 小组件底色：iOS 26 起用系统玻璃效果，老系统退回毛玻璃材质。
struct WidgetBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
    }
}


