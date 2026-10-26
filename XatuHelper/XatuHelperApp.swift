import SwiftUI

@main
struct XatuHelperApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
        }
        .onChange(of: scenePhase) { _, phase in
            // 退到后台时把这一次运行里新拿到的 cookie 一起存下来，
            // 这样下次冷启动能接着用，不用重新登录。
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
    }
}
