import Foundation

/// 课表缓存，纯本地 JSON
struct TimetableStore {
    var fileName = "timetable.json"
    private var file: LocalJSONFile<TimetableSnapshot> { .init(name: fileName, usesISO8601: true) }

    func load() -> TimetableSnapshot? { file.load() }
    func save(_ snapshot: TimetableSnapshot) { file.save(snapshot) }
    func clear() { file.clear() }
}

/// 用户修改独立保存，教务缓存刷新和退出登录都不会覆盖它。
struct TimetableEditStore {
    typealias Accounts = [String: [String: [TimetableEdit]]]

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("timetable-edits.json")
    }

    func load() throws -> Accounts {
        do {
            return try JSONDecoder().decode(Accounts.self, from: Data(contentsOf: fileURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        }
    }

    func save(_ accounts: Accounts) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(accounts).write(to: fileURL, options: .atomic)
    }
}
