import SwiftUI
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

// MARK: - 小组件

struct CourseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CourseWidget", provider: SnapshotProvider(preview: PreviewData.snapshot)) { entry in
            CourseWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("课程")
        .description("今天要上的课。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ElectricityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ElectricityWidget", provider: SnapshotProvider(preview: PreviewData.snapshot)) { entry in
            ElectricityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("放假倒计时")
        .description("离放假还有多少天。")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 视图

struct CourseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
        } else if family == .systemSmall {
            smallLayout
        } else {
            mediumLayout
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            Spacer(minLength: 0)
            if remaining.isEmpty {
                Text(entry.snapshot.courses.isEmpty ? "今天没课" : "今天的课上完了")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(remaining.prefix(3)) { course in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(course.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(WidgetSnapshot.clock(course.startMinutes))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
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
            if remaining.isEmpty {
                Text(entry.snapshot.courses.isEmpty ? "今天没课" : "今天的课上完了")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(remaining.prefix(4)) { course in
                    HStack(spacing: 8) {
                        Text(WidgetSnapshot.clock(course.startMinutes))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .leading)
                        Text(course.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if !course.room.isEmpty {
                            Text(course.room)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        Text(headerText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var headerText: String {
        entry.snapshot.week > 0
            ? "\(entry.snapshot.weekdayLabel) · 第 \(entry.snapshot.week) 周"
            : entry.snapshot.weekdayLabel
    }

    private var remaining: [WidgetSnapshot.Course] {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: entry.date) * 60
            + calendar.component(.minute, from: entry.date)
        let list = entry.snapshot.courses.filter { $0.endMinutes >= minutes }
        return list.isEmpty ? [] : list
    }
}

struct ElectricityWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        if !entry.snapshot.loggedIn {
            EmptyHint()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("电费还剩")
                    .font(.headline)

                Spacer(minLength: 0)

                if let balance = entry.snapshot.balance {
                    Text("¥\(String(format: "%.2f", balance))")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
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
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(item.days == 0 ? "今天" : "还有 \(item.days) 天")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
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
