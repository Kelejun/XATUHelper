import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#else
import SwiftUI
#endif

/// 教务处「校历」：列表页 → 内容页 → 校历图片 → 本地 OCR → 结构化放假日
enum CalendarService {
    static let indexURL = "https://jwcw.xatu.edu.cn/index/xagydxxl.htm"

    // MARK: - 页面抓取

    struct CalendarPage {
        let title: String
        let pageURL: URL
        let imageURL: URL
    }

    struct TextError: Error {
        let reason: String
    }

    static let campusOnly = "您无权访问此页面"

    enum LoadError: LocalizedError {
        case index(String)
        case page(String)
        case image
        case download(String)

        var errorDescription: String? {
            switch self {
            case .index(let reason): return reason == campusOnly
                ? "这个页面只有校内网能打开，连上校园网再试"
                : "打不开教务处的校历列表（\(reason)）"
            case .page(let reason): return reason == campusOnly
                ? "这个页面只有校内网能打开，连上校园网再试"
                : "打不开校历正文页（\(reason)）"
            case .image: return "正文页里没找到校历图片，可能改版了"
            case .download(let reason): return "校历图片下载失败（\(reason)）"
            }
        }
    }

    static func loadPage() async -> Result<CalendarPage, LoadError> {
        guard let listURL = URL(string: indexURL) else { return .failure(.index("地址不对")) }

        switch await fetchHTML(listURL) {
        case .failure(let reason):
            return .failure(.index(reason.reason))
        case .success(let html):
            guard let pageURL = latestLink(in: html) else {
                return .failure(.index("列表页里没有带「校历」的链接"))
            }
            switch await fetchHTML(pageURL) {
            case .failure(let reason):
                return .failure(.page(reason.reason))
            case .success(let pageHTML):
                guard let imageURL = calendarImageURL(in: pageHTML, base: pageURL) else {
                    return .failure(.image)
                }
                let title = pageHTMLTitle(pageHTML) ?? "校历"
                return .success(CalendarPage(title: title, pageURL: pageURL, imageURL: imageURL))
            }
        }
    }

