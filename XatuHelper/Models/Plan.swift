import Foundation

/// 培养计划里的一条要求（一个模块/一类课程），用来算毕业学分进度
struct PlanRow: Codable, Identifiable, Hashable {
    var id: String
    var module: String      // 模块名，比如「通识必修」
    var required: Double    // 要求学分
    var earned: Double      // 已修学分

    var progress: Double {
        guard required > 0 else { return 0 }
        return min(earned / required, 1)
    }
}

/// 培养计划页解析出来的东西
struct PlanSnapshot: Codable, Hashable {
    var rows: [PlanRow] = []
    var totalRequired: Double = 0
    var totalEarned: Double = 0

    var totalProgress: Double {
        guard totalRequired > 0 else { return 0 }
        return min(totalEarned / totalRequired, 1)
    }

    static let empty = PlanSnapshot()
}
