import Foundation

private final class FeedProtocol: URLProtocol {
    static var data = Data()
    static var fails = false
    static var delay = 0.0
    static var requests = 0
    static var started: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let data = Self.data
        let fails = Self.fails
        Self.started?()
        Self.started = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [self] in
            if fails {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private final class ImageProtocol: URLProtocol {
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
    static var fails = false
    static var delay = 0.0
    static var corrupt = false
    static var started: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.started?()
        Self.started = nil
        if Self.fails {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let data = Self.corrupt ? Data("not an image".utf8) : Self.png
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "image/png"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main
struct AnnouncementTests {
    @MainActor static func main() async throws {
        let suite = "announcement-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let time = Int64(Date().timeIntervalSince1970 * 1000)
        let item = Announcement(id: UUID().uuidString, title: "公告", body: "# 标题\n\n**正文**", platforms: ["ios"], publishedAt: time - 1000, expiresAt: nil,
                                imageURL: URL(string: "https://example.com/header.png"))
        let store = AnnouncementLocalStore(defaults: defaults)
        let received = Date(timeIntervalSince1970: 1000)
        store.receive([item], source: "A", at: received)
        store.receive([item], source: "A", at: received.addingTimeInterval(60))
        precondition(store.records.count == 1 && store.records[0].receivedAt == received)
        precondition(AnnouncementLocalStore(defaults: defaults).records[0].announcement == item)
        store.receive([item], source: "B", at: received.addingTimeInterval(60))
        precondition(store.records.count == 2 && store.records[0].source == "B")
        store.clear()
        store.receive([item], source: "A", at: Date())
        precondition(store.records.count == 1, "Cleared receipts must allow receiving the same ID again")
        precondition(AnnouncementLocalStore(defaults: defaults).records.count == 1)
        store.clear()

        let orphanID = "https://legacy.example/v1/announcements?platform=ios#" + item.id
        let orphanSeenKey = "announcements.seen.https://legacy.example/v1/announcements?platform=ios"
        defaults.set([orphanID], forKey: "announcements.receipts.v1")
        defaults.set([item.id, "unrelated-read-id"], forKey: orphanSeenKey)
        let migrated = AnnouncementLocalStore(defaults: defaults)
        precondition(defaults.stringArray(forKey: orphanSeenKey) == ["unrelated-read-id"])
        migrated.receive([item], source: "https://legacy.example/v1/announcements?platform=ios", at: Date())
        precondition(migrated.records.count == 1, "Old deleted receipt IDs must not suppress re-receiving")
        migrated.clear()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedProtocol.self]
        let client = AnnouncementClient(session: URLSession(configuration: config))
        func feed(_ items: [Announcement]) throws {
            let payload: [String: Any] = ["announcements": try JSONSerialization.jsonObject(with: JSONEncoder().encode(items)), "server_time": time]
            FeedProtocol.data = try JSONSerialization.data(withJSONObject: payload)
        }
        try feed([item])
        let imageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: imageDirectory) }
        let imageConfig = URLSessionConfiguration.ephemeral
        imageConfig.protocolClasses = [ImageProtocol.self]
        let imageSession = URLSession(configuration: imageConfig)
        let imageStore = AnnouncementImageStore(directory: imageDirectory, session: imageSession)
        let center = AnnouncementCenter(baseURL: "http://47.109.84.89", defaults: defaults, client: client, imageStore: imageStore)
        await center.refresh()
        precondition(center.pending.count == 1 && center.history.count == 1)
        let savedImage = await imageStore.cachedURL(for: item.imageURL!)
        precondition(savedImage != nil)
        let savedData = try Data(contentsOf: savedImage!)
        precondition(savedData == ImageProtocol.png)
        let offlineStore = AnnouncementImageStore(directory: imageDirectory, session: imageSession)
        ImageProtocol.fails = true
        await offlineStore.synchronize([item.imageURL!])
        let offlineImage = await offlineStore.cachedURL(for: item.imageURL!)
        precondition(offlineImage != nil, "A new cache instance must retain offline images")
        ImageProtocol.fails = false
        let firstReceipt = center.history[0].receivedAt
        await center.refresh()
        precondition(center.history.count == 1 && center.history[0].receivedAt == firstReceipt)
        center.dismiss(item.id)
        await center.refresh()
        precondition(center.pending.isEmpty)
        try feed([])
        await center.refresh()
        precondition(center.history.count == 1)
        try feed([item])
        await center.refresh()
        precondition(center.pending.isEmpty, "Withdrawn/reappearing IDs must stay read")
        FeedProtocol.fails = true
        await center.refresh()
        precondition(center.history.count == 1 && center.pending.isEmpty)
        FeedProtocol.fails = false
        await center.clearHistory()
        let clearedImage = await imageStore.cachedURL(for: item.imageURL!)
        precondition(clearedImage == nil)
        precondition(center.history.isEmpty && center.pending.isEmpty)
        precondition(defaults.array(forKey: "announcements.receipts.v1") == nil)
        precondition(!defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("announcements.seen.") })
        await center.refresh()
        precondition(center.history.count == 1 && center.pending.map(\.id) == [item.id])
        let newItem = Announcement(id: UUID().uuidString, title: "新公告", body: "正文", platforms: ["ios"], publishedAt: time, expiresAt: nil)
        try feed([newItem, item])
        await center.refresh()
        precondition(center.history.count == 2 && Set(center.pending.map(\.id)) == [newItem.id, item.id])
        let restored = AnnouncementCenter(baseURL: "http://47.109.84.89", defaults: defaults, client: client, imageStore: imageStore)
        precondition(restored.history.count == 2)

        let sharedA = Announcement(id: UUID().uuidString, title: "共享封面 A", body: "正文", platforms: ["ios"], publishedAt: time, expiresAt: nil, imageURL: item.imageURL)
        let sharedB = Announcement(id: UUID().uuidString, title: "共享封面 B", body: "正文", platforms: ["ios"], publishedAt: time, expiresAt: nil, imageURL: item.imageURL)
        try feed([sharedA, sharedB])
        await center.refresh()
        await center.deleteHistory(center.history.first { $0.announcement.id == sharedA.id }!)
        let sharedImage = await imageStore.cachedURL(for: item.imageURL!)
        precondition(sharedImage != nil, "Deleting one record must retain a shared cover")
        precondition(!center.history.contains { $0.announcement.id == sharedA.id })
        precondition(!center.pending.contains { $0.id == sharedA.id })
        let reloadedStore = AnnouncementLocalStore(defaults: defaults)
        precondition(!reloadedStore.records.contains { $0.announcement.id == sharedA.id })
        await center.refresh()
        precondition(center.history.contains { $0.announcement.id == sharedA.id })
        precondition(center.pending.contains { $0.id == sharedA.id })
        let receiptA = center.history.first { $0.announcement.id == sharedA.id }!
        center.acknowledge(receiptA)
        let sourceSeen = "announcements.seen." + receiptA.source
        precondition(defaults.stringArray(forKey: sourceSeen)?.contains(sharedA.id) == true)
        await center.deleteHistory(receiptA)
        precondition(defaults.stringArray(forKey: sourceSeen)?.contains(sharedA.id) != true)
        await center.deleteHistory(center.history.first { $0.announcement.id == sharedB.id }!)
        precondition(center.history.count == 2, "Deleting announcements must preserve unrelated records")
        // Remove the original image-bearing record too, so no remaining record references the cover.
        await center.deleteHistory(center.history.first { $0.announcement.id == item.id }!)
        let deletedImage = await imageStore.cachedURL(for: item.imageURL!)
        precondition(deletedImage == nil)
        let afterDelete = AnnouncementCenter(baseURL: "http://47.109.84.89", defaults: defaults, client: client, imageStore: imageStore)
        await afterDelete.refresh()
        precondition(afterDelete.history.contains { $0.announcement.id == sharedA.id })
        precondition(afterDelete.pending.contains { $0.id == sharedA.id }, "Re-receiving after deletion must survive a restart")

        let lateURL = URL(string: "https://example.com/late.png")!
        ImageProtocol.delay = 0.2
        var download: Task<Void, Never>!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ImageProtocol.started = { continuation.resume() }
            download = Task { await imageStore.synchronize([lateURL]) }
        }
        // Invalidate the in-flight response before it can recreate a cleared cover.
        await imageStore.synchronize([])
        await download.value
        let lateImage = await imageStore.cachedURL(for: lateURL)
        precondition(lateImage == nil)
        ImageProtocol.delay = 0
        ImageProtocol.corrupt = true
        await imageStore.synchronize([lateURL])
        let invalidImage = await imageStore.cachedURL(for: lateURL)
        precondition(invalidImage == nil)
        ImageProtocol.corrupt = false

