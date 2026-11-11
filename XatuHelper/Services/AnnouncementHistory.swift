import Foundation

struct ReceivedAnnouncement: Codable, Identifiable, Equatable {
    let source: String
    let announcement: Announcement
    let receivedAt: Date

    var id: String { source + "#" + announcement.id }
}

final class AnnouncementLocalStore {
    private let defaults: UserDefaults
    private let key = "announcements.history.v1"
    private let receiptsKey = "announcements.receipts.v1"
    private(set) var records: [ReceivedAnnouncement]
    private var receipts: Set<String>

    init(defaults: UserDefaults) {
        self.defaults = defaults
        records = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([ReceivedAnnouncement].self, from: $0) } ?? []
        let savedReceipts = Set(defaults.stringArray(forKey: receiptsKey) ?? [])
        receipts = Set(records.map(\.id))
        for orphan in savedReceipts.subtracting(receipts) {
            guard let separator = orphan.lastIndex(of: "#") else { continue }
            let key = "announcements.seen." + orphan[..<separator]
            let identifier = String(orphan[orphan.index(after: separator)...])
            var seen = Set(defaults.stringArray(forKey: key) ?? [])
            seen.remove(identifier)
            if seen.isEmpty { defaults.removeObject(forKey: key) }
            else { defaults.set(Array(seen), forKey: key) }
        }
        if savedReceipts != receipts { persist() }
    }

    func receive(_ announcements: [Announcement], source: String, at date: Date) {
        for announcement in announcements {
            let record = ReceivedAnnouncement(source: source, announcement: announcement, receivedAt: date)
            if receipts.insert(record.id).inserted { records.append(record) }
        }
        records.sort {
            if $0.receivedAt != $1.receivedAt { return $0.receivedAt > $1.receivedAt }
            if $0.announcement.publishedAt != $1.announcement.publishedAt {
                return $0.announcement.publishedAt > $1.announcement.publishedAt
            }
            return $0.id < $1.id
        }
        persist()
    }

    func delete(_ record: ReceivedAnnouncement) {
        records.removeAll { $0.id == record.id }
        receipts.remove(record.id)
        persist()
    }

    func clear() {
        records = []
        defaults.removeObject(forKey: key)
        receipts.removeAll()
        defaults.removeObject(forKey: receiptsKey)
    }

    private func persist() {
        if records.isEmpty { defaults.removeObject(forKey: key) }
        else if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
        if receipts.isEmpty { defaults.removeObject(forKey: receiptsKey) }
        else { defaults.set(Array(receipts), forKey: receiptsKey) }
    }
}
