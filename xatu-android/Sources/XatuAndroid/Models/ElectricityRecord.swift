import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
