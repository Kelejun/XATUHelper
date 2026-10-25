import SwiftUI

/// 校园服务的入口页，样式照着健康 App 的「浏览」：分组标题 + 两列卡片。
/// 现在卡片点了只弹提示，后面每接一个功能就把对应 case 从占位里拿掉。
struct InfoView: View {
    @EnvironmentObject var app: AppState

    enum Entry: String, Identifiable, CaseIterable {
        case exam
        case grade
        case plan
        case bill
        case checkin

        var id: String { rawValue }

        var title: String {
            switch self {
            case .exam: return "考试安排"
            case .grade: return "成绩"
            case .plan: return "培养计划"
            case .bill: return "电费"
            case .checkin: return "签到"
            }
        }

        var subtitle: String {
            switch self {
            case .exam: return "时间、考场、座位号"
            case .grade: return "每学期的课程成绩"
            case .plan: return "毕业要修多少学分"
            case .bill: return "宿舍还剩多少电费"
            case .checkin: return "按时点一下，别断签"
            }
        }

        var icon: String {
            switch self {
            case .exam: return "calendar.badge.clock"
            case .grade: return "chart.bar.fill"
            case .plan: return "list.bullet.rectangle.fill"
            case .bill: return "bolt.fill"
            case .checkin: return "checkmark.seal.fill"
            }
        }

        var tint: Color {
            switch self {
            case .exam: return .orange
            case .grade: return .blue
            case .plan: return .green
            case .bill: return .yellow
            case .checkin: return .pink
            }
        }
    }

    @State private var pending: Entry?
    @State private var showsCheckin = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    group("教务", entries: [.exam, .grade, .plan])
                    group("生活", entries: [.bill, .checkin])
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("校园")
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
                    } else if entry == .checkin {
                        Button { showsCheckin = true } label: { card(entry) }
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

                Text(subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    InfoView()
        .environmentObject(AppState())
}
