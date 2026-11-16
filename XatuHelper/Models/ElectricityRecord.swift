import Foundation

/// 每天一条的电费余额记录。同一天刷新多次也只留一条（后到的覆盖先到的）。
struct ElectricityRecord: Codable, Identifiable, Hashable {
    /// yyyy-MM-dd
    var day: String
    var balance: Double

    var id: String { day }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayString(for date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    var date: Date { Self.formatter.date(from: day) ?? .distantPast }

    /// 列表里显示的「10-25」
    var shortLabel: String {
        day.count >= 10 ? String(day.suffix(5)) : day
    }

    var amountText: String { String(format: "%.2f", balance) }
}

struct ElectricityUsagePoint: Identifiable {
    let date: Date
    let usage: Double?
    let hasRecharge: Bool
    var id: Date { date }

    static func make(history: [ElectricityRecord], from start: Date, through end: Date,
                     calendar: Calendar = .current) -> [Self] {
        let records = history.sorted { $0.day < $1.day }
        var samples: [Self] = []
        for (previous, current) in zip(records, records.dropFirst()) {
            let days = calendar.dateComponents([.day], from: previous.date, to: current.date).day ?? 0
            guard days > 0, current.date >= start, previous.date < end, current.date <= end else { continue }
            let difference = previous.balance - current.balance
            let firstDay = max(calendar.dateComponents([.day], from: previous.date, to: start).day ?? 1, 1)
            guard firstDay <= days else { continue }
            for offset in firstDay...days {
                guard let date = calendar.date(byAdding: .day, value: offset, to: previous.date) else { continue }
                samples.append(Self(date: date, usage: difference >= 0 ? difference / Double(days) : nil,
                                    hasRecharge: difference < 0 && offset == days))
            }
        }
        let measured = samples.compactMap(\.usage)
        let average = measured.isEmpty ? nil : measured.reduce(0, +) / Double(measured.count)
        return samples.map {
            Self(date: $0.date, usage: $0.usage ?? average, hasRecharge: $0.hasRecharge)
        }
    }
}
