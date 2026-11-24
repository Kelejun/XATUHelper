import SwiftUI
import WidgetKit

struct WatchWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WatchSnapshot
    var courseProgress: WatchCourseProgress? = nil
}

struct WatchWidgetProvider: TimelineProvider {
    var preview: WatchSnapshot = .empty
    var includesCourseProgress = false

    func placeholder(in context: Context) -> WatchWidgetEntry {
        WatchWidgetEntry(date: Date(), snapshot: preview)
    }
    func getSnapshot(in context: Context, completion: @escaping (WatchWidgetEntry) -> Void) {
        let snapshot = WatchStore.read().snapshot ?? (context.isPreview ? preview : .empty)
        let date = Date()
        let progress = includesCourseProgress ? WatchCourseProgress(snapshot: snapshot, at: date) : nil
        completion(WatchWidgetEntry(date: date, snapshot: snapshot, courseProgress: progress))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWidgetEntry>) -> Void) {
        let snapshot = WatchStore.read().snapshot ?? .empty
        let now = Date()
        let entries: [WatchWidgetEntry]
        if includesCourseProgress {
            entries = WatchCourseProgress.timeline(snapshot: snapshot, from: now).map {
                WatchWidgetEntry(date: $0.date, snapshot: snapshot, courseProgress: $0)
            }
        } else {
            entries = ([now] + snapshot.timelineDates(after: now)).map {
                WatchWidgetEntry(date: $0, snapshot: snapshot)
            }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(24 * 3600))))
    }
}

private enum WatchWidgetKind: String {
    case course = "courses", electricity, holiday, exam = "exams"

    var icon: String {
        switch self {
        case .course: return "book.closed.fill"
        case .electricity: return "bolt.fill"
        case .holiday: return "sun.max.fill"
        case .exam: return "pencil.and.list.clipboard"
        }
    }
}

private struct WatchComplicationView: View {
    let entry: WatchWidgetEntry
    let kind: WatchWidgetKind
    @Environment(\.widgetFamily) private var family

    private var lesson: WatchSnapshot.Lesson? {
        entry.snapshot.currentLesson(at: entry.date) ?? entry.snapshot.nextLesson(at: entry.date)
    }
    private var holiday: WatchSnapshot.Holiday? { entry.snapshot.nextHoliday(at: entry.date) }
    private var exam: WatchSnapshot.Exam? { entry.snapshot.upcomingExams(at: entry.date).first }
    private var examCountdown: String {
        guard let exam else { return "—" }
        let days = WatchSnapshot.days(from: entry.date, to: exam.start)
        return days <= 0 ? "今天" : "\(days) 天"
    }
    private var url: URL { URL(string: "xatuwatch://\(kind.rawValue)")! }
    private var icon: String { kind.icon }

    private var tint: Color {
        switch kind {
        case .course: return CampusCourseColors.color(index: lesson?.colorIndex)
        case .electricity: return .yellow
        case .exam: return .indigo
        case .holiday: return .mint
        }
    }

