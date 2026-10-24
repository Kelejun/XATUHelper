import SwiftUI

/// 学业信息的入口页。现在只有按钮，点开会提示还没做。
struct InfoView: View {
    @EnvironmentObject var app: AppState

    /// 这一页上的入口。后续每做好一个，就把对应的 case 从"未完成"里拿掉。
    enum Entry: String, Identifiable, CaseIterable {
        case exam
        case grade
        case plan
        case bill

        var id: String { rawValue }

        var title: String {
            switch self {
            case .exam: return "考试安排"
            case .grade: return "成绩查询"
            case .plan: return "培养计划"
            case .bill: return "电费账单"
            }
        }

        var icon: String {
            switch self {
            case .exam: return "calendar.badge.clock"
            case .grade: return "chart.bar.doc.horizontal"
            case .plan: return "list.bullet.rectangle"
            case .bill: return "bolt.horizontal"
            }
        }
    }

    @State private var pending: Entry?

    var body: some View {
        NavigationStack {
            List {
                Section("教务") {
                    ForEach([Entry.exam, .grade, .plan]) { entry in
                        row(entry)
                    }
                }

                Section("生活") {
                    row(.bill)
                }
            }
            .navigationTitle("学业")
            .alert(item: $pending) { entry in
                Alert(
                    title: Text(entry.title),
                    message: Text("这个还没做，下一版接上。"),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        Button {
            pending = entry
        } label: {
            Label(entry.title, systemImage: entry.icon)
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    InfoView()
        .environmentObject(AppState())
}
