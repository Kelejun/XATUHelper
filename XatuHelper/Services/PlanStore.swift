import Foundation

/// 学业完成情况（培养计划）缓存，过期才重新读。
struct PlanStore {
    struct Payload: Codable {
        var plan: PlanSnapshot
        var fetchedAt: Date
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("plan.json")
    }

    func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    func save(_ plan: PlanSnapshot, at date: Date = Date()) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Payload(plan: plan, fetchedAt: date)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
