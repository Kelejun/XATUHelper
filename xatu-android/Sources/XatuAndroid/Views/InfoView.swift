import SwiftUI

/// 校园服务的入口页，样式照着健康 App 的「浏览」：分组标题 + 两列卡片。
/// 现在卡片点了只弹提示，后面每接一个功能就把对应 case 从占位里拿掉。
struct InfoView: View {
    @Environment(AppState.self) var app

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

    @State var pending: Entry?
    @State var showsCheckin = false
    @State var showsSettings = false
    @State var webLink: WebLink?

    struct WebLink: Identifiable {
        let id = UUID()
        let title: String
        let urlString: String
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    group("教务", entries: [.exam, .grade, .plan, .calendar])
                    group("生活", entries: [.bill, .netfee, .checkin, .leave])
                    group("杂项", entries: [.ehall, .jwgl])
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Color.gray.opacity(0.08))
            .navigationTitle("校园")
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
            .alert(pending?.title ?? "提示", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("好") { pending = nil }
            } message: {
                Text("这个还没做，下一版接上。")
            }
        }
    }

    private func group(_ title: String, entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.leading, 2)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(entries) { entry in
                    if entry == .bill {
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
        }
    }

    private func subtitle(for entry: Entry) -> String {
        guard entry == .bill, let balance = app.electricityBalance else { return entry.subtitle }
        return "剩 ¥\(balance)"
    }

    private func card(_ entry: Entry) -> some View {
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
            .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}

#if !os(Android)
#Preview {
    InfoView()
        .environment(AppState())
}
#endif

