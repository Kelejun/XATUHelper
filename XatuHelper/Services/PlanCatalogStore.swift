import Foundation

/// 教学计划课程信息存本地一份，免得每进一次页面都去拉。
enum PlanCatalogStore {
    private static let fileName = "plan-catalog.json"

    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> PlanCatalog {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return PlanCatalog() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PlanCatalog.self, from: data)) ?? PlanCatalog()
    }

    static func save(_ catalog: PlanCatalog) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(catalog) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func clear() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }
}
