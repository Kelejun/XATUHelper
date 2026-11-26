import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - iPad 超大尺寸校园总览小组件

struct CampusOverviewProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CourseEntry {
        CourseEntry(date: Date(), snapshot: PreviewData.snapshot, showTomorrow: false)
    }

    func snapshot(for configuration: CourseWidgetConfigIntent, in context: Context) async -> CourseEntry {
        let now = Date()
        let snapshot = WidgetStore.read() ?? (context.isPreview ? PreviewData.snapshot : .empty)
        return CourseEntry(
            date: now,
            snapshot: snapshot.resolved(at: now),
            showTomorrow: configuration.showTomorrow
        )
    }

    func timeline(for configuration: CourseWidgetConfigIntent, in context: Context) async -> Timeline<CourseEntry> {
        let now = Date()
        let snapshot = WidgetStore.read() ?? .empty
        var dates = (0...24).map { now.addingTimeInterval(Double($0) * 3600) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let startOfToday = calendar.startOfDay(for: now)

        for offset in 0...1 {
            let day = calendar.date(byAdding: .day, value: offset, to: startOfToday)!
            dates.append(day)
            for course in snapshot.resolved(at: day).courses {
                dates.append(day.addingTimeInterval(Double(course.startMinutes * 60)))
                dates.append(day.addingTimeInterval(Double(course.endMinutes * 60)))
            }
        }

        dates.append(contentsOf: snapshot.examTimelineDates(after: now, days: 2))

        let entries = Set(dates.filter { $0 >= now }).sorted().map { date in
            CourseEntry(
                date: date,
                snapshot: snapshot.resolved(at: date),
                showTomorrow: configuration.showTomorrow
            )
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600)))
    }
}

struct CampusOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "CampusOverviewWidget",
            intent: CourseWidgetConfigIntent.self,
            provider: CampusOverviewProvider()
        ) { entry in
            CampusOverviewWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(tint: .blue) }
        }
        .configurationDisplayName("校园总览")
        .description("在一张超大卡片里同时查看课程、考试倒计时、宿舍电量与假期倒计时。")
        .supportedFamilies([.systemExtraLarge])
    }
}

// MARK: - 视图

