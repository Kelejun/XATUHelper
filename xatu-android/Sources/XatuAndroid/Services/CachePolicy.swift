import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 各类数据的本地缓存有效期。
/// 故意错开一天：课程表最短，考试最长，这样几份数据不会挤在同一次打开里
/// 一起过期、一起联网，把学校的登录次数和流量都省下来。
enum CacheKind: String, CaseIterable {
    case timetable
    case plan
    case grades
    case exams

    var title: String {
        switch self {
        case .timetable: return "课程表"
        case .plan: return "学业完成情况"
        case .grades: return "成绩"
        case .exams: return "考试安排"
        }
    }

    /// 最短 168 小时（7 天），之后每类再推后一天
    var lifetime: TimeInterval {
        switch self {
        case .timetable: return 168 * 3600
        case .plan: return 192 * 3600
        case .grades: return 216 * 3600
        case .exams: return 240 * 3600
        }
    }
}
