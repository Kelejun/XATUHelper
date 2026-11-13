import SwiftUI

@main
struct XatuHelperApp: App {
    @UIApplicationDelegateAdaptor(ElectricityRefreshAppDelegate.self) private var delegate
    @StateObject private var app: AppState
    @StateObject private var announcements = AnnouncementCenter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let state = AppState()
        _app = StateObject(wrappedValue: state)
        // Activate even for a background launch triggered by the paired watch.
        PhoneWatchBridge.shared.start(app: state)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .environmentObject(announcements)
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
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var announcements: AnnouncementCenter

    var body: some View {
        Group {
            if app.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.isLoggedIn)
        .background {
            AnnouncementNotice(center: announcements,
                canPresent: scenePhase == .active && app.inAppNotice == nil &&
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
    }
}