    private var title: String {
        guard entry.snapshot.loggedIn else { return "请在手机端同步" }
        switch kind {
        case .exam: return exam?.name ?? (entry.snapshot.examsUpdatedAt == nil ? "考试尚未同步" : "暂无待考科目")
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
        case .exam: return exam == nil ? "考试倒计时" : "考试 · " + examCountdown
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
        case .exam:
            guard let exam else { return "打开 iPhone 查看考试安排" }
            let hasStartTime = exam.time.range(of: #"\d{1,2}[:：]\d{2}"#, options: .regularExpression) != nil
            return WatchSnapshot.format(exam.start, hasStartTime ? "M月d日 · HH:mm" : "M月d日")
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
                case .accessoryCorner:
                    Text(examCountdown)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .widgetAccentable()
                        .widgetLabel { Text(title) }
                case .accessoryInline:
                    if kind == .exam, exam != nil {
                        Label(examCountdown + " · " + title, systemImage: icon)
                    } else {
                        Label(kind == .course ? "\(detail) · \(title)" : title, systemImage: icon)
                    }
                case .accessoryCircular where kind != .course:
                    VStack(spacing: 2) {
                        if kind == .exam {
                            Image(systemName: icon).font(.caption2).widgetAccentable()
                            Text(examCountdown).font(.system(size: 19, weight: .bold, design: .rounded))
                                .lineLimit(1).minimumScaleFactor(0.65)
                            Text(exam == nil ? title : "考试").font(.system(size: 9)).lineLimit(1)
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
                            .fill(tint).frame(width: 5).widgetAccentable()
                        ViewThatFits(in: .vertical) {
                            rectangularDetails(titleLines: 2)
                                .fixedSize(horizontal: false, vertical: true)
                            rectangularDetails(titleLines: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
        }
        .privacySensitive()
        .widgetURL(url)
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .combine)
    }

    private func rectangularDetails(titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if kind == .course {
                HStack(spacing: 3) {
                    Image(systemName: "location.fill")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                    Text(detail)
                        .font(.footnote.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(tint).widgetAccentable()
                .layoutPriority(1)
                Text(title).font(.headline).lineLimit(titleLines).minimumScaleFactor(0.75)
            } else {
                Label {
                    if kind == .exam, let exam {
                        let venue = [exam.room, exam.seat.isEmpty ? "" : "座位 " + exam.seat]
                            .filter { !$0.isEmpty }.joined(separator: " · ")
                        ViewThatFits(in: .horizontal) {
                            if !venue.isEmpty { Text(rectangularHeading + " · " + venue).fixedSize() }
                            Text(rectangularHeading)
                        }
                    } else {
                        Text(rectangularHeading)
                    }
                } icon: {
                    Image(systemName: icon)
                }
                    .font(.caption).foregroundStyle(tint).widgetAccentable()
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(title).font(.headline).foregroundStyle(kind == .exam ? Color.primary : tint)
                    .widgetAccentable().lineLimit(titleLines).minimumScaleFactor(0.75)
            }
            Text(time).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rectangularHeading: String {
        switch kind {
        case .course, .exam: return detail
        case .electricity: return "剩余电量"
        case .holiday: return "假期倒计时"
        }
    }
}

struct WatchCourseWidget: Widget {
    private var preview: WatchSnapshot {
        let now = Date()
        var snapshot = WatchSnapshot.empty
        snapshot.loggedIn = true
        snapshot.lessons = [.init(id: "preview", name: "高等数学", room: "5B502", fullRoom: "",
                                  teacher: "", periods: "", start: now.addingTimeInterval(-42 * 60),
                                  end: now.addingTimeInterval(8 * 60), colorIndex: 4)]
        return snapshot
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchCourse", provider: WatchWidgetProvider(preview: preview, includesCourseProgress: true)) {
            WatchCourseWidgetView(entry: $0)
        }
        .configurationDisplayName("当前／下一节课")
        .description("查看教室、课程时间和进度。")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

private struct WatchCourseWidgetView: View {
    let entry: WatchWidgetEntry
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        if !redactionReasons.contains(.placeholder), let progress = entry.courseProgress,
           let lesson = progress.lesson, let interval = progress.progressInterval {
            WatchCourseProgressView(lesson: lesson, previousRoom: progress.previous?.displayRoom,
                                    minutesUntilClass: progress.minutesUntilClass, interval: interval)
        } else {
            WatchComplicationView(entry: entry, kind: .course)
        }
    }
}

private struct WatchCourseProgressView: View {
    let lesson: WatchSnapshot.Lesson
    let previousRoom: String?
    let minutesUntilClass: Int?
    let interval: ClosedRange<Date>
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redactionReasons

    private var tint: Color { CampusCourseColors.color(index: lesson.colorIndex) }
    private var countdownLabel: String { minutesUntilClass == nil ? "距下课" : "距上课" }
    private var countdown: Text { Text(timerInterval: interval, countsDown: true, showsHours: false) }

    var body: some View {
        Group {
            if family == .accessoryInline {
                Label {
                    Text("\(countdownLabel) \(countdown)")
                } icon: {
                    Image(systemName: "book.closed.fill")
                }
                .unredacted()
            } else {
                card
            }
        }
        .containerBackground(family == .accessoryRectangular ? Color(white: 0.17) : .clear, for: .widget)
        .accessibilityElement(children: .combine)
        .widgetURL(URL(string: "xatuwatch://courses"))
    }

    private var card: some View {
        let showLessonDetails = !redactionReasons.contains(.privacy)
        return GeometryReader { bounds in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Group {
                        if showLessonDetails {
                            Text(lesson.name).privacySensitive()
                        } else {
                            Text("课程进度").unredacted()
                        }
                    }
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if minutesUntilClass != nil || showLessonDetails {
                        Group {
                            if let minutes = minutesUntilClass {
                                Text("\(minutes)分钟").unredacted()
                            } else {
                                Text(lesson.displayRoom).privacySensitive()
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .watchCapsule(tint: tint)
                        .widgetAccentable()
                        .frame(maxWidth: bounds.size.width * (minutesUntilClass == nil ? 0.44 : 0.53), alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Spacer(minLength: 0)
                if minutesUntilClass != nil {
                    Group {
                        if showLessonDetails {
                            HStack(spacing: 5) {
                                if let previousRoom, previousRoom != lesson.displayRoom {
                                    Text(previousRoom)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(tint)
                                        .widgetAccentable()
                                        .accessibilityHidden(true)
                                }
                                Text(lesson.displayRoom)
                                    .foregroundStyle(tint)
                                    .widgetAccentable()
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .privacySensitive()
                        } else {
                            Text("距上课").foregroundStyle(.secondary).unredacted()
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                } else {
                    HStack(spacing: 3) {
                        Text(countdownLabel).foregroundStyle(.secondary).unredacted()
                        Group {
                            if #available(watchOS 11, *) {
                                Text(.currentDate, format: .offset(to: lesson.end, allowedFields: [.minute], sign: .never))
                            } else {
                                Text(lesson.end, style: .relative)
                            }
                        }
                        .foregroundStyle(tint)
                        .widgetAccentable()
                        .unredacted()
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                progressBar
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
        }
    }

    private var progressBar: some View {
        ProgressView(timerInterval: interval, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(tint)
        .frame(height: 4)
        .background(tint.opacity(0.3), in: Capsule())
        .clipShape(Capsule())
        .widgetAccentable()
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
struct WatchExamWidget: Widget {
    private var preview: WatchSnapshot {
        var snapshot = WatchSnapshot.empty
        let calendar = WatchSnapshot.campusCalendar
        let day = calendar.date(byAdding: .day, value: 7, to: Date())!
        let date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        snapshot.loggedIn = true
        snapshot.exams = [.init(id: "exam", name: "数据结构", start: date, end: date.addingTimeInterval(7200),
                                time: "09:00–11:00", room: "", seat: "", note: "")]
        return snapshot
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchExam", provider: WatchWidgetProvider(preview: preview)) {
            WatchComplicationView(entry: $0, kind: .exam)
        }
        .configurationDisplayName("考试倒计时")
        .description("查看下一场考试，轻点打开手表考试安排。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct WatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchCourseWidget()
        WatchElectricityWidget()
        WatchHolidayWidget()
        WatchExamWidget()
    }
}
