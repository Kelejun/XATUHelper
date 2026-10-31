import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 培养计划里的一门课
struct PlanCourse: Codable, Identifiable, Hashable {
    var id: String
    var code: String
    var name: String
    var required: Double
    var earned: Double
    var score: String
    var passed: Bool
}

/// 培养计划里的一个模块（一级：通识教育；二级：(一) 通识必修）
struct PlanSection: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var required: Double
    var earned: Double
    var shortfall: Double
    var courses: [PlanCourse] = []
    var children: [PlanSection] = []

    var progress: Double {
        guard required > 0 else { return earned > 0 ? 1 : 0 }
        return min(earned / required, 1)
    }

    /// 这一块总共几门课（含子模块）
    var courseCount: Int {
        courses.count + children.reduce(0) { $0 + $1.courseCount }
    }
}

/// 培养计划完成情况
struct PlanSnapshot: Codable, Hashable {
    var studentName: String = ""
    var major: String = ""
    var gpa: String = ""
    var totalRequired: Double = 0
    var totalEarned: Double = 0
    var sections: [PlanSection] = []

    var progress: Double {
        guard totalRequired > 0 else { return 0 }
        return min(totalEarned / totalRequired, 1)
    }

    var shortfall: Double { max(totalRequired - totalEarned, 0) }

    static let empty = PlanSnapshot()
}