    static func latestLink(in html: String) -> URL? {
        let pattern = #"<a[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
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
            guard url.path != base?.path, !href.hasPrefix("#"),
                  url.path.contains("/info/") || url.path.contains("/news/") else { continue }
            return url
        }
        return nil
    }

    static func pageHTMLTitle(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title>\s*([^<]+?)\s*</title>"#, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[r]).replacingOccurrences(of: "-西安工业大学本科生院", with: "")
    }

    /// 内容页正文里那张校历大图
    static func calendarImageURL(in html: String, base: URL) -> URL? {
        let patterns = [
            #"<img[^>]+orisrc\s*=\s*"([^"]+)"[^>]*>"#,
            #"<img[^>]+src\s*=\s*"([^"]*__local[^"]+)"[^>]*>"#,
            #"<img[^>]+src\s*=\s*"([^"]+\.(?:jpg|png|jpeg))"[^>]*>"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, options: [], range: range) {
                guard let r = Range(match.range(at: 1), in: html) else { continue }
                let src = String(html[r])
                guard !src.contains("bottom-icon"), !src.contains("nav-"), !src.contains("logo") else { continue }
                if let url = URL(string: src, relativeTo: base)?.absoluteURL { return url }
            }
        }
        return nil
    }

    // MARK: - 图片与 OCR

    static func downloadImage(_ url: URL) async -> Result<Data, LoadError> {
        var request = URLRequest(url: url)
        request.setValue(indexURL, forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else { return .failure(.download("HTTP \(status)")) }
            return .success(data)
        } catch {
            return .failure(.download(describe(error)))
        }
    }

    /// 只认底部说明区，再退一次全图
    static func recognizeText(from imageData: Data) -> String {
        if let bottom = ocr(imageData, region: Foundation.CGRect(x: 0, y: 0, width: 1, height: 0.22)),
           !parseSemesters(from: bottom).isEmpty {
            return bottom
        }
        return ocr(imageData, region: Foundation.CGRect(x: 0, y: 0, width: 1, height: 1)) ?? ""
    }

    // MARK: - 解析

    struct SemesterSpan: Codable, Hashable {
        var label: String
        var start: String
        var end: String
    }

    struct Info: Codable {
        var title: String
        var pageURL: String
        var imageURL: String
        var semesters: [SemesterSpan]
        var notes: [String]
        var rawText: String
        var fetchedAt: Date
    }

    static func parse(_ text: String, title: String, pageURL: URL, imageURL: URL) -> Info {
        let semesters = parseSemesters(from: text)
        var notes: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let clean = line.replacingOccurrences(of: " ", with: "").trimmed
            guard !clean.isEmpty else { continue }
            if clean.contains("春节") || clean.contains("运动会") || clean.contains("法定节假日") {
                if !notes.contains(clean) { notes.append(clean) }
            }
        }
        return Info(
            title: title,
            pageURL: pageURL.absoluteString,
            imageURL: imageURL.absoluteString,
            semesters: semesters,
            notes: notes,
            rawText: text,
            fetchedAt: Date()
        )
    }

    static func parseSemesters(from text: String) -> [SemesterSpan] {
        let flattened = text
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "－", with: "-")
        let pattern = #"(\d{4})年(\d{1,2})月(\d{1,2})日[-—~至到]{1,2}(?:(\d{4})年)?(\d{1,2})月(\d{1,2})日"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(flattened.startIndex..<flattened.endIndex, in: flattened)
        var spans: [SemesterSpan] = []
        for (offset, match) in regex.matches(in: flattened, options: [], range: range).enumerated() {
            guard let r1 = Range(match.range(at: 1), in: flattened),
                  let r2 = Range(match.range(at: 2), in: flattened),
                  let r3 = Range(match.range(at: 3), in: flattened),
                  let r5 = Range(match.range(at: 5), in: flattened),
                  let r6 = Range(match.range(at: 6), in: flattened) else { continue }
            let startYear = Int(flattened[r1]) ?? 0
            let endYear: Int
            if match.range(at: 4).location != NSNotFound, let r4 = Range(match.range(at: 4), in: flattened) {
                endYear = Int(flattened[r4]) ?? startYear
            } else {
                endYear = startYear + ((Int(flattened[r5]) ?? 1) < (Int(flattened[r2]) ?? 1) ? 1 : 0)
            }
            let startMonth = Int(flattened[r2]) ?? 1
            let startDay = Int(flattened[r3]) ?? 1
            let endMonth = Int(flattened[r5]) ?? 1
            let endDay = Int(flattened[r6]) ?? 1
            let label = offset == 0 ? "第一学期" : (offset == 1 ? "第二学期" : "第\(offset + 1)学期")
            spans.append(SemesterSpan(
                label: label,
                start: String(format: "%04d-%02d-%02d", startYear, startMonth, startDay),
                end: String(format: "%04d-%02d-%02d", endYear, endMonth, endDay)
            ))
        }
        return spans
    }

    // MARK: - 工具

    static func fetchHTML(_ url: URL) async -> Result<String, TextError> {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else { return .failure(TextError(reason: "HTTP \(status)")) }
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(TextError(reason: "页面不是 UTF-8，\(data.count) 字节"))
            }
            // 教务处部分页面只对校内网开放，外面拿到的是「您无权访问此页面」
            if text.contains("无权访问") || text.contains("无权限访问") {
                return .failure(TextError(reason: "您无权访问此页面"))
            }
            return .success(text)
        } catch {
            return .failure(TextError(reason: describe(error)))
        }
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts = ["\(ns.domain) \(ns.code)"]
        if let url = ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String,
           let host = URL(string: url)?.host {
            parts.append(host)
        }
        if !ns.localizedDescription.isEmpty {
            parts.append(ns.localizedDescription)
        }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
