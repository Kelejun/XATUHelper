import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 一节课的一次出现：某门课在某个星期几的第几节，占用某些教学周。
struct CourseOccurrence: Identifiable, Codable, Hashable {
    var id: String
    /// 课程号，如 060020.03
    var courseKey: String
    /// 课程名，已去掉括号里的课程号
    var name: String
    var teacher: String
    var room: String
    /// 1...7，周一 = 1
    var day: Int
    /// 1...12
    var period: Int
    /// 占用的教学周，升序
    var weeks: [Int]
    /// 线上教室（平台修读）
    var isRemote: Bool
    /// 实践环节选课之类的占位课
    var isPlaceholder: Bool

    var weekdayLabel: String {
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        return labels[max(0, min(6, day - 1))]
    }

    var weeksText: String {
        guard !weeks.isEmpty else { return "" }
        let sorted = weeks.sorted()
        var parts: [String] = []
        var start = sorted[0]
        var previous = sorted[0]

        for value in sorted.dropFirst() {
            if value == previous + 1 {
                previous = value
                continue
            }
            parts.append(start == previous ? "\(start)" : "\(start)-\(previous)")
            start = value
            previous = value
        }
        parts.append(start == previous ? "\(start)" : "\(start)-\(previous)")
        return "第" + parts.joined(separator: ",") + "周"
    }

    var shortRoom: String {
        var s = room
        if let r = s.range(of: #"\([^()]*\)$"#, options: .regularExpression) {
            s = String(s[s.startIndex..<r.lowerBound])
        }
        return s
    }

    /// 第几节到第几节，单节就直接显示节次
    var periodText: String {
        "第 \(period) 节"
    }
}

/// 连排合并后的一块课：周一下午 1-2 节这种。
struct CourseBlock: Identifiable, Hashable {
    var id: String
    var courseKey: String
    var name: String
    var teacher: String
    var room: String
    var day: Int
    var startPeriod: Int
    var endPeriod: Int
    var weeks: [Int]
    var isRemote: Bool
    var isPlaceholder: Bool

    var span: Int { max(1, endPeriod - startPeriod + 1) }

    var weekdayLabel: String {
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        return labels[max(0, min(6, day - 1))]
    }

    var periodText: String {
        startPeriod == endPeriod ? "第 \(startPeriod) 节" : "第 \(startPeriod)-\(endPeriod) 节"
    }

    var weeksText: String {
        guard !weeks.isEmpty else { return "" }
        let sorted = weeks.sorted()
        var parts: [String] = []
        var start = sorted[0]
        var previous = sorted[0]
        for value in sorted.dropFirst() {
            if value == previous + 1 { previous = value; continue }
            parts.append(start == previous ? "\(start)" : "\(start)-\(previous)")
            start = value
            previous = value
        }
        parts.append(start == previous ? "\(start)" : "\(start)-\(previous)")
        return "第" + parts.joined(separator: ",") + "周"
    }

    var shortRoom: String {
        var s = room
        if let r = s.range(of: #"\([^()]*\)$"#, options: .regularExpression) {
            s = String(s[s.startIndex..<r.lowerBound])
        }
        return s
    }
}

extension Array where Element == CourseOccurrence {
    /// 把同一天、同一门课、同一间教室的连续节次合并成一块。
    func courseBlocks() -> [CourseBlock] {
        var groups: [String: [CourseOccurrence]] = [:]
        for item in self {
            let key = "\(item.day)|\(item.courseKey)|\(item.room)|\(item.teacher)"
            groups[key, default: []].append(item)
        }

        var result: [CourseBlock] = []
        for items in groups.values {
            let ordered = items.sorted { $0.period < $1.period }

            // 先按连续节次切成若干段
            var runs: [[CourseOccurrence]] = []
            for item in ordered {
                if var tail = runs.last, let previous = tail.last, item.period == previous.period + 1 {
                    tail.append(item)
                    runs[runs.count - 1] = tail
                } else {
                    runs.append([item])
                }
            }

            for run in runs {
                guard let first = run.first, let last = run.last else { continue }
                var weekSet: Set<Int> = []
                for occurrence in run {
                    weekSet.formUnion(occurrence.weeks)
                }
                result.append(
                    CourseBlock(
                        id: first.id,
                        courseKey: first.courseKey,
                        name: first.name,
                        teacher: first.teacher,
                        room: first.room,
                        day: first.day,
                        startPeriod: first.period,
                        endPeriod: last.period,
                        weeks: weekSet.sorted(),
                        isRemote: first.isRemote,
                        isPlaceholder: first.isPlaceholder
                    )
                )
            }
        }

        return result.sorted {
            $0.day == $1.day ? $0.startPeriod < $1.startPeriod : $0.day < $1.day
        }
    }
}

/// 学年学期
struct Semester: Codable, Hashable, Identifiable {
    var id: String
    /// 完整显示名，如 "2026-2027学年1学期"
    var name: String
    /// 学年，如 "2026-2027"，菜单里用来分组
    var schoolYear: String? = nil
    /// 学期名，如 "1学期"
    var termName: String? = nil
    /// 开学日期，形如 "2026-09-07"，能拿到就能精确算出第几周
    var startDate: String? = nil

    /// 太长的学期名截一下，给导航栏用的
    var shortName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 14 ? String(trimmed.prefix(14)) + "…" : trimmed
    }
}

struct TimetableSnapshot: Codable {
    var occurrences: [CourseOccurrence]
    var studentID: String
    var semesterID: String
    var fetchedAt: Date
    var weekOneMonday: Date
    var unitCount: Int

    // 下面几项是后加的，老缓存里没有这些键，解码成 nil 就行
    var semesters: [Semester]?
    var selectedSemesterID: String?
    var currentSemesterID: String?
    var kind: String?
}

/// 登录期信息，用于刷新时复用
struct LoginProfile: Codable {
    var studentID: String
}

extension String {
    /// 返回所有匹配的捕获组（第 1 组起）
    func regexGroups(_ pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = self as NSString
        let range = NSRange(location: 0, length: ns.length)
        return re.matches(in: self, options: [], range: range).map { m in
            (1..<m.numberOfRanges).map { idx in
                if let r = Range(m.range(at: idx), in: self) { return String(self[r]) }
                return ""
            }
        }
    }

    func firstMatch(_ pattern: String) -> String? {
        if let group = regexGroups(pattern).first?.first, !group.isEmpty {
            return group
        }
        // 没写括号的正则也认，返回整段匹配
        return range(of: pattern, options: .regularExpression).map { String(self[$0]) }
    }

    var strippingTags: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
