import SwiftUI
import WidgetKit

struct WatchWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WatchSnapshot
}

struct WatchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchWidgetEntry {
        WatchWidgetEntry(date: Date(), snapshot: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (WatchWidgetEntry) -> Void) {
        completion(WatchWidgetEntry(date: Date(), snapshot: WatchStore.read().snapshot ?? .empty))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWidgetEntry>) -> Void) {
        let snapshot = WatchStore.read().snapshot ?? .empty
        let now = Date()
        let dates = [now] + snapshot.timelineDates(after: now)
        completion(Timeline(entries: dates.map { WatchWidgetEntry(date: $0, snapshot: snapshot) },
                            policy: .after(now.addingTimeInterval(24 * 3600))))
    }
}

private enum WatchWidgetKind { case course, electricity, holiday }

private struct WatchComplicationView: View {
    let entry: WatchWidgetEntry
    let kind: WatchWidgetKind
    @Environment(\.widgetFamily) private var family

    private var lesson: WatchSnapshot.Lesson? {
        entry.snapshot.currentLesson(at: entry.date) ?? entry.snapshot.nextLesson(at: entry.date)
    }
    private var holiday: WatchSnapshot.Holiday? { entry.snapshot.nextHoliday(at: entry.date) }
    private var url: URL { URL(string: "xatuwatch://\(kind == .course ? "courses" : kind == .electricity ? "electricity" : "holiday")")! }
    private var icon: String { kind == .course ? "book.closed.fill" : kind == .electricity ? "bolt.fill" : "sun.max.fill" }

    private var tint: Color {
        switch kind {
        case .course: return CampusCourseColors.color(index: lesson?.colorIndex)
        case .electricity: return .yellow
        case .holiday: return .mint
        }
    }

    private var title: String {
        guard entry.snapshot.loggedIn else { return "请在手机端同步" }
        switch kind {
        case .course: return lesson?.name ?? "暂无后续课程"
        case .electricity: return "\(entry.snapshot.balance ?? "—") 度"
        case .holiday:
            guard let holiday else { return "请更新校历" }
            let days = WatchSnapshot.days(from: entry.date, to: holiday.date)
            return days == 0 ? "今天\(holiday.title)" : "\(holiday.title)还有 \(days) 天"
        }
    }
    private var detail: String {
        switch kind {
        case .course: return lesson.map { $0.room.isEmpty ? "教室待定" : $0.room } ?? "打开手机更新课表"
        case .electricity: return entry.snapshot.roomName ?? "请在手机端绑定宿舍"
        case .holiday: return holiday.map(\.title) ?? "假期倒计时"
        }
    }
    private var time: String {
        switch kind {
        case .course:
            guard let lesson else { return "" }
            let calendar = WatchSnapshot.campusCalendar
            let prefix = calendar.isDate(lesson.start, inSameDayAs: entry.date) ? "" : WatchSnapshot.dayLabel(lesson.start, relativeTo: entry.date) + " "
            let current = entry.snapshot.currentLesson(at: entry.date) != nil
            return current ? "\(WatchSnapshot.clock(lesson.end)) 下课" : "\(prefix)\(WatchSnapshot.clock(lesson.start)) 上课"
        case .electricity:
            return entry.snapshot.balanceUpdatedAt.map { "查询于 \(WatchSnapshot.format($0, "M/d HH:mm"))" } ?? "尚未查询"
        case .holiday: return holiday.map { WatchSnapshot.format($0.date, "M月d日") } ?? ""
        }
    }

    var body: some View {
        Group {
            if !entry.snapshot.loggedIn {
                if family == .accessoryRectangular {
                    Label("打开 iPhone 同步", systemImage: icon).font(.headline)
                } else {
                    Label("待同步", systemImage: icon).font(.caption2)
                }
            } else {
                switch family {
                case .accessoryInline:
                    Label(kind == .course ? "\(detail) · \(title)" : title, systemImage: icon)
                case .accessoryCircular:
                    VStack(spacing: 2) {
                        if kind == .course {
                            Text(detail).font(.system(size: 12, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                            Text(title).font(.system(size: 10)).lineLimit(2).minimumScaleFactor(0.7)
                        } else if kind == .holiday, let holiday {
                            Text("\(max(0, WatchSnapshot.days(from: entry.date, to: holiday.date)))")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text(holiday.title).font(.system(size: 9)).lineLimit(1)
                        } else {
                            Image(systemName: icon).font(.caption2)
                            Text(entry.snapshot.balance ?? "—").font(.system(size: 16, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                            Text("度").font(.system(size: 9))
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tint).frame(width: 3).widgetAccentable()
                        VStack(alignment: .leading, spacing: 2) {
                            if kind == .course {
                                HStack(spacing: 3) {
                                    Image(systemName: "mappin")
                                        .font(.caption.weight(.bold))
                                        .accessibilityHidden(true)
                                    Text(detail)
                                        .font(.footnote.weight(.bold))
                                }
                                .foregroundStyle(tint).widgetAccentable()
                                Text(title).font(.headline).lineLimit(2).minimumScaleFactor(0.75)
                            } else {
                                Label(kind == .electricity ? "剩余电量" : "假期倒计时", systemImage: icon)
                                    .font(.caption).foregroundStyle(tint).widgetAccentable()
                                Text(title).font(.headline).foregroundStyle(tint)
                                    .widgetAccentable().lineLimit(2).minimumScaleFactor(0.75)
                            }
                            Text(time).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
        }
        .privacySensitive()
        .widgetURL(url)
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .combine)
    }
}

struct WatchCourseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchCourse", provider: WatchWidgetProvider()) {
            WatchComplicationView(entry: $0, kind: .course)
        }
        .configurationDisplayName("当前／下一节课")
        .description("教室、课程名和上课时间，随课表自动切换。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
struct WatchElectricityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchElectricity", provider: WatchWidgetProvider()) {
            WatchComplicationView(entry: $0, kind: .electricity)
        }
        .configurationDisplayName("宿舍电费")
        .description("手机最近查询的剩余电量。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
struct WatchHolidayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchHoliday", provider: WatchWidgetProvider()) {
            WatchComplicationView(entry: $0, kind: .holiday)
        }
        .configurationDisplayName("假期倒计时")
        .description("距离放假或开学还有多少天。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
@main
struct WatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchCourseWidget()
        WatchElectricityWidget()
        WatchHolidayWidget()
    }
}
