import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

final class PortabilityTests: XCTestCase {
    func testCASCompatibleAES() {
        // Independently produced using OpenSSL AES-128-CBC with PKCS7 padding.
        XCTAssertEqual(Crypto.aesCBCEncrypt("xatu-password", key: "0123456789abcdef", iv: "fedcba9876543210"), "PNK7KHZdk4qpd+KsL0UtUw==")
        XCTAssertNil(Crypto.aesCBCEncrypt("password", key: "short", iv: "fedcba9876543210"))
    }

    func testWeekMaskAndConsecutivePeriods() {
        let html = #"""
        var unitCount = 12;
        var actTeachers = [{name:"张老师"}];
        activity = new TaskActivity("t", "t", "060020", "计算机网络(060020.03)", "r", "教3-201", "011010");
        index = 0*unitCount+2;
        index = 0*unitCount+3;
        """#
        let parsed = TimetableParser.parse(html)
        XCTAssertEqual(parsed.unitCount, 12)
        XCTAssertEqual(parsed.rawCount, 1)
        XCTAssertEqual(parsed.occurrences.count, 2)
        XCTAssertEqual(parsed.occurrences.first?.weeks, [1, 2, 4])
        XCTAssertEqual(parsed.occurrences.first?.name, "计算机网络")
        XCTAssertEqual(parsed.occurrences.first?.teacher, "张老师")
        let blocks = parsed.occurrences.courseBlocks()
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.day, 1)
        XCTAssertEqual(blocks.first?.startPeriod, 3)
        XCTAssertEqual(blocks.first?.endPeriod, 4)
    }

    func testOnlineCoursesRemainExcluded() {
        let html = #"new TaskActivity("t","t","1","线上课","r","线上教室","0100"); index = 1*unitCount+0;"#
        let parsed = TimetableParser.parse(html)
        XCTAssertEqual(parsed.rawCount, 1)
        XCTAssertTrue(parsed.occurrences.isEmpty)
    }
}

final class AuthenticationPortabilityTests: XCTestCase {
    func testSliderCaptchaUsesTheAccountDecision() {
        let html = #"var captchaSwitch = "2"; var needCaptcha = ""; var _badCredentialsCount="3";"#
        XCTAssertTrue(CASLoginPolicy.captchaEnabled(in: html))
        XCTAssertFalse(CASLoginPolicy.explicitlyRequiresCaptcha(in: html))
        XCTAssertEqual(CASLoginPolicy.captchaDecision(from: Data(#"{"isNeed":true}"#.utf8)), true)
        XCTAssertEqual(CASLoginPolicy.captchaDecision(from: Data(#"{"isNeed":false}"#.utf8)), false)
    }

    func testMandatoryAndDisabledChallenges() {
        XCTAssertTrue(CASLoginPolicy.explicitlyRequiresCaptcha(in: #"var captchaSwitch="2";var needCaptcha=true;"#))
        XCTAssertTrue(CASLoginPolicy.explicitlyRequiresCaptcha(in: #"var captchaSwitch="1";var _badCredentialsCount="0";"#))
        XCTAssertFalse(CASLoginPolicy.captchaEnabled(in: #"var captchaSwitch="0";"#))
        XCTAssertNil(CASLoginPolicy.captchaDecision(from: Data("<html>session expired</html>".utf8)))
    }

    func testWebCookieMetadataPreservesEamsPathAndHttpOnly() throws {
        let url = URL(string: "http://jwgl2018.xatu.edu.cn/eams/homeExt.action")!
        let cookies = WebSessionCookies.parse(records: ["JSESSIONID=eams-fixture; Path=/eams; HttpOnly"], for: url)
        let cookie = try XCTUnwrap(cookies.first)
        XCTAssertEqual(cookie.path, "/eams")
        XCTAssertEqual(cookie.domain, "jwgl2018.xatu.edu.cn")
        XCTAssertTrue(cookie.isHTTPOnly)
        XCTAssertFalse(cookie.isSecure)
        let storage = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        WebSessionCookies.install(cookies, in: storage)
        XCTAssertTrue((storage.cookies(for: url) ?? []).contains { $0.value == "eams-fixture" })
        XCTAssertFalse((storage.cookies(for: URL(string: "http://jwgl2018.xatu.edu.cn/")!) ?? []).contains { $0.name == "JSESSIONID" })
        XCTAssertTrue((storage.cookies(for: URL(string: "https://authserver.xatu.edu.cn/authserver/login")!) ?? []).isEmpty)
    }

    func testWebCookieImportReplacesLegacyWrongScope() throws {
        let storage = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let url = URL(string: "http://jwgl2018.xatu.edu.cn/eams/homeExt.action")!
        let old = try XCTUnwrap(HTTPCookie(properties: [.name: "JSESSIONID", .value: "stale", .domain: "jwgl2018.xatu.edu.cn", .path: "/"]))
        storage.setCookie(old)
        WebSessionCookies.install(WebSessionCookies.parse(records: ["JSESSIONID=fresh; Domain=.jwgl2018.xatu.edu.cn; Path=/eams; HttpOnly"], for: url), in: storage)
        XCTAssertEqual((storage.cookies(for: url) ?? []).filter { $0.name == "JSESSIONID" }.map(\.value), ["fresh"])
    }

    func testLegacyCookieFallbackQueriesTheApplicationPath() throws {
        let scope = try XCTUnwrap(WebSessionCookies.scopes.first { $0.url.path == "/eams/homeExt.action" })
        let cookie = try XCTUnwrap(WebSessionCookies.parseLegacy(header: "JSESSIONID=fixture", scope: scope).first)
        XCTAssertEqual(cookie.path, "/eams")
        XCTAssertTrue(WebSessionCookies.scopes.contains { $0.url.path == "/authserver/login" })
        XCTAssertFalse(WebSessionCookies.isCampusHost("evilxatu.edu.cn"))
    }
}

final class ScopedHTTPSessionTests: XCTestCase {
    func testPathBoundaryAndSecureMatching() throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "JSESSIONID", .value: "fixture", .domain: "authserver.xatu.edu.cn", .path: "/authserver", .secure: "TRUE"]))
        XCTAssertTrue(ScopedHTTPSession.matches(cookie, url: URL(string: "https://authserver.xatu.edu.cn/authserver/login")!))
        XCTAssertFalse(ScopedHTTPSession.matches(cookie, url: URL(string: "https://authserver.xatu.edu.cn/authserver-other")!))
        XCTAssertFalse(ScopedHTTPSession.matches(cookie, url: URL(string: "https://authserver.xatu.edu.cn/")!))
        XCTAssertFalse(ScopedHTTPSession.matches(cookie, url: URL(string: "http://authserver.xatu.edu.cn/authserver/login")!))
        XCTAssertFalse(ScopedHTTPSession.matches(cookie, url: URL(string: "https://evil-authserver.xatu.edu.cn/authserver/login")!))
    }

    func testRedirectReplacesPreviousCookieHeaderWithMatchingSession() throws {
        let storage = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        for (path, value) in [("/authserver", "auth-fixture"), ("/eams", "eams-fixture")] {
            storage.setCookie(try XCTUnwrap(HTTPCookie(properties: [.name: "JSESSIONID", .value: value, .domain: "campus.xatu.edu.cn", .path: path])))
        }
        var redirected = URLRequest(url: URL(string: "http://campus.xatu.edu.cn/eams/homeExt.action")!)
        redirected.setValue("JSESSIONID=auth-fixture", forHTTPHeaderField: "Cookie")
        let prepared = ScopedHTTPSession.prepare(redirected, storage: storage)
        XCTAssertEqual(prepared.value(forHTTPHeaderField: "Cookie"), "JSESSIONID=eams-fixture")
        XCTAssertFalse(prepared.httpShouldHandleCookies)
    }

    func testRedirectResponseStoresSessionBeforeNextRequest() throws {
        let storage = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let url = URL(string: "http://jwgl2018.xatu.edu.cn/eams/casLogin.action")!
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Set-Cookie": "JSESSIONID=new-ticket-session; Path=/eams; HttpOnly", "Location": "/eams/homeExt.action"]))
        ScopedHTTPSession.storeCookies(from: response, in: storage)
        let next = ScopedHTTPSession.prepare(URLRequest(url: URL(string: "http://jwgl2018.xatu.edu.cn/eams/homeExt.action")!), storage: storage)
        XCTAssertEqual(next.value(forHTTPHeaderField: "Cookie"), "JSESSIONID=new-ticket-session")
    }
}
