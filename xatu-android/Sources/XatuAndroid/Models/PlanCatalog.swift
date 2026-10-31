import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 「教学计划」里每门课的固定信息：开课学期、学时、课程性质。
/// 这张表来自 /eams/myPlan.action，和计划完成情况（myPlanCompl）分开取，取到一次就存下来。
struct PlanCourseInfo: Codable, Identifiable, Hashable {
    var id: String { code.isEmpty ? name : code }
    var code: String
    var name: String
    var nature: String       // 必修 / 选修 / 限选 …
    var credit: String
    var hours: String        // 学时
    var term: String         // 第 3 学期 / 3 / 2026-2027(1)
}

struct PlanCatalog: Codable, Hashable {
    var updatedAt: Date = .distantPast
    var courses: [PlanCourseInfo] = []
}
