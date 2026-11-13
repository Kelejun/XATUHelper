import Foundation

/// Atomic storage for replaceable caches; callers keep ownership and migration rules.
struct LocalJSONFile<Value: Codable> {
    let name: String
    var usesISO8601 = false

    var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        if usesISO8601 { decoder.dateDecodingStrategy = .iso8601 }
        return try? decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        let encoder = JSONEncoder()
        if usesISO8601 { encoder.dateEncodingStrategy = .iso8601 }
        guard let data = try? encoder.encode(value) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch { return }
    }

    func clear() { try? FileManager.default.removeItem(at: url) }
}
