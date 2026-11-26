import ActivityKit
import SwiftUI
import WidgetKit

@main
struct XatuHelperApp: App {
    @UIApplicationDelegateAdaptor(ElectricityRefreshAppDelegate.self) private var delegate
    @StateObject private var app: AppState
    @AppStorage(CourseActivityController.beforeKey) private var beforeClass = false
    @AppStorage(CourseActivityController.duringKey) private var duringClass = false
    @AppStorage(CourseActivityController.beforeLeadKey) private var beforeClassLead = CourseActivityController.defaultBeforeLeadMinutes
    @AppStorage(CourseActivityController.beforeExamKey) private var beforeExam = false
    @AppStorage(CourseActivityController.examLeadKey) private var examActivityLead = CourseActivityController.defaultExamLeadMinutes
    @StateObject private var permissionReview: NotificationPermissionReview
    @StateObject private var announcements = AnnouncementCenter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CourseActivityController.migratePreferences()
        let state = AppState()
        _permissionReview = StateObject(wrappedValue: NotificationPermissionReview(hasCachedAccount: state.isLoggedIn))
        _app = StateObject(wrappedValue: state)
        // Activate even for a background launch triggered by the paired watch.
        PhoneWatchBridge.shared.start(app: state)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .environmentObject(announcements)
                .environmentObject(permissionReview)
                .onChange(of: [beforeClass, duringClass, beforeExam]) { _, _ in
                    CourseActivityController.shared.refresh()
                }
                .onChange(of: [beforeClassLead, examActivityLead]) { _, _ in
                    CourseActivityController.shared.refresh()
                }
                .task(id: scenePhase) {
                    CourseActivityController.shared.setForeground(scenePhase == .active)
                    guard scenePhase == .active else { return }
                    await Self.runPromoCaptureIfNeeded(app: app)
                    await NotificationService.clearExpiredClassReminders()
                }
        }
        .backgroundTask(.appRefresh(BackgroundElectricityRefresh.identifier)) {
            await app.performBackgroundElectricityRefresh()
        }
        .onChange(of: app.isLoggedIn) { _, _ in
            app.scheduleBackgroundElectricityRefresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // 退到后台时把这一次运行里新拿到的 cookie 一起存下来，
            // 这样下次冷启动能接着用，不用重新登录。
            if phase == .active {
                Task { await announcements.refresh() }
                PhoneWatchBridge.shared.start(app: app)
                PhoneWatchBridge.shared.publish(force: true)
                BackgroundElectricityRefresh.clearExitReminder(includingTests: false)
            }
            if phase == .active || phase == .background {
                app.scheduleBackgroundElectricityRefresh()
            }
            if phase == .background || phase == .inactive {
                PhoneWatchBridge.shared.publish()
                CookieVault.pinAndSave()
            }
        }
    }

    @MainActor
    private static func runPromoCaptureIfNeeded(app: AppState) async {
        let args = ProcessInfo.processInfo.arguments
        let isSingle = args.contains("-promo-live-single")
        let isDual = args.contains("-promo-live-dual")
        guard isSingle || isDual else { return }

        app.showsDemoAccount = true

        // Publish real demo exam countdown snapshot for Home Screen widgets
        let now = Date()
        var cal = WatchSnapshot.campusCalendar
        let d1 = cal.date(byAdding: .day, value: 11, to: cal.startOfDay(for: now))!.addingTimeInterval(9 * 3600)
        let d2 = cal.date(byAdding: .day, value: 15, to: cal.startOfDay(for: now))!.addingTimeInterval(14 * 3600)
        let d3 = cal.date(byAdding: .day, value: 18, to: cal.startOfDay(for: now))!.addingTimeInterval(9 * 3600)
        let exams: [WidgetSnapshot.Exam] = [
            WidgetSnapshot.Exam(title: "计算机网络", date: d1, days: 11, end: d1.addingTimeInterval(7200), startTime: "09:00", room: "教3-109", seat: "16"),
            WidgetSnapshot.Exam(title: "数据结构", date: d2, days: 15, end: d2.addingTimeInterval(7200), startTime: "14:00", room: "教2-210", seat: "08"),
            WidgetSnapshot.Exam(title: "大学英语", date: d3, days: 18, end: d3.addingTimeInterval(7200), startTime: "09:00", room: "教1-201", seat: "24")
        ]
        let snap = WidgetSnapshot(
            generatedAt: now, week: 8, weekday: 4, courses: [],
            balance: 52.77, balanceUpdatedAt: now, roomName: "320宿舍",
            upcomingBreak: nil, nextExam: exams.first, upcomingExams: exams, loggedIn: true
        )
        WidgetStore.write(snap)
        WidgetCenter.shared.reloadAllTimelines()

        // End any existing activities
        for act in Activity<CourseActivityAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }

        // Start real Course Live Activity (课间换教室: 高等数学 教2-302 -> 教1-201)
        let prevLesson = WatchSnapshot.Lesson(
            id: "promo-prev", name: "大学英语", room: "教2-302", fullRoom: "教2-302",
            teacher: "李老师", periods: "1-2节", start: now.addingTimeInterval(-100 * 60),
            end: now.addingTimeInterval(-10 * 60), colorIndex: 1
        )
        let nextLesson = WatchSnapshot.Lesson(
            id: "promo-math", name: "高等数学", room: "教1-201", fullRoom: "教1-201",
            teacher: "张老师", periods: "3-4节", start: now.addingTimeInterval(5 * 60 + 2),
            end: now.addingTimeInterval(105 * 60), colorIndex: 0
        )
        let ws1 = WatchSnapshot(
            generatedAt: now, accountID: "promo", loggedIn: true, semester: "2026-2027学年1学期",
            weekOneMonday: now, timetableUpdatedAt: now, examsUpdatedAt: now,
            lessons: [prevLesson, nextLesson], exams: [], balance: nil, balanceUpdatedAt: nil,
            roomName: nil, holidays: []
        )
        if let slot1 = CourseActivitySlot(snapshot: ws1, at: now, beforeClass: true, duringClass: true) {
            let attr1 = CourseActivityAttributes(accountID: "promo", lessonID: "promo-math", scheduledStart: nil)
            let state1 = CourseActivityAttributes.ContentState(slot: slot1, prefersDarkAppearance: true)
            _ = try? Activity<CourseActivityAttributes>.request(
                attributes: attr1,
                content: ActivityContent(state: state1, staleDate: nextLesson.start)
            )
        }

        if isDual {
            let liveLesson = WatchSnapshot.Lesson(
                id: "promo-net", name: "计算机网络", room: "教3-109", fullRoom: "教3-109",
                teacher: "王老师", periods: "3-4节", start: now.addingTimeInterval(-32 * 60),
                end: now.addingTimeInterval(18 * 60 + 2), colorIndex: 2
            )
            let ws2 = WatchSnapshot(
                generatedAt: now, accountID: "promo", loggedIn: true, semester: "2026-2027学年1学期",
                weekOneMonday: now, timetableUpdatedAt: now, examsUpdatedAt: now,
                lessons: [liveLesson], exams: [], balance: nil, balanceUpdatedAt: nil,
                roomName: nil, holidays: []
            )
            if let slot2 = CourseActivitySlot(snapshot: ws2, at: now, beforeClass: false, duringClass: true) {
                let attr2 = CourseActivityAttributes(accountID: "promo", lessonID: "promo-net", scheduledStart: nil)
                let state2 = CourseActivityAttributes.ContentState(slot: slot2, prefersDarkAppearance: true)
                _ = try? Activity<CourseActivityAttributes>.request(
                    attributes: attr2,
                    content: ActivityContent(state: state2, staleDate: liveLesson.end)
                )
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var announcements: AnnouncementCenter
    @EnvironmentObject private var permissionReview: NotificationPermissionReview

    var body: some View {
        Group {
            if app.isLoggedIn {
                MainTabView()
                    .background {
                        NotificationPermissionReviewPresenter(review: permissionReview,
                            canPresent: scenePhase == .active && !app.isDemoMode && app.inAppNotice == nil &&
                                !app.showsWebLogin && !app.showsDemoAccount && app.deepLink == nil)
                    }
            } else {
                LoginView()
            }
        }
        .onChange(of: colorScheme, initial: true) { _, scheme in
            CourseActivityController.shared.setDarkAppearance(scheme == .dark)
        }
        .animation(.easeInOut(duration: 0.2), value: app.isLoggedIn)
        .background {
            AnnouncementNotice(center: announcements,
                canPresent: (!app.isLoggedIn || !permissionReview.pending) && scenePhase == .active && app.inAppNotice == nil &&
                    !app.showsWebLogin && !app.showsDemoAccount && app.deepLink == nil)
        }
        .task { await announcements.refresh() }
        .background {
            InAppNotificationPresenter(
                notice: app.inAppNotice,
                onTap: {
                    guard let notice = app.inAppNotice else { return }
                    switch notice.kind {
                    case .exam: app.deepLink = .exam
                    case .grade: app.deepLink = .grade
                    case .loginFailure, .sessionExpired: break
                    }
                    app.dismissNotice()
                },
                onClose: app.dismissNotice
            )
            .frame(width: 0, height: 0)
        }
        .fullScreenCover(isPresented: $app.showsDemoAccount) {
            DemoAccountView()
                .onDisappear { CoursePalette.register(app.occurrences.map(\.courseKey)) }
        }
        .sheet(isPresented: $app.showsWebLogin, onDismiss: app.cancelWebLogin) {
            CASWebLoginSheet()
        }
        .sheet(item: $app.deepLink) { link in
            NavigationStack {
                Group {
                    switch link {
                    case .exam:
                        ExamView()
                    case .grade:
                        GradeView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("完成") { app.deepLink = nil }
                    }
                }
            }
        }
        .environmentObject(announcements)
        .environment(\.notificationReviewPending, permissionReview.pending)
        .environment(\.courseReminderSuppressed, permissionReview.dismissedInSession)
    }
}
