import SwiftUI

/// 每天一条的余额存档，新的在上面。
struct ElectricityHistoryView: View {
    @Environment(AppState.self) var app

    private var grouped: [(month: String, records: [ElectricityRecord])] {
        let sorted = app.electricityHistory.sorted { $0.day > $1.day }
        var result: [(month: String, records: [ElectricityRecord])] = []

        for record in sorted {
            let month = String(record.day.prefix(7))
            if let last = result.last, last.month == month {
                result[result.count - 1].records.append(record)
            } else {
                result.append((month: month, records: [record]))
            }
        }
        return result
    }

    var body: some View {
        List {
            if app.electricityHistory.isEmpty {
                Section {
                    ContentUnavailableView(
                        "还没有记录",
                        systemImage: "bolt.slash",
                        description: Text("选好宿舍后每天查一次余额，这里就会攒起来")
                    )
                }
            } else {
                ForEach(grouped, id: \.month) { group in
                    Section(group.month) {
                        ForEach(group.records) { record in
                            row(record)
                        }
                    }
                }
            }
        }
        .md3List()
        .navigationTitle("历史余额")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ record: ElectricityRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(record.shortLabel)
                

            Spacer(minLength: 8)

            if let usage = app.electricityUsage(on: record) {
                Text(usage >= 0
                     ? String(format: "用 ¥%.2f", usage)
                     : String(format: "充 ¥%.2f", -usage))
                    .font(MD3Type.bodyMedium)
                    .foregroundStyle(.secondary)
            }

            Text("¥\(record.amountText)")
                
                .foregroundStyle(record.balance < 10 ? .orange : .primary)
        }
    }
}

#if !os(Android)
#Preview {
    NavigationStack {
        ElectricityHistoryView()
            .environment(AppState())
    }
}
#endif

