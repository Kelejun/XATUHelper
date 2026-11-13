import Foundation

/// 成绩缓存。进成绩页时只在过期后联网。
struct GradeStore {
    struct Payload: Codable {
        var grades: [GradeRecord]
        var fetchedAt: Date
        var account: String?
        var context: String?
    }

    private let file = LocalJSONFile<Payload>(name: "grades.json")

    func load() -> Payload? { file.load() }

    func save(_ grades: [GradeRecord], at date: Date = Date(), account: String, context: String) {
        file.save(Payload(grades: grades, fetchedAt: date, account: account, context: context))
    }

    func clear() { file.clear() }
}
