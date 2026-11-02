import SwiftUI

/// 校园服务入口：手机使用卡片，iPad 使用分组服务列表。
struct InfoView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.campusNavigation) private var navigate
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesWorkspace: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    enum Entry: String, Identifiable, CaseIterable {
        case exam
        case grade
        case plan
        case bill
        case netfee
        case checkin
        case leave
        case calendar
        case jwgl
        case ehall
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .exam: return "考试安排"
            case .grade: return "成绩"
            case .plan: return "学业完成情况"
            case .bill: return "电费"
            case .netfee: return "校园网充值"
            case .checkin: return "签到"
            case .leave: return "请销假"
            case .calendar: return "校历"
            case .jwgl: return "教务系统"
            case .ehall: return "一网通办"
            case .settings: return "设置"
            }
        }

        var page: CampusPage? {
            switch self {
            case .exam: return .exam
            case .grade: return .grade
            case .plan: return .plan
            case .bill: return .electricity
            case .calendar: return .calendar
            case .settings: return .settings
            default: return nil
            }
        }

        var subtitle: String {
            switch self {
            case .exam: return "时间、考场、座位号"
            case .grade: return "每学期的课程成绩"
            case .plan: return "毕业要修多少学分"
            case .bill: return "宿舍还剩多少电费"
            case .netfee: return "续费、查套餐"
            case .checkin: return "按时点一下，别断签"
            case .leave: return "请假、销假都在这里"
            case .calendar: return "什么时候放假？"
            case .jwgl: return ""
            case .ehall: return ""
            case .settings: return ""
            }
        }

        var icon: String {
            switch self {
            case .exam: return "calendar.badge.clock"
            case .grade: return "chart.bar.fill"
            case .plan: return "list.bullet.rectangle.fill"
            case .bill: return "bolt.fill"
            case .netfee: return "wifi"
            case .checkin: return "checkmark.seal.fill"
            case .leave: return "doc.text.fill"
            case .calendar: return "calendar"
            case .jwgl: return "graduationcap.fill"
            case .ehall: return "square.grid.2x2.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var tint: Color {
            switch self {
            case .exam: return .orange
            case .grade: return .blue
            case .plan: return .green
            case .bill: return .yellow
            case .netfee: return .cyan
            case .checkin: return .pink
            case .leave: return .brown
            case .calendar: return .purple
            case .jwgl: return .teal
            case .ehall: return .indigo
            case .settings: return .gray
            }
        }
    }

    @State private var pending: Entry?
    @State private var showsCheckin = false
    @State private var showsSettings = false
    @State private var webLink: WebLink?

    private struct WebLink: Identifiable {
        let id = UUID()
        let title: String
        let urlString: String
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let available = max(0, min(width, 1080) - 40)
        let minimum: CGFloat = dynamicTypeSize.isAccessibilitySize ? 280 : 150
        let count = min(4, max(1, Int((available + 12) / (minimum + 12))))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    if usesWorkspace {
                        tabletServices(width: proxy.size.width)
                    } else {
                        VStack(alignment: .leading, spacing: 26) {
                            group("教务", entries: [.exam, .grade, .plan, .calendar], columns: columns(for: proxy.size.width))
                            group("生活", entries: [.bill, .netfee, .checkin, .leave], columns: columns(for: proxy.size.width))
                            group("杂项", entries: [.ehall, .jwgl], columns: columns(for: proxy.size.width))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 1080)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .campusSidebarToolbar()
            .navigationTitle(!usesWorkspace ? "校园" : "校园服务")
            .navigationBarTitleDisplayMode(!usesWorkspace ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .sheet(item: $webLink) { link in
                WebSheet(title: link.title, urlString: link.urlString)
            }
            .sheet(isPresented: $showsSettings) {
                SettingsSheet()
            }
            .sheet(isPresented: $showsCheckin) {
                WebSheet(
                    title: "签到",
                    urlString: "https://ehall.xatu.edu.cn/xsfw/sys/swmqdzsapp/*default/index.do#/jrqd"
                )
            }
            .alert(item: $pending) { entry in
                Alert(
                    title: Text(entry.title),
                    message: Text("这个还没做，下一版接上。"),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private func tabletServices(width: CGFloat) -> some View {
        let twoColumns = width >= 680 && !dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("校园服务").font(.largeTitle.bold())
                Text("教务查询、生活服务与常用网站")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: twoColumns ? 2 : 1), alignment: .leading, spacing: 28) {
                group("教务查询", entries: [.exam, .grade, .plan, .calendar], columns: [GridItem(.flexible())])
                group("生活服务", entries: [.bill, .netfee, .checkin, .leave], columns: [GridItem(.flexible())])
                group("常用网站", entries: [.ehall, .jwgl], columns: [GridItem(.flexible())])
            }
        }
        .padding(width >= 600 ? 28 : 20)
        .frame(maxWidth: 1180, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func group(_ title: String, entries: [Entry], columns: [GridItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.leading, 2)

            LazyVGrid(columns: columns, spacing: !usesWorkspace ? 12 : 0) {
                ForEach(entries) { entry in
                    if usesWorkspace, let page = entry.page, let navigate {
                        Button { navigate(page) } label: { card(entry) }
                            .buttonStyle(.plain)
                    } else if entry == .bill {
                        NavigationLink {
                            ElectricityView()
                        } label: {
                            card(entry)
                        }
                        .buttonStyle(.plain)
                    } else if entry == .exam {
                        NavigationLink {
                            ExamView()
                        } label: {
                            card(entry)
                        }
                        .buttonStyle(.plain)
                    } else if entry == .grade {
                        NavigationLink {
                            GradeView()
                        } label: {
                            card(entry)
                        }
                        .buttonStyle(.plain)
                    } else if entry == .plan {
                        NavigationLink {
                            PlanView()
                        } label: {
                            card(entry)
                        }
                        .buttonStyle(.plain)
                    } else if entry == .netfee {
                        Button {
                            webLink = WebLink(
                                title: "校园网充值",
                                urlString: "https://self.xatu.edu.cn/Self/sso/packageChange"
                            )
                        } label: {
                            card(entry)
                        }
                        .buttonStyle(.plain)
                    } else if entry == .checkin {
                        Button { showsCheckin = true } label: { card(entry) }
                            .buttonStyle(.plain)
                    } else if entry == .leave {
                        Button {
                            webLink = WebLink(
                                title: "请销假",
                                urlString: "https://ehall.xatu.edu.cn/xsfw/sys/swmxsqjapp/*default/index.do?wxType=1"
                            )
                        } label: {
                            card(entry)
                        }
                        .buttonStyle(.plain)
                    } else if entry == .calendar {
                        NavigationLink { SchoolCalendarView() } label: { card(entry) }
                            .buttonStyle(.plain)
                    } else if entry == .ehall {
                        Button {
                            webLink = WebLink(title: "一网通办", urlString: "https://ywtb.xatu.edu.cn/")
                        } label: {
                            card(entry)
                        }
                        .buttonStyle(.plain)
                    } else if entry == .settings {
                        Button { showsSettings = true } label: { card(entry) }
                            .buttonStyle(.plain)
                    } else if entry == .jwgl {
                        Button {
                            webLink = WebLink(title: "教务系统", urlString: "http://jwgl2018.xatu.edu.cn/")
                        } label: {
                            card(entry)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { pending = entry } label: { card(entry) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .background(!usesWorkspace ? Color.clear : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func subtitle(for entry: Entry) -> String {
        guard entry == .bill, let balance = app.electricityBalance else { return entry.subtitle }
        return "剩 \(balance) 度"
    }

    @ViewBuilder
    private func card(_ entry: Entry) -> some View {
        if usesWorkspace {
            serviceRow(entry)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: entry.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(entry.tint)
                    .frame(width: 32, height: 32)
                    .background(entry.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                let subtitle = subtitle(for: entry)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func serviceRow(_ entry: Entry) -> some View {
        HStack(spacing: 14) {
            Image(systemName: entry.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(entry.tint)
                .frame(width: 38, height: 38)
                .background(entry.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                let subtitle = subtitle(for: entry)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.4))
                .frame(height: 0.5)
                .padding(.leading, 68)
        }
    }
}

#Preview {
    InfoView()
        .environmentObject(AppState())
}