        let queueSuite = suite + "-queue"
        let queueDefaults = UserDefaults(suiteName: queueSuite)!
        defer { queueDefaults.removePersistentDomain(forName: queueSuite) }
        let queueDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: queueDirectory) }
        let queueImages = AnnouncementImageStore(directory: queueDirectory, session: imageSession)
        let queueCenter = AnnouncementCenter(baseURL: "http://queue.local", defaults: queueDefaults, client: client, imageStore: queueImages)
        try feed([])
        FeedProtocol.delay = 0.1
        let initialRequests = FeedProtocol.requests
        var firstRefresh: Task<Void, Never>!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            FeedProtocol.started = { continuation.resume() }
            firstRefresh = Task { await queueCenter.refresh() }
        }
        try feed([newItem])
        await queueCenter.refresh()
        await firstRefresh.value
        precondition(FeedProtocol.requests == initialRequests + 2, "A foreground trigger during a fetch must be queued")
        precondition(queueCenter.pending.map(\.id) == [newItem.id])
        FeedProtocol.delay = 0

        let slowCover = Announcement(id: UUID().uuidString, title: "慢速封面", body: "正文", platforms: ["ios"], publishedAt: time, expiresAt: nil, imageURL: URL(string: "https://example.com/slow-foreground.png"))
        try feed([slowCover])
        ImageProtocol.delay = 0.2
        var coverRefresh: Task<Void, Never>!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ImageProtocol.started = { continuation.resume() }
            coverRefresh = Task { await queueCenter.refresh() }
        }
        let beforeForeground = FeedProtocol.requests
        try feed([newItem])
        await queueCenter.refresh()
        precondition(FeedProtocol.requests == beforeForeground + 1, "Cover downloads must not block a foreground feed refresh")
        await coverRefresh.value
        ImageProtocol.delay = 0

        let blocks = AnnouncementMarkdownBlock.parse("# 标题\n\n**粗体** 与 [链接](https://example.com)\n\n- 列表\n1. 顺序\n> 引用\n\n```swift\nlet x = 1\n```\n---")
        precondition(blocks == [.heading(1, "标题"), .paragraph("**粗体** 与 [链接](https://example.com)"), .listItem("•", "列表"), .listItem("1.", "顺序"), .quote("引用"), .code("let x = 1"), .divider])
        precondition(AnnouncementMarkdownBlock.parse("```\n未闭合") == [.code("未闭合")])
        print("Announcement persistence, offline covers, shared-image deletion, delayed-download cleanup, swipe deletion semantics and Markdown tests passed")
    }
}
