import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// App 和小组件共用的快照，两边都编进 target
struct WidgetSnapshot: Codable {
    struct Course: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var room: String
        var startMinutes: Int
        var endMinutes: Int
        var colorIndex: Int? = nil
    }

    struct Break: Codable, Hashable {
        var title: String
        var date: Date
        var days: Int
    }

    struct Exam: Codable, Hashable {
        var title: String
        var date: Date?
        var days: Int?
    }

    var generatedAt: Date
    var week: Int
    var weekday: Int
    var courses: [Course]
    var tomorrowCourses: [Course]? = nil
    var tomorrowWeekday: Int? = nil
    var balance: Double?
    var balanceUpdatedAt: Date?
    var roomName: String?
    var upcomingBreak: Break?
    var nextExam: Exam?
    var loggedIn: Bool

    static let empty = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        week: 0,
        weekday: 1,
        courses: [],
        balance: nil,
        balanceUpdatedAt: nil,
        roomName: nil,
        upcomingBreak: nil,
        nextExam: nil,
        loggedIn: false
    )

    var weekdayLabel: String { Self.weekdayLabel(weekday) }

    static func weekdayLabel(_ index: Int) -> String {
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard index >= 1, index <= names.count else { return "" }
        return names[index - 1]
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// 共享容器，读不到就说明没开 App Group
enum WidgetStore {
    static let appGroup = "group.com.cell.xatuapp"
    static let fileName = "widget-snapshot.json"

    static var fileURL: URL? {
        #if os(Android)
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
        #endif
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        #if os(Android)
        _ = AndroidPlatform.call("widget", String(decoding: data, as: UTF8.self))
        #endif
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
