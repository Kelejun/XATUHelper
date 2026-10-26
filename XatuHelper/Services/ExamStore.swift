import Foundation

/// 考试安排缓存，首页卡片只读这份，不在启动时联网。
struct ExamStore {
    struct Payload: Codable {
        var exams: [ExamRecord]
        var fetchedAt: Date
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("exams.json")
    }

    func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            return payload
        }
        // 老版本只存了数组，按文件修改时间补一个时间戳
        guard let exams = try? JSONDecoder().decode([ExamRecord].self, from: data) else { return nil }
        let date = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? Date()
        return Payload(exams: exams, fetchedAt: date)
    }

    func save(_ exams: [ExamRecord], at date: Date = Date()) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Payload(exams: exams, fetchedAt: date)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
