import Foundation

/// 课表缓存，纯本地 JSON
struct TimetableStore {
    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("timetable.json")
    }

    func load() -> TimetableSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TimetableSnapshot.self, from: data)
    }

    func save(_ snapshot: TimetableSnapshot) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
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
