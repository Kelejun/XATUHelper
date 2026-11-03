import SwiftUI

@main
struct XatuHelperApp: App {
    @UIApplicationDelegateAdaptor(ElectricityRefreshAppDelegate.self) private var delegate
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
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
                BackgroundElectricityRefresh.clearExitReminder()
            }
            if phase == .active || phase == .background {
                app.scheduleBackgroundElectricityRefresh()
            }
            if phase == .background || phase == .inactive {
                CookieVault.pinAndSave()
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if app.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.isLoggedIn)
        .overlay(alignment: .top) {
            if let notice = app.inAppNotice {
                InAppNotificationLayer(
                    notice: notice,
                    onTap: {
                        switch notice.kind {
                        case .exam: app.deepLink = .exam
                        case .grade: app.deepLink = .grade
                        case .loginFailure: break
                        }
                        app.dismissNotice()
                    },
                    onClose: { app.dismissNotice() }
                )
                .animation(InAppNotificationLayer.bannerAnimation, value: app.inAppNotice)
            }
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
    }
}
