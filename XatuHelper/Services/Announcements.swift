import Foundation
import Combine

struct Announcement: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let platforms: [String]
    let publishedAt: Int64
    let expiresAt: Int64?
    var imageURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, body, platforms
        case publishedAt = "published_at", expiresAt = "expires_at", imageURL = "image_url"
    }
}

struct AnnouncementFeed: Decodable {
    let announcements: [Announcement]
    let serverTime: Int64

    enum CodingKeys: String, CodingKey {
        case announcements
        case serverTime = "server_time"
    }

    func validated() throws -> AnnouncementFeed {
        guard serverTime > 0, announcements.count <= 100,
              Set(announcements.map(\.id)).count == announcements.count,
              announcements.allSatisfy({
                  UUID(uuidString: $0.id) != nil && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.title.unicodeScalars.count <= 120 && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.body.unicodeScalars.count <= 10000 && $0.platforms.contains("ios") &&
                  $0.publishedAt > 0 && $0.publishedAt <= serverTime &&
                  ($0.expiresAt == nil || $0.expiresAt! > serverTime)
              }) else { throw URLError(.cannotParseResponse) }
        return self
    }
}

struct AnnouncementClient {
    let session: URLSession

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        self.session = session ?? URLSession(configuration: config)
    }

    static func endpoint(_ base: String, allowHTTP: Bool) -> URL? {
        guard var parts = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.scheme == "https" ||
                (parts.scheme == "http" && (allowHTTP || host == "47.109.84.89")) else { return nil }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = (parts.path.isEmpty ? "" : "/" + parts.path) + "/v1/announcements"
        parts.queryItems = [URLQueryItem(name: "platform", value: "ios")]
        return parts.url
    }

    func fetch(_ endpoint: URL) async throws -> AnnouncementFeed {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType == "application/json", data.count <= 4 * 1024 * 1024 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(AnnouncementFeed.self, from: data).validated()
    }
}

@MainActor
final class AnnouncementCenter: ObservableObject {
    @Published private(set) var pending: [Announcement] = []
    @Published private(set) var history: [ReceivedAnnouncement]
    @Published var presentationBlockers: Set<UUID> = []
    @Published private(set) var imageRevision = 0
    @Published private(set) var isCachingImages = false
    private let imageStore: AnnouncementImageStore
    private var imageGeneration = UUID()
    private let localStore: AnnouncementLocalStore
    private var active: [Announcement] = []

    var latest: ReceivedAnnouncement? {
        history.max { $0.announcement.publishedAt < $1.announcement.publishedAt }
    }
    private let client: AnnouncementClient
    private let defaults: UserDefaults
    private let endpoint: URL?
    private let storageKey: String
    private var loading = false
    private var refreshRequested = false
    private var expiryTask: Task<Void, Never>?

    init(baseURL: String = Bundle.main.object(forInfoDictionaryKey: "AnnouncementsBaseURL") as? String ?? "",
         defaults: UserDefaults = .standard, client: AnnouncementClient = AnnouncementClient(),
         imageStore: AnnouncementImageStore = .shared) {
        #if DEBUG
        let allowHTTP = true
        #else
        let allowHTTP = false
        #endif
        endpoint = AnnouncementClient.endpoint(baseURL, allowHTTP: allowHTTP)
        storageKey = "announcements.seen." + (endpoint?.absoluteString ?? "disabled")
        self.defaults = defaults
        self.client = client
        self.imageStore = imageStore
        localStore = AnnouncementLocalStore(defaults: defaults)
        history = localStore.records
        Task { [weak self] in await self?.synchronizeImages() }
    }

    func refresh() async {
        guard let endpoint else { return }
        if loading {
            refreshRequested = true
            return
        }
        loading = true
        repeat {
            refreshRequested = false
            await refreshFeed(endpoint)
        } while refreshRequested && !Task.isCancelled
        loading = false
        if !Task.isCancelled { await synchronizeImages() }
    }

    private func refreshFeed(_ endpoint: URL) async {
        do {
            let feed = try await client.fetch(endpoint)
            guard !Task.isCancelled else { return }
            localStore.receive(feed.announcements, source: endpoint.absoluteString, at: Date())
            history = localStore.records
            active = feed.announcements
            let seen = Set(defaults.stringArray(forKey: storageKey) ?? [])
            let retained = Set(history.filter { $0.source == endpoint.absoluteString }.map { $0.announcement.id })
            pending = active.filter { !seen.contains($0.id) && retained.contains($0.id) }
            expiryTask?.cancel()
            let received = ProcessInfo.processInfo.systemUptime
            expiryTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let next = self.pending.compactMap(\.expiresAt).min() else { return }
                    let elapsed = Int64((ProcessInfo.processInfo.systemUptime - received) * 1000)
                    let remaining = max(0, next - feed.serverTime - elapsed)
                    // Wake at least daily to keep the sleep interval bounded.
                    try? await Task.sleep(nanoseconds: UInt64(min(remaining, 86_400_000)) * 1_000_000)
                    guard !Task.isCancelled else { return }
                    let now = feed.serverTime + Int64((ProcessInfo.processInfo.systemUptime - received) * 1000)
                    self.pending.removeAll { ($0.expiresAt ?? Int64.max) <= now }
                }
            }
        } catch {
            // A failed foreground refresh must not keep showing a withdrawn cached notice.
            pending = []
            expiryTask?.cancel()
        }
    }

    func acknowledge(_ record: ReceivedAnnouncement) {
        let key = "announcements.seen." + record.source
        var seen = Set(defaults.stringArray(forKey: key) ?? [])
        seen.insert(record.announcement.id)
        defaults.set(Array(seen), forKey: key)
        if record.source == endpoint?.absoluteString { pending.removeAll { $0.id == record.announcement.id } }
    }

    func cachedImageURL(for url: URL) async -> URL? {
        await imageStore.cachedURL(for: url)
    }

    private func synchronizeImages() async {
        let current = UUID()
        imageGeneration = current
        let urls = Set(history.compactMap { $0.announcement.imageURL })
        isCachingImages = !urls.isEmpty
        await imageStore.synchronize(urls)
        guard imageGeneration == current else { return }
        imageRevision += 1
        isCachingImages = false
    }

    func deleteHistory(_ record: ReceivedAnnouncement) async {
        let key = "announcements.seen." + record.source
        var seen = Set(defaults.stringArray(forKey: key) ?? [])
        seen.remove(record.announcement.id)
        if seen.isEmpty { defaults.removeObject(forKey: key) }
        else { defaults.set(Array(seen), forKey: key) }
        if record.source == endpoint?.absoluteString { pending.removeAll { $0.id == record.announcement.id } }
        localStore.delete(record)
        history = localStore.records
        await synchronizeImages()
    }

    func clearHistory() async {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("announcements.seen.") {
            defaults.removeObject(forKey: key)
        }
        expiryTask?.cancel()
        localStore.clear()
        history = []
        pending = []
        await synchronizeImages()
    }

    func dismiss(_ id: String) {
        var seen = Set(defaults.stringArray(forKey: storageKey) ?? [])
        seen.insert(id)
        defaults.set(Array(seen), forKey: storageKey)
        pending.removeAll { $0.id == id }
    }
}
