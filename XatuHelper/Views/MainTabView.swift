import SwiftUI

/// 登录后的主界面。底栏暂时只有首页和课程表两项。
struct MainTabView: View {
    @EnvironmentObject var app: AppState
    @State private var selection: Tab = .home

    enum Tab: Hashable {
        case home
        case timetable
        case info
    }

    var body: some View {
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
            await app.refreshElectricityIfNeeded()
        }
        .sheet(isPresented: $app.showsWebLogin) {
            CASWebLoginSheet()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
