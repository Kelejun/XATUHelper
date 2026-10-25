import Foundation

/// 教务处「校历」列表页：抓第一条校历链接（页面按学年倒序排）
enum CalendarService {
    static let indexURL = "https://jwcw.xatu.edu.cn/index/xagydxxl.htm"

    static func latestCalendarURL() async -> URL? {
        guard let url = URL(string: indexURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }
        return latestLink(in: html)
    }

    /// 从列表页 HTML 里挑出第一条带「校历」字样的链接
    static func latestLink(in html: String) -> URL? {
        let pattern = #"<a[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let base = URL(string: indexURL)

        for match in regex.matches(in: html, options: [], range: range) {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else { continue }
            let href = String(html[hrefRange])
            let text = String(html[textRange]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            guard text.contains("校历") else { continue }
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            return url
        }
        return nil
    }
}