struct CampusOverviewWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: CourseEntry

    var body: some View {
        if !entry.snapshot.loggedIn {
            loggedOutView
        } else {
            HStack(spacing: 12) {
                coursePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 10) {
                    examPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: 10) {
                        electricityPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        breakPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 未登录状态

    private var loggedOutView: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill")
                        .foregroundStyle(.blue)
                    Text("XATune")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 4)

                Text("校园日常，一眼掌握")
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("打开 App 登录，同步课程、考试、宿舍电量与假期倒计时。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                Label("打开 App 登录", systemImage: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    placeholderBadge(icon: "calendar", title: "课程安排", tint: .blue)
                    placeholderBadge(icon: "pencil.and.list.clipboard", title: "考试倒计时", tint: CampusFeatureColors.exam)
                }
                HStack(spacing: 10) {
                    placeholderBadge(icon: "bolt.fill", title: "宿舍电量", tint: .orange)
                    placeholderBadge(icon: "sun.horizon.fill", title: "假期倒计时", tint: .teal)
                }
            }
            .frame(maxWidth: 260, maxHeight: .infinity)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholderBadge(icon: String, title: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(tint: tint))
        .overlay(panelBorder(tint: tint))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 左侧：课程面板

    private var todayRemaining: [WidgetSnapshot.Course] {
        let minutes = WidgetSnapshot.minutes(of: entry.date)
        return entry.snapshot.courses.filter { $0.endMinutes > minutes }
    }

    private var showingTomorrow: Bool {
        entry.showTomorrow && todayRemaining.isEmpty
    }

    private var visibleCourses: [WidgetSnapshot.Course] {
        showingTomorrow ? (entry.snapshot.tomorrowCourses ?? []) : todayRemaining
    }

    private var courseEmptyText: String {
        if showingTomorrow { return "明天没课" }
        return entry.snapshot.courses.isEmpty ? "今天没课" : "今天的课上完了"
    }

    private var courseHeaderText: String {
        if showingTomorrow {
            let label = WidgetSnapshot.weekdayLabel(entry.snapshot.tomorrowWeekday ?? 0)
            return label.isEmpty ? "明天" : "\(label) · 明天"
        }
        return entry.snapshot.week > 0
            ? "\(entry.snapshot.weekdayLabel) · 第 \(entry.snapshot.week) 周"
            : entry.snapshot.weekdayLabel
    }

    private var coursePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(courseHeaderText)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(showingTomorrow ? "明日课程" : "今日课程")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(colorScheme == .dark ? 0.20 : 0.10), in: Capsule())
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)

            if let course = visibleCourses.first {
                let accent = CourseWidgetView.color(for: course)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(WidgetSnapshot.clock(course.startMinutes))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                        Spacer(minLength: 4)
                        Text(courseStatus(course))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accent.opacity(colorScheme == .dark ? 0.22 : 0.12), in: Capsule())
                            .lineLimit(1)
                    }

                    Text(course.name)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    if !course.room.isEmpty {
                        Label(course.room, systemImage: "location.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Rectangle()
                    .fill(.primary.opacity(0.08))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    if visibleCourses.count > 1 {
                        HStack {
                            Text("接下来")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if visibleCourses.count > 3 {
                                Text("还有 \(visibleCourses.count - 3) 节")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(visibleCourses.dropFirst().prefix(2)) { next in
                            upcomingCourseRow(next)
                        }
                    } else {
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("之后没有课程")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.blue)
                    Text(courseEmptyText)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("留点时间给自己")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(tint: .blue))
        .overlay(panelBorder(tint: .blue))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .privacySensitive()
    }

    private func upcomingCourseRow(_ course: WidgetSnapshot.Course) -> some View {
        let accent = CourseWidgetView.color(for: course)
        return HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("\(WidgetSnapshot.clock(course.startMinutes))–\(WidgetSnapshot.clock(course.endMinutes))")
                        .foregroundStyle(accent)
                        .monospacedDigit()
                    if !course.room.isEmpty {
                        Text(course.room)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)

                Text(course.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
        }
    }

    private func courseStatus(_ course: WidgetSnapshot.Course) -> String {
        let minutes = WidgetSnapshot.minutes(of: entry.date)
        return !showingTomorrow && minutes >= course.startMinutes
            ? "正在上课 · \(WidgetSnapshot.clock(course.endMinutes)) 下课"
            : "下一节 · \(WidgetSnapshot.clock(course.endMinutes)) 下课"
    }

    // MARK: - 右上：考试倒计时面板

    private var nextExam: WidgetSnapshot.Exam? { entry.snapshot.nextExam }

    private var followingExams: ArraySlice<WidgetSnapshot.Exam> {
        (entry.snapshot.upcomingExams ?? []).dropFirst().prefix(2)
    }

    private var examPanel: some View {
        let tint = CampusFeatureColors.exam
        let totalCount = entry.snapshot.upcomingExams?.count ?? (nextExam == nil ? 0 : 1)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "pencil.and.list.clipboard")
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text("考试倒计时")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if totalCount > 1 {
                    Text("共 \(totalCount) 场")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)

            if let exam = nextExam {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            let days = exam.days ?? 0
                            Text(days <= 0 ? "今天" : "\(days)")
                                .font(.system(size: days <= 0 ? 26 : 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(tint)
                                .minimumScaleFactor(0.65)
                            if days > 0 {
                                Text("天")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)

                        Text(exam.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if let detail = examDetail(exam) {
                            Text(detail)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(width: 1)

                    VStack(alignment: .leading, spacing: 5) {
                        if followingExams.isEmpty {
                            Text("考场信息")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Label(examRoom(exam) ?? "考场待定", systemImage: "location.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            if let seat = examSeat(exam) {
                                Text(seat)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("后续考试")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            ForEach(Array(followingExams.indices), id: \.self) { index in
                                let item = followingExams[index]
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(examDetail(item) ?? "")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(tint)
                                        .lineLimit(1)
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("暂无待考科目")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text("打开 App 查看考试安排")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(tint: tint))
        .overlay(panelBorder(tint: tint))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .privacySensitive()
    }

    private func examDetail(_ exam: WidgetSnapshot.Exam) -> String? {
        guard let date = exam.date else { return nil }
        var format = Date.FormatStyle.dateTime.month().day()
        format.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return [date.formatted(format), exam.startTime].compactMap { $0 }.joined(separator: " · ")
    }

    private func examRoom(_ exam: WidgetSnapshot.Exam) -> String? {
        guard let room = exam.room?.trimmingCharacters(in: .whitespacesAndNewlines), !room.isEmpty else { return nil }
        return room
    }

    private func examSeat(_ exam: WidgetSnapshot.Exam) -> String? {
        guard let seat = exam.seat?.trimmingCharacters(in: .whitespacesAndNewlines), !seat.isEmpty else { return nil }
        return "座位 " + seat
    }

    // MARK: - 右下左：宿舍电量面板

    private var isLowElectricity: Bool { (entry.snapshot.balance ?? .infinity) < 10 }

    private var electricityUpdateText: String {
        guard let updated = entry.snapshot.balanceUpdatedAt else { return "尚无记录" }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(updated, inSameDayAs: entry.date)
            ? "HH:mm 更新" : "M/d HH:mm"
        return formatter.string(from: updated)
    }

    private var electricityPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("宿舍电量")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)

            Spacer(minLength: 4)

            if let balance = entry.snapshot.balance {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.2f", balance))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .layoutPriority(1)
                    Text("度")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(isLowElectricity ? Color.orange : Color.primary)
                .lineLimit(1)

                Text(isLowElectricity ? "电量偏低，记得充值" : "剩余可用电量")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isLowElectricity ? Color.orange : Color.secondary)
                    .lineLimit(1)
            } else {
                Text("待查询")
                    .font(.system(size: 22, weight: .semibold))
                Text("打开 App 查询电量")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(alignment: .bottom, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    if let room = entry.snapshot.roomName, !room.isEmpty {
                        Label(room, systemImage: "building.2")
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    Text(electricityUpdateText)
                        .font(.system(size: 9))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button(intent: RefreshElectricityIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.primary.opacity(0.07), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新电量")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(tint: .orange))
        .overlay(panelBorder(tint: .orange))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .privacySensitive()
    }

    // MARK: - 右下右：假期倒计时面板

    private var breakPanel: some View {
        let item = entry.snapshot.upcomingBreak
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(.teal)
                    .accessibilityHidden(true)
                Text("假期倒计时")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)

            Spacer(minLength: 4)

            if let item {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(item.days <= 0 ? "今天" : "\(item.days)")
                        .font(.system(size: item.days <= 0 ? 26 : 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.teal)
                        .minimumScaleFactor(0.6)
                    if item.days > 0 {
                        Text("天")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)

                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.teal)
                Text("期待下一次放假")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Text(item.map { BreakWidgetView.formatBreakDate($0.date) } ?? "打开 App 更新校历")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(tint: .teal))
        .overlay(panelBorder(tint: .teal))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 面板视觉样式

    private func panelBackground(tint: Color) -> some View {
        ZStack {
            Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035)
            LinearGradient(
                colors: [
                    tint.opacity(colorScheme == .dark ? 0.14 : 0.09),
                    tint.opacity(0.02),
                    .clear
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }

    private func panelBorder(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(tint.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 0.75)
    }
}
