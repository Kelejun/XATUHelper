import Foundation

/// 成绩页的两种视角
enum GradeScope: String, CaseIterable, Identifiable, Codable {
    case current = "当前学期"
    case all = "所有学期"

    var id: String { rawValue }
}

/// 成绩里的一个分项，比如「平时成绩 88」
struct GradeComponent: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var score: String
}

/// 一门课的成绩
struct GradeRecord: Identifiable, Hashable, Codable {
    var id: String
    var course: String      // 课程名称
    var code: String        // 课程序号
    var credit: String      // 学分
    var score: String       // 总成绩
    var gpa: String         // 绩点
    var term: String = ""   // 学年学期，只有「所有学期成绩」那一页才有
    var components: [GradeComponent]

    /// 右边那行大字：「成绩 / 绩点」
    var headline: String {
        let left = score.isEmpty ? "-" : score
        let right = gpa.isEmpty ? "-" : gpa
        return "\(left) / \(right)"
    }

    var subtitle: String {
        [term, code, credit.isEmpty ? "" : "\(credit) 学分"]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
