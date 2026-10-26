import Foundation

/// 成绩缓存。进成绩页时只在过期后联网。
struct GradeStore {
    struct Payload: Codable {
        var grades: [GradeRecord]
        var fetchedAt: Date
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("grades.json")
    }

    func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    func save(_ grades: [GradeRecord], at date: Date = Date()) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Payload(grades: grades, fetchedAt: date)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
