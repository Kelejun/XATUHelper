import Foundation
import CryptoKit
import ImageIO

actor AnnouncementImageStore {
    static let shared = AnnouncementImageStore()
    private let directory: URL
    private let session: URLSession
    private var generation = UUID()

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AnnouncementImages", isDirectory: true), session: URLSession? = nil) {
        self.directory = directory
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCache = nil
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: config)
        }
    }

    private func file(for url: URL) -> URL {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".image")
    }

    func cachedURL(for url: URL) -> URL? {
        let path = file(for: url)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    func synchronize(_ urls: Set<URL>) async {
        let current = UUID()
        generation = current
        let wanted = Set(urls.map { file(for: $0).lastPathComponent })
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where !wanted.contains(file.lastPathComponent) {
                try FileManager.default.removeItem(at: file)
            }
        } catch { return }
        for url in urls.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            guard generation == current, !Task.isCancelled else { return }
            guard cachedURL(for: url) == nil,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.user == nil, url.password == nil else { continue }
            do {
                let (temporary, response) = try await session.download(for: URLRequest(url: url))
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard generation == current, !Task.isCancelled,
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.mimeType?.hasPrefix("image/") == true,
                      let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size > 0, size <= 10 * 1024 * 1024,
                      let source = CGImageSourceCreateWithURL(temporary as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 16000, height <= 16000,
                      width * height <= 40_000_000 else { continue }
                try FileManager.default.moveItem(at: temporary, to: file(for: url))
            } catch { continue }
        }
    }
}
