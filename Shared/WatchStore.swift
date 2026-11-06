import Foundation

/// This container is local to Apple Watch. WatchConnectivity crosses the devices.
enum WatchStore {
    static let appGroup = "group.com.cell.xatuapp"
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("watch-cache-v1.plist")
    }

    static func read() -> WatchCache {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let cache = try? PropertyListDecoder().decode(WatchCache.self, from: data) else {
            return WatchCache()
        }
        return cache
    }

    static func write(_ cache: WatchCache) throws {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(cache).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
