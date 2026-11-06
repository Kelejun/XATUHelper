import SwiftUI

/// 宽屏侧边栏与窄屏校园页共用的目的地。
enum CampusPage: String, Identifiable, Hashable {
    case home, timetable, exam, grade, plan, info, electricity, calendar, netfee, checkin, leave, ehall, jwgl, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .timetable: return "课程表"
        case .exam: return "考试安排"
        case .grade: return "成绩"
        case .plan: return "学业完成情况"
        case .info: return "校园服务"
        case .electricity: return "电费"
        case .calendar: return "校历"
        case .netfee: return "校园网充值"
        case .checkin: return "签到"
        case .leave: return "请销假"
        case .ehall: return "一网通办"
        case .jwgl: return "教务系统"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .timetable: return "calendar"
        case .exam: return "calendar.badge.clock"
        case .grade: return "chart.bar.xaxis"
        case .plan: return "graduationcap"
        case .info: return "building.columns"
        case .electricity: return "bolt"
        case .calendar: return "calendar.badge.checkmark"
        case .netfee: return "wifi"
        case .checkin: return "checkmark.seal"
        case .leave: return "doc.text"
        case .ehall: return "square.grid.2x2"
        case .jwgl: return "graduationcap"
        case .settings: return "gearshape"
        }
    }

    var webURL: String? {
        switch self {
        case .netfee: return "https://self.xatu.edu.cn/Self/sso/packageChange"
        case .checkin: return "https://ehall.xatu.edu.cn/xsfw/sys/swmqdzsapp/*default/index.do#/jrqd"
        case .leave: return "https://ehall.xatu.edu.cn/xsfw/sys/swmxsqjapp/*default/index.do?wxType=1"
        case .ehall: return "https://ywtb.xatu.edu.cn/"
        case .jwgl: return "http://jwgl2018.xatu.edu.cn/"
        default: return nil
        }
    }

}

private struct CampusSidebarToggleKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct CampusNavigationKey: EnvironmentKey {
    static let defaultValue: ((CampusPage) -> Void)? = nil
}

extension EnvironmentValues {
    var campusSidebarToggle: (() -> Void)? {
        get { self[CampusSidebarToggleKey.self] }
        set { self[CampusSidebarToggleKey.self] = newValue }
    }

    /// 主导航路由，宽窄窗口之间共享目的地。
    var campusNavigation: ((CampusPage) -> Void)? {
        get { self[CampusNavigationKey.self] }
        set { self[CampusNavigationKey.self] = newValue }
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
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: Tab = .home
    @State private var timetableWeek: Int?
    @State private var showsSettings = false
    @State private var sidebarSelection: CampusPage? = .home
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum Tab: Hashable {
        case home, timetable, info
    }

    private var usesWorkspace: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesWorkspace {
                workspace
                    .environment(\.campusNavigation, { sidebarSelection = $0 })
                    .environment(\.campusSidebarToggle, toggleSidebar)
            } else {
                tabs
            }
        }
        .onChange(of: sidebarSelection) { _, page in
            guard let page else { return }
            preferredCompactColumn = .detail
            selection = page == .home ? .home : page == .timetable ? .timetable : .info
        }
        .onChange(of: selection) { _, tab in
            guard !usesWorkspace else { return }
            switch tab {
            case .home: sidebarSelection = .home
            case .timetable: sidebarSelection = .timetable
            case .info:
                if sidebarSelection == .home || sidebarSelection == .timetable {
                    sidebarSelection = .info
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await handlePendingRefresh()
            await app.startupRefreshIfNeeded()
            app.publishWidgetSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: RefreshRequest.notification)) { _ in
            Task { await handlePendingRefresh() }
        }
    }

    private var workspace: some View {
        // 系统负责在分屏和窄窗口中折叠侧边栏，保留当前目的地和返回路径。
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            List(selection: $sidebarSelection) {
                Section("日常") {
                    sidebarLink(.home)
                    sidebarLink(.timetable)
                }
                Section("教务") {
                    sidebarLink(.exam)
                    sidebarLink(.grade)
                    sidebarLink(.plan)
                    sidebarLink(.calendar)
                }
                Section("生活") {
                    sidebarLink(.electricity)
                    sidebarLink(.netfee)
                    sidebarLink(.checkin)
                    sidebarLink(.leave)
                }
                Section("杂项") {
                    sidebarLink(.ehall)
                    sidebarLink(.jwgl)
                }
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationTitle("XATune")
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
        if let url = page.webURL {
            WebSheet(title: page.title, urlString: url, showsCloseButton: !usesWorkspace, showsSidebarToggle: true, onClose: { sidebarSelection = .info })
                .id(page)
        } else {
            switch page {
            case .home: HomeView()
            case .timetable: TimetableView(visibleWeek: $timetableWeek)
            case .info:
                InfoView()
                    .environment(\.campusNavigation, { sidebarSelection = $0 })
            default:
                NavigationStack {
                    servicePage(page)
                        .campusSidebarToolbar()
                        .toolbar {
                            if !usesWorkspace {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button { sidebarSelection = .info } label: {
                                        Label("校园", systemImage: "chevron.left")
                                    }
                                }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func servicePage(_ page: CampusPage) -> some View {
        switch page {
        case .exam: ExamView()
        case .grade: GradeView()
        case .plan: PlanView()
        case .electricity: ElectricityView()
        case .calendar: SchoolCalendarView()
        case .settings: SettingsContent()
        default: InfoView()
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            HomeView()
                .environment(\.campusNavigation, { sidebarSelection = $0 })
                .tabItem { Label("首页", systemImage: "house") }
                .tag(Tab.home)
            TimetableView(visibleWeek: $timetableWeek)
                .tabItem { Label("课程表", systemImage: "calendar") }
                .tag(Tab.timetable)
            page(sidebarSelection == .home || sidebarSelection == .timetable ? .info : sidebarSelection ?? .info)
                .tabItem { Label("校园", systemImage: "building.columns") }
                .tag(Tab.info)
        }
    }

    private func handlePendingRefresh() async {
        guard !app.isDemoMode else { return }
        guard RefreshRequest.pendingElectricityRefresh() else { return }
        RefreshRequest.clearElectricityRefresh()
        await app.refreshElectricity()
        app.publishWidgetSnapshot()
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
