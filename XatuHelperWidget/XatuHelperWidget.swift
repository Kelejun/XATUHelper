import SwiftUI
import WidgetKit

@main
struct XatuHelperWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: WidgetStore.read() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: Date(), snapshot: WidgetStore.read() ?? .empty)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日")
        .description("今天的课、电费余额和放假倒计时。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        if let snapshot = entry.snapshot, snapshot.loggedIn {
            if family == .systemSmall {
                smallLayout(snapshot)
            } else {
                mediumLayout(snapshot)
            }
        } else {
            emptyLayout
        }
    }

    private var emptyLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("XATU Helper")
                .font(.headline)
            Text("打开 App 登录一次，这里就会显示今天的课。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func smallLayout(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(snapshot.weekdayLabel)
                if snapshot.week > 0 { Text("· 第 \(snapshot.week) 周") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let next = nextCourse(snapshot) {
                Text(next.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                Text("\(WidgetSnapshot.clock(next.startMinutes)) \(next.room)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(snapshot.courses.isEmpty ? "今天没课" : "今天的课上完了")
                    .font(.system(size: 15, weight: .semibold))
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if let balance = snapshot.balance {
                    Text("¥\(String(format: "%.2f", balance))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(balance < 10 ? Color.orange : Color.primary)
                }
                if let breakItem = snapshot.upcomingBreak {
                    Text("\(breakItem.title) \(breakItem.days) 天")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func mediumLayout(_ snapshot: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(snapshot.weekdayLabel)
                    if snapshot.week > 0 { Text("· 第 \(snapshot.week) 周") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if snapshot.courses.isEmpty {
                    Text("今天没课")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(remainingCourses(snapshot).prefix(4)) { course in
                            HStack(spacing: 6) {
                                Text(WidgetSnapshot.clock(course.startMinutes))
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .leading)
                                Text(course.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .trailing, spacing: 6) {
                if let balance = snapshot.balance {
                    Text("¥\(String(format: "%.2f", balance))")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(balance < 10 ? Color.orange : Color.primary)
                }
                if let breakItem = snapshot.upcomingBreak {
                    Text("\(breakItem.title)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("还有 \(breakItem.days) 天")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.teal)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 84, alignment: .trailing)
        }
    }

    private func remainingCourses(_ snapshot: WidgetSnapshot) -> [WidgetSnapshot.Course] {
        let now = entry.date
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let remaining = snapshot.courses.filter { $0.endMinutes >= minutes }
        return remaining.isEmpty ? snapshot.courses : remaining
    }

    private func nextCourse(_ snapshot: WidgetSnapshot) -> WidgetSnapshot.Course? {
        let calendar = Calendar.current
        let now = entry.date
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return snapshot.courses.first { $0.endMinutes >= minutes }
    }
}
