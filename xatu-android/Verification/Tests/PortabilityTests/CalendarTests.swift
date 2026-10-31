import Foundation
import XCTest

// These tests exercise HTML/date parsing; OCR itself is tested on Android.
extension CalendarService {
    static func ocr(_ data: Data, region: CGRect) -> String? { nil }
}

final class CalendarTests: XCTestCase {
    func testCalendarListSkipsNavigationAndAcceptsCurrentArticleURL() {
        let html = #"<a href="xagydxxl.htm">校历</a><a href="../news/content.jsp?wbnewsid=200057">2026-2027学年校历</a><a href="../info/15497/199345.htm">2025-2026学年校历</a>"#
        XCTAssertEqual(CalendarService.latestLink(in: html)?.absoluteString, "https://jwcw.xatu.edu.cn/news/content.jsp?wbnewsid=200057")
    }
    func testCalendarPrefersFullResolutionImageAndHandlesUppercaseTitle() {
        let html = #"<TITLE>2026-2027学年校历-西安工业大学本科生院</TITLE><img src="logo.png"><img src="/__local/thumb.jpg" orisrc="/__local/original.jpg">"#
        XCTAssertEqual(CalendarService.pageHTMLTitle(html), "2026-2027学年校历")
        XCTAssertEqual(CalendarService.calendarImageURL(in: html, base: URL(string: CalendarService.indexURL)!)?.path, "/__local/original.jpg")
    }
    func testSemesterDatesFromPublic2026Calendar() {
        let text = "2026-2027（1）学期：教学周20周（2026年8月31日–2027年1月15日）。\n2026-2027（2）学期：教学周20周（2027年3月1日-2027年7月16日）。"
        let spans = CalendarService.parseSemesters(from: text)
        XCTAssertEqual(spans.map(\.start), ["2026-08-31", "2027-03-01"])
        XCTAssertEqual(spans.map(\.end), ["2027-01-15", "2027-07-16"])
    }
    func testOCRWhitespaceAndImplicitCrossYear() {
        let spans = CalendarService.parseSemesters(from: "2026 年 8 月 31 日\r\n－\t1月15日")
        XCTAssertEqual(spans.first?.end, "2027-01-15")
    }
}
