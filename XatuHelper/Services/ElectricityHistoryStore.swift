import Foundation

/// 电费余额的按天存档，放 UserDefaults 就够，量很小。
enum ElectricityHistoryStore {
    private static let key = "xatu.electricityHistory"
    /// 一年多是够用的，再多列表也翻不动
    private static let limit = 400

    static func load() -> [ElectricityRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([ElectricityRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.day < $1.day }
    }

    static func save(_ records: [ElectricityRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 同一天只留一条：先删掉旧的，再插新的
    static func upserting(_ record: ElectricityRecord, into records: [ElectricityRecord]) -> [ElectricityRecord] {
        var list = records.filter { $0.day != record.day }
        list.append(record)
        list.sort { $0.day < $1.day }
        if list.count > limit {
            list.removeFirst(list.count - limit)
        }
        return list
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
