import Foundation

/// 一条考试安排。树维的「我的考试」是服务端直出的表格，字段随学校配置略有差异，
/// 所以这里保留原始文本，解析时按表头找列。
struct ExamRecord: Identifiable, Hashable {
    var id: String
    var course: String      // 课程名称
    var code: String        // 课程序号
    var name: String        // 考试名称
    var time: String        // 考试时间（原始文本）
    var room: String        // 考场
    var seat: String        // 座位号
    var note: String        // 备注

    /// 用来分组的日期，形如 "2027-01-12"；认不出来就留空
    var dateKey: String { ExamRecord.dateKey(in: time) }

    static func dateKey(in text: String) -> String {
        dateFormatter.firstMatch(in: text) ?? ""
    }

    var timeWithoutDate: String {
        guard let date = ExamRecord.dateFormatter.firstMatch(in: time),
              let range = time.range(of: date) else { return time }
        return time[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    private static let dateFormatter = DatePattern()
}

/// 从一段文本里抠日期，认三种写法：2027-01-12 / 2027年1月12日 / 1月12日
private struct DatePattern {
    func firstMatch(in text: String) -> String? {
        if let parts = groups(#"(\d{4})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{1,2})"#, in: text, count: 3) {
            return make(year: parts[0], month: parts[1], day: parts[2])
        }
        if let parts = groups(#"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#, in: text, count: 3) {
            return make(year: parts[0], month: parts[1], day: parts[2])
        }
        // 没写年份的，按学年的位置猜一个
        if let parts = groups(#"(\d{1,2})\s*月\s*(\d{1,2})\s*日"#, in: text, count: 2) {
            let calendar = Calendar.current
            let now = Date()
            let currentYear = calendar.component(.year, from: now)
            let currentMonth = calendar.component(.month, from: now)
            let month = Int(parts[0]) ?? currentMonth
            var year = currentYear
            if month >= 8 && currentMonth < 8 { year -= 1 }
            if month < 8 && currentMonth >= 8 { year += 1 }
            return make(year: "\(year)", month: parts[0], day: parts[1])
        }
        return nil
    }

    private func groups(_ pattern: String, in text: String, count: Int) -> [String]? {
        guard let first = text.regexGroups(pattern).first, first.count >= count else { return nil }
        return Array(first.prefix(count))
    }

    private func make(year: String, month: String, day: String) -> String? {
        guard let y = Int(year), let m = Int(month), let d = Int(day),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
