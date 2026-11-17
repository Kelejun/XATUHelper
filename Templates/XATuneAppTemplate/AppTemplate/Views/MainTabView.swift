import SwiftUI

enum CampusPage: String, Identifiable, Hashable {
    case home, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }
}

private struct CampusSidebarToggleKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var campusSidebarToggle: (() -> Void)? {
        get { self[CampusSidebarToggleKey.self] }
        set { self[CampusSidebarToggleKey.self] = newValue }
    }
}

private struct CampusSidebarToolbar: ViewModifier {
    @Environment(\.campusSidebarToggle) private var toggle
    var enabled: Bool

    func body(content: Content) -> some View {
        content.toolbar {
            if enabled, let toggle {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: toggle) {
                        Image(systemName: "sidebar.left")
                    }
                    .accessibilityLabel("显示或隐藏侧边栏")
                }
            }
        }
    }
}

extension View {
    func campusSidebarToolbar(enabled: Bool = true) -> some View {
        modifier(CampusSidebarToolbar(enabled: enabled))
    }
}

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: Tab = .home
    @State private var showsSettings = false
    @State private var sidebarSelection: CampusPage? = .home
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum Tab: Hashable {
        case home, settings
    }

    private var usesWorkspace: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesWorkspace {
                workspace
                    .environment(\.campusSidebarToggle, toggleSidebar)
            } else {
                tabs
            }
        }
        .onChange(of: sidebarSelection) { _, page in
            guard let page else { return }
            preferredCompactColumn = .detail
            selection = page == .home ? .home : .settings
        }
        .onChange(of: selection) { _, tab in
            guard !usesWorkspace else { return }
            switch tab {
            case .home: sidebarSelection = .home
            case .settings: sidebarSelection = .settings
            }
        }
    }

    private var workspace: some View {
        // 系统负责在分屏和窄窗口中折叠侧边栏，保留当前目的地和返回路径。
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            List(selection: $sidebarSelection) {
                sidebarLink(.home)
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationTitle("AppTemplate")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    settingsButton
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        } detail: {
            page(sidebarSelection ?? .home)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
    }

    private var settingsButton: some View {
        Button { showsSettings = true } label: {
            settingsIcon
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("设置")
        .sheet(isPresented: $showsSettings) {
            SettingsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var settingsIcon: some View {
        if #available(iOS 26.0, *) {
            Image(systemName: "gearshape")
                .font(.system(size: 19))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Image(systemName: "gearshape")
                .font(.system(size: 19))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if horizontalSizeClass == .compact {
                preferredCompactColumn = preferredCompactColumn == .sidebar ? .detail : .sidebar
            } else {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        }
    }

    private func sidebarLink(_ page: CampusPage) -> some View {
        NavigationLink(value: page) {
            Label(page.title, systemImage: page.icon)
                .padding(.vertical, 3)
        }
    }

    @ViewBuilder
    private func page(_ page: CampusPage) -> some View {
        switch page {
        case .home: HomeView()
        case .settings:
            NavigationStack {
                SettingsContent()
                    .campusSidebarToolbar()
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag(Tab.home)
            page(.settings)
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    MainTabView()
}
