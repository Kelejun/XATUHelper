import Foundation

enum AnnouncementMarkdownBlock: Equatable {
    case heading(Int, String), paragraph(String), listItem(String, String), quote(String), code(String), divider

    static func parse(_ source: String) -> [Self] {
        var blocks: [Self] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for raw in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flush()
                if let content = code { blocks.append(.code(content.joined(separator: "\n"))); code = nil }
                else { code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.isEmpty { flush(); continue }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                flush(); blocks.append(.heading(hashes, String(line.dropFirst(hashes + 1)))); continue
            }
            if ["---", "***", "___"].contains(line) { flush(); blocks.append(.divider); continue }
            if line.hasPrefix(">") {
                flush(); blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); continue
            }
            if ["- ", "* ", "+ "].contains(String(line.prefix(2))) {
                flush(); blocks.append(.listItem("•", String(line.dropFirst(2)))); continue
            }
            if let separator = line.firstIndex(where: { $0 == "." || $0 == ")" }),
               Int(line[..<separator]) != nil, line[line.index(after: separator)...].hasPrefix(" ") {
                flush()
                blocks.append(.listItem(String(line[...separator]), String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)))
                continue
            }
            paragraph.append(raw)
        }
        flush()
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        return blocks
    }
}
