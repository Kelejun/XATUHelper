import SwiftUI

/// 登录后的主界面。底栏暂时只有首页和课程表两项。
struct MainTabView: View {
    @Environment(AppState.self) var app
    @State var selection: Tab = .home

    enum Tab: Hashable {
        case home
        case timetable
        case info
    }

    var body: some View {
        @Bindable var app = app
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag(Tab.home)

            TimetableView()
                .tabItem { Label("课程表", systemImage: "calendar") }
                .tag(Tab.timetable)

            InfoView()
                .tabItem { Label("校园", systemImage: "building.columns") }
                .tag(Tab.info)
        }
        .task {
            await app.startupRefreshIfNeeded()
            await handlePendingRefresh()
            app.publishWidgetSnapshot()
        }
        #if !os(Android)
        .onReceive(NotificationCenter.default.publisher(for: RefreshRequest.notification)) { _ in
            Task { await handlePendingRefresh() }
        }
        #endif
        .sheet(isPresented: $app.showsWebLogin) {
            CASWebLoginSheet()
        }
    }

    /// 小组件上的刷新按钮：先拉起 App，再在这里真正去查一次电费。
    private func handlePendingRefresh() async {
        guard RefreshRequest.pendingElectricityRefresh() else { return }
        RefreshRequest.clearElectricityRefresh()
        await app.refreshElectricity()
        app.publishWidgetSnapshot()
    }
}

#if !os(Android)
#Preview {
    MainTabView()
        .environment(AppState())
}
#endif

