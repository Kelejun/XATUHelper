import SwiftUI

private enum WatchPage: Int, Hashable { case courses, exams, electricity, holiday }

struct WatchRootView: View {
    @EnvironmentObject private var receiver: WatchReceiver
    @State private var page: WatchPage = .courses
    @State private var navigationPath = NavigationPath()

    init() {
        #if DEBUG
        if WatchPreview.enabled && ProcessInfo.processInfo.arguments.contains("--watch-preview-exams-page") {
            _page = State(initialValue: .exams)
        }
        #endif
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TimelineView(.everyMinute) { context in
                Group {
                    if receiver.snapshot.loggedIn {
                        TabView(selection: $page) {
                            CoursePages(snapshot: receiver.snapshot, now: receiver.displayDate(context.date)).tag(WatchPage.courses)
                            WatchExamsView(snapshot: receiver.snapshot, now: receiver.displayDate(context.date)).tag(WatchPage.exams)
                            WatchElectricityView(snapshot: receiver.snapshot).tag(WatchPage.electricity)
                            WatchHolidayView(snapshot: receiver.snapshot, now: receiver.displayDate(context.date)).tag(WatchPage.holiday)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                        .ignoresSafeArea(.container, edges: .top)
                    } else {
                        ContentUnavailableView {
                            Label(receiver.waitingForData ? "正在同步" : "在 iPhone 上开始", systemImage: "iphone.and.arrow.forward")
                        } description: {
                            Text(receiver.waitingForData ? "课表正在从手机传来，请稍候。" : "打开 XATune 并登录，课程、考试、电费和校历将自动同步。")
                        }
                    }
                }

            }
            .toolbar(.hidden)
            .navigationDestination(for: WatchSnapshot.Lesson.self) { lesson in
                WatchLessonDetail(lesson: lesson).toolbar(.visible)
            }
            .onChange(of: receiver.cache.descriptor?.accountID) { _, _ in
                navigationPath = NavigationPath()
                page = .courses
            }
            .onChange(of: receiver.snapshot.loggedIn) { _, loggedIn in
                if !loggedIn { navigationPath = NavigationPath() }
            }
            .onOpenURL { url in
                navigationPath = NavigationPath()
                switch url.host {
                case "exams": page = .exams
                case "electricity": page = .electricity
                case "holiday": page = .holiday
                default: page = .courses
                }
            }
            .overlay(alignment: .bottom) {
                if let error = receiver.storageError {
                    Text(error).font(.caption2).foregroundStyle(.orange).padding(4)
                }
            }
        }
        .tint(.cyan)
    }
}

/// Page headings live in the page content, moving naturally in both pagers.
private struct WatchPageHeading: View {
    let title: String
    var tint: Color = .blue

    var body: some View {
        Text(title)
            .font(.title2).foregroundStyle(tint)
            .lineLimit(1).minimumScaleFactor(0.9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4).padding(.trailing, 42).padding(.bottom, 4)
    }
}

private struct CoursePages: View {
    let snapshot: WatchSnapshot
    let now: Date
    @State private var section = 0

