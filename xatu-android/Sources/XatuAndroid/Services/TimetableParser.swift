import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 解析树维 EAMS 课表页里那段 JS 生成的课表。
enum TimetableParser {
    struct Parsed {
        var occurrences: [CourseOccurrence]
        var unitCount: Int
        /// 原始 TaskActivity 条数（剔除占位课前），用来区分"这学期没课"和"接口没给数据"
        var rawCount: Int
    }

    static func parse(_ html: String) -> Parsed {
        let unitCount = Int(html.firstMatch(#"var\s+unitCount\s*=\s*(\d+)"#) ?? "") ?? 12
        let chunks = html.components(separatedBy: "new TaskActivity")
        guard chunks.count > 1 else {
            return Parsed(occurrences: [], unitCount: unitCount, rawCount: 0)
        }

        var merged: [String: CourseOccurrence] = [:]
        var order: [String] = []
        var rawCount = 0

        for index in 1..<chunks.count {
            let chunk = chunks[index]
            guard let argumentText = leadingArguments(chunk) else { continue }
            let args = splitArgs(argumentText)
            guard args.count >= 7 else { continue }

            let codeRaw = unquote(args[2])
            let nameRaw = unquote(args[3])
            let room = unquote(args[5])
            let mask = unquote(args[6])

            // 一门课一周上几节，就有几条 `index = 天*unitCount+节`
            let positions = chunk.regexGroups(#"index\s*=\s*(\d+)\s*\*\s*unitCount\s*\+\s*(\d+)"#)
            guard !positions.isEmpty else { continue }

            let (code, displayName) = splitCodeName(nameRaw, fallbackCode: codeRaw)
            let teacher = teacherNames(before: chunks[index - 1])
            // 树维的周次掩码是按「周序号」直接落位的：第 1 周在 index 1，index 0 空着
            let weeks = mask.enumerated().compactMap { $0.element == "1" && $0.offset > 0 ? $0.offset : nil }
            guard !weeks.isEmpty else { continue }
            rawCount += 1

            // 线上教室（平台修读）和"实践环节选课（供选课参考）"都不是要去的课，直接不进课表
            let isRemote = room.contains("线上") || room.contains("平台修读") || room.contains("虚拟教室")
            let isPlaceholder = room.contains("实践环节")
                || room.contains("供选课参考")
                || displayName.contains("实践环节")
            guard !isRemote, !isPlaceholder else { continue }

            for position in positions {
                guard position.count >= 2,
                      let dayIndex = Int(position[0]),
                      let periodIndex = Int(position[1]) else { continue }

                let key = "\(code)|\(dayIndex)|\(periodIndex)|\(room)|\(teacher)"
                if var existing = merged[key] {
                    existing.weeks = Array(Set(existing.weeks).union(weeks)).sorted()
                    merged[key] = existing
                } else {
                    let occurrence = CourseOccurrence(
                        id: key,
                        courseKey: code,
                        name: displayName,
                        teacher: teacher,
                        room: room,
                        day: dayIndex + 1,
                        period: periodIndex + 1,
                        weeks: weeks.sorted(),
                        isRemote: false,
                        isPlaceholder: false
                    )
                    merged[key] = occurrence
                    order.append(key)
                }
            }
        }

        let occurrences = order.compactMap { merged[$0] }
            .sorted { ($0.day, $0.period) < ($1.day, $1.period) }
        return Parsed(occurrences: occurrences, unitCount: unitCount, rawCount: rawCount)
    }

    /// `new TaskActivity(...)` 里括号内的参数原文，字符串里的括号不算
    private static func leadingArguments(_ chunk: String) -> String? {
        guard let open = chunk.firstIndex(of: "(") else { return nil }
        let contentStart = chunk.index(after: open)

        var depth = 0
        var inString = false
        var escaped = false
        var cursor = open

        while cursor < chunk.endIndex {
            let ch = chunk[cursor]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                switch ch {
                case "\"":
                    inString = true
                case "(":
                    depth += 1
                case ")":
                    depth -= 1
                    if depth == 0 { return String(chunk[contentStart..<cursor]) }
                default:
                    break
                }
            }
            cursor = chunk.index(after: cursor)
        }
        return nil
    }

    /// 课程名和课程号在括号里：计算机网络(060020.03)
    private static func splitCodeName(_ name: String, fallbackCode: String) -> (String, String) {
        if let range = name.range(of: #"\(([^()]*)\)\s*$"#, options: .regularExpression) {
            let code = String(name[range]).trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            let display = String(name[name.startIndex..<range.lowerBound])
            return (code, display)
        }
        let code = fallbackCode.regexGroups(#"\(([^()]*)\)"#).first?.first ?? fallbackCode
        return (code, name)
    }

    /// 找上一段里最后一个 `var actTeachers = [...]` 的姓名
    private static func teacherNames(before text: String) -> String {
        guard let range = text.range(of: "var actTeachers", options: .backwards) else { return "" }
        let tail = String(text[range.lowerBound...])
        let names = tail.regexGroups(#"name:"([^"]*)""#).compactMap { $0.first }
        return names.joined(separator: "、")
    }

    private static func unquote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\"") { t.removeFirst() }
        if t.hasSuffix("\"") { t.removeLast() }
        return t
    }

    /// 按顶层逗号切参数，跳过引号和括号内部的逗号
    static func splitArgs(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inString = false
        var depth = 0
        var escaped = false

        for ch in s {
            if inString {
                current.append(ch)
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                switch ch {
                case "\"":
                    inString = true
                    current.append(ch)
                case "(":
                    depth += 1
                    current.append(ch)
                case ")":
                    depth -= 1
                    current.append(ch)
                case "," where depth == 0:
                    result.append(current)
                    current = ""
                default:
                    current.append(ch)
                }
            }
        }
        result.append(current)
        return result.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
