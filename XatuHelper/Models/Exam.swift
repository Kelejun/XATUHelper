import Foundation

/// 一条考试安排。树维的「我的考试」是服务端直出的表格，字段随学校配置略有差异，
/// 所以这里保留原始文本，解析时按表头找列。
struct ExamRecord: Identifiable, Hashable {
    var id: String
    var course: String      // 课程名称
    var name: String        // 考试名称
    var time: String        // 考试时间（原始文本）
    var room: String        // 考场
    var seat: String        // 座位号
    var note: String        // 备注

    /// 用来分组的日期，形如 "2027-01-12"；认不出来就留空
    var dateKey: String {
        ExamRecord.dateFormatter.firstMatch(in: time) ?? ""
    }

    var timeWithoutDate: String {
        guard let date = ExamRecord.dateFormatter.firstMatch(in: time),
              let range = time.range(of: date) else { return time }
        return time[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    private static let dateFormatter = DatePattern()
}

/// 从一段文本里抠 yyyy-MM-dd / yyyy/MM/dd / yyyy.MM.dd
private struct DatePattern {
    func firstMatch(in text: String) -> String? {
        let pattern = #"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let raw = String(text[range])
        let parts = raw.split(whereSeparator: { "-/. ".contains($0) })
        guard parts.count >= 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