    var body: some View {
        TabView(selection: $section) {
            WatchHomeView(snapshot: snapshot, now: now).tag(0)
            WatchTimetableView(snapshot: snapshot, now: now).tag(1)
            WatchTimetableView(snapshot: snapshot, now: now, dayOffset: 1).tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct WatchHomeView: View {
    let snapshot: WatchSnapshot
    let now: Date

    private var current: WatchSnapshot.Lesson? { snapshot.currentLesson(at: now) }
    private var next: WatchSnapshot.Lesson? { snapshot.nextLesson(at: now) }
    @ScaledMetric private var titleSize: CGFloat = 26
    @ScaledMetric private var captionSize: CGFloat = 12
    @ScaledMetric private var statusSize: CGFloat = 13

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
            ScrollView { content(compact: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func content(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 10) {
            WatchPageHeading(title: CampusGreeting.text(at: now))
            HStack(spacing: 5) {
                Text(WatchSnapshot.format(now, "M月d日 EEE"))
                Spacer(minLength: 0)
                Text(snapshot.week(at: now) > 0 ? "第\(snapshot.week(at: now))周" : "学期未开始")
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.blue.opacity(0.16), in: Capsule())
            }
            .font(.system(size: captionSize, weight: .medium))
            .foregroundStyle(.secondary).padding(.horizontal, 3)

            if let lesson = current ?? next {
                NavigationLink(value: lesson) { courseCard(lesson, compact: compact) }
                    .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sun.max").font(.title2.weight(.light)).foregroundStyle(.blue)
                    Text(snapshot.timetableUpdatedAt == nil ? "课表尚未同步" : "暂无后续课程")
                        .font(.headline)
                    Text(snapshot.timetableUpdatedAt == nil ? "在手机端加载课表后自动同步" : "留点时间给自己")
                        .font(.system(size: captionSize + 1)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }

            if let exam = snapshot.nearExam(at: now) {
                let title = WatchSnapshot.campusCalendar.isDate(exam.start, inSameDayAs: now)
                    ? "今日考试" : "\(WatchSnapshot.dayLabel(exam.start, relativeTo: now))考试"
                examSummary(exam, title: title, compact: compact)
            } else if current != nil, let next {
                summary(tint: CampusCourseColors.color(index: next.colorIndex), compact: compact) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("下一节").foregroundStyle(.secondary)
                            Spacer(minLength: 2)
                            Text("\(WatchSnapshot.campusCalendar.isDate(next.start, inSameDayAs: now) ? "" : WatchSnapshot.dayLabel(next.start, relativeTo: now) + " ")\(WatchSnapshot.clock(next.start))")
                                .foregroundStyle(CampusCourseColors.color(index: next.colorIndex))
                        }.font(.system(size: captionSize, weight: .medium))
                        Text("\(next.name) · \(next.room.isEmpty ? "教室待定" : next.room)")
                            .font(.system(size: captionSize + 1, weight: .semibold)).lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func courseCard(_ lesson: WatchSnapshot.Lesson, compact: Bool) -> some View {
        let tint = CampusCourseColors.color(index: lesson.colorIndex)
        let isCurrent = current != nil
        let today = WatchSnapshot.campusCalendar.isDate(lesson.start, inSameDayAs: now)
        return HStack(alignment: .top, spacing: compact ? 9 : 11) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: compact ? 3 : 9) {
                HStack(spacing: 4) {
                    Text(isCurrent ? "正在上课" : today ? "下一节课" : WatchSnapshot.dayLabel(lesson.start, relativeTo: now) + "的课")
                    Spacer(minLength: 0)
                    Text(lesson.periods)
                }
                .font(.system(size: statusSize, weight: .medium)).foregroundStyle(tint)

                Text(lesson.name)
                    .font(.system(size: compact ? titleSize - 2 : titleSize, weight: .bold))
                    .foregroundStyle(.primary).lineLimit(3).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Label(lesson.room.isEmpty ? "教室待定" : lesson.room, systemImage: "mappin")
                    .font(.system(size: compact ? 14 : 16, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)

                Text("\(WatchSnapshot.clock(lesson.start))–\(WatchSnapshot.clock(lesson.end))")
                    .font(.system(size: captionSize + 3, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                if !isCurrent && !today {
                    Text(snapshot.lessons(on: now).isEmpty ? "今日无课" : "今日课程已结束")
                        .font(.system(size: statusSize)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(compact ? 6 : 12)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func examSummary(_ exam: WatchSnapshot.Exam, title: String, compact: Bool) -> some View {
        summary(tint: .orange, compact: compact) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).foregroundStyle(.orange)
                    Spacer(minLength: 2)
                    Text(exam.time).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }.font(.system(size: captionSize, weight: .medium))
                Text("\(exam.name) · \(exam.room.isEmpty ? "考场待定" : exam.room)")
                    .font(.system(size: captionSize + 1, weight: .semibold)).lineLimit(2)
            }
        }
    }

    private func summary<Content: View>(tint: Color, compact: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4).padding(.vertical, compact ? 3 : 5)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private struct WatchTimetableView: View {
    let snapshot: WatchSnapshot
    let now: Date
    var dayOffset: Int = 0

    private var day: Date {
        WatchSnapshot.campusCalendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
    }
    private var title: String { dayOffset == 0 ? "今日课表" : "明日课表" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchPageHeading(title: title)
                Text("\(WatchSnapshot.format(day, "M月d日 EEEE")) · \(snapshot.lessons(on: day).count) 节安排")
                    .font(.caption2).foregroundStyle(.secondary)
                if snapshot.lessons(on: day).isEmpty {
                    Label(snapshot.timetableUpdatedAt == nil ? "课表尚未同步" : (dayOffset == 0 ? "今日无课" : "明日无课"), systemImage: "calendar")
                        .padding(.vertical)
                }
                ForEach(snapshot.lessons(on: day)) { lesson in
                    let tint = CampusCourseColors.color(index: lesson.colorIndex)
                    NavigationLink(value: lesson) {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(WatchSnapshot.clock(lesson.start))–\(WatchSnapshot.clock(lesson.end))")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(tint)
                                Text(lesson.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                Text(lesson.room.isEmpty ? "教室待定" : lesson.room).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(tint.opacity(lesson.start <= now && now < lesson.end ? 0.23 : 0.14),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    .opacity(lesson.end <= now ? 0.5 : 1)
                }
                WatchUpdateLabel(title: "课表更新", date: snapshot.timetableUpdatedAt)
                Text(snapshot.semester).font(.caption2).foregroundStyle(.tertiary)
            }.padding(.horizontal, 6).padding(.vertical, 8)
        }
    }
}

private struct WatchLessonDetail: View {
    let lesson: WatchSnapshot.Lesson
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(lesson.name).font(.title2.bold())
                Label(lesson.fullRoom.isEmpty ? "教室待定" : lesson.fullRoom, systemImage: "mappin")
                Label("\(WatchSnapshot.format(lesson.start, "M月d日 EEEE"))\n\(WatchSnapshot.clock(lesson.start))–\(WatchSnapshot.clock(lesson.end))", systemImage: "clock")
                Text(lesson.periods).foregroundStyle(.secondary)
                if !lesson.teacher.isEmpty { Label(lesson.teacher, systemImage: "person") }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
        }.navigationTitle("课程详情")
    }
}

private struct WatchExamsView: View {
    let snapshot: WatchSnapshot
    let now: Date
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchPageHeading(title: "考试安排", tint: .orange)
                if snapshot.upcomingExams(at: now).isEmpty {
                    Text(snapshot.examsUpdatedAt == nil ? "考试尚未同步" : "暂无考试安排").font(.title3.bold()).padding(.vertical, 8)
                }
                ForEach(snapshot.upcomingExams(at: now)) { exam in
                    VStack(alignment: .leading, spacing: 7) {
                        let days = WatchSnapshot.days(from: now, to: exam.start)
                        Text(days == 0 ? "今天考试" : "还有 \(days) 天").font(.caption).foregroundStyle(.orange)
                        Text(exam.name).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                        Text(WatchSnapshot.format(exam.start, "M月d日 EEEE")).font(.caption)
                        Text(exam.time.isEmpty ? "时间待定" : exam.time).font(.caption).foregroundStyle(.secondary)
                        Label(exam.room.isEmpty ? "考场待定" : exam.room, systemImage: "mappin").font(.caption)
                        if !exam.seat.isEmpty { Text("座位 \(exam.seat)").font(.caption) }
                        if !exam.note.isEmpty { Text(exam.note).font(.caption2).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
                WatchUpdateLabel(title: "考试更新", date: snapshot.examsUpdatedAt)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
    }
}

private struct WatchElectricityView: View {
    let snapshot: WatchSnapshot
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WatchPageHeading(title: "宿舍电费", tint: .yellow)
                Text("剩余电量").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(snapshot.balance ?? "—").font(.system(size: 42, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    Text("度").font(.callout).foregroundStyle(.secondary)
                }
                Text(snapshot.roomName ?? "请在手机端绑定宿舍").font(.callout)
                WatchUpdateLabel(title: "手机查询", date: snapshot.balanceUpdatedAt)
                Text("余额由 iPhone 查询后同步").font(.caption2).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 8)
        }
    }
}

private struct WatchHolidayView: View {
    let snapshot: WatchSnapshot
    let now: Date
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                WatchPageHeading(title: "假期倒计时", tint: .mint)
                if let holiday = snapshot.nextHoliday(at: now) {
                    Text(holiday.title).font(.title3.bold())
                    let days = WatchSnapshot.days(from: now, to: holiday.date)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(days == 0 ? "今天" : "\(days)")
                            .font(.system(size: 52, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                        if days > 0 { Text("天").foregroundStyle(.secondary) }
                    }
                    Text(WatchSnapshot.format(holiday.date, "yyyy年M月d日")).font(.caption).foregroundStyle(.secondary)
                    Text("日期依据手机端校历").font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("暂无假期日期").font(.title3.bold()).padding(.vertical, 20)
                    Text("请在手机端打开校历并更新").font(.caption).foregroundStyle(.secondary)
                }
                WatchUpdateLabel(title: "手机同步", date: snapshot.generatedAt)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 8)
        }
    }
}

private struct WatchUpdateLabel: View {
    let title: String
    let date: Date?
    var body: some View {
        Text(date.map { "\(title) \(WatchSnapshot.format($0, "M/d HH:mm"))" } ?? "\(title)：尚无数据")
            .font(.caption2).foregroundStyle(.secondary)
    }
}
