import Foundation

/// 学业完成情况（培养计划）缓存，过期才重新读。
struct PlanStore {
    struct Payload: Codable {
        var plan: PlanSnapshot
        var fetchedAt: Date
        var account: String?
        var context: String?
    }

    private let file = LocalJSONFile<Payload>(name: "plan.json")

    func load() -> Payload? { file.load() }

    func save(_ plan: PlanSnapshot, at date: Date = Date(), account: String, context: String) {
        file.save(Payload(plan: plan, fetchedAt: date, account: account, context: context))
    }

    func clear() { file.clear() }
}
