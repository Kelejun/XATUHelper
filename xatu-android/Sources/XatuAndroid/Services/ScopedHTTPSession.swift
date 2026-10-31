import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// FoundationNetworking cookies(for:) does not filter Path/Secure on Android.
/// Select cookies explicitly for each request, including every redirect target.
final class ScopedHTTPSession: @unchecked Sendable {
    let storage: HTTPCookieStorage
    private let session: URLSession

    init(storage: HTTPCookieStorage = .shared, onRedirect: ((HTTPURLResponse, URLRequest) -> Void)? = nil) {
        self.storage = storage
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config, delegate: RedirectDelegate(storage: storage, onRedirect: onRedirect), delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let result = try await session.data(for: Self.prepare(request, storage: storage))
        if let response = result.1 as? HTTPURLResponse { Self.storeCookies(from: response, in: storage) }
        return result
    }

    static func matches(_ cookie: HTTPCookie, url: URL, now: Date = Date()) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let rawDomain = cookie.domain.lowercased()
        let domain = rawDomain.hasPrefix(".") ? String(rawDomain.dropFirst()) : rawDomain
        guard host == domain || (rawDomain.hasPrefix(".") && host.hasSuffix("." + domain)) else { return false }
        guard !cookie.isSecure || url.scheme?.lowercased() == "https" else { return false }
        if let expires = cookie.expiresDate, expires <= now { return false }
        let path = cookie.path.isEmpty ? "/" : cookie.path
        let requestPath = url.path.isEmpty ? "/" : url.path
        return requestPath == path || (requestPath.hasPrefix(path) && (path.hasSuffix("/") || requestPath.dropFirst(path.count).hasPrefix("/")))
    }

    static func prepare(_ request: URLRequest, storage: HTTPCookieStorage) -> URLRequest {
        var next = request
        next.httpShouldHandleCookies = false
        next.setValue(nil, forHTTPHeaderField: "Cookie")
        if let url = request.url {
            let matching = (storage.cookies ?? []).filter { matches($0, url: url) }
                .sorted { $0.path.count > $1.path.count }
            if !matching.isEmpty {
                next.setValue(HTTPCookie.requestHeaderFields(with: matching)["Cookie"], forHTTPHeaderField: "Cookie")
            }
        }
        return next
    }

    static func storeCookies(from response: HTTPURLResponse, in storage: HTTPCookieStorage) {
        guard let url = response.url, let host = url.host?.lowercased() else { return }
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { output, item in
            output[String(describing: item.key)] = String(describing: item.value)
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard host == domain || host.hasSuffix("." + domain) else { continue }
            storage.setCookie(cookie)
        }
    }

    private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let storage: HTTPCookieStorage
        let onRedirect: ((HTTPURLResponse, URLRequest) -> Void)?
        init(storage: HTTPCookieStorage, onRedirect: ((HTTPURLResponse, URLRequest) -> Void)?) {
            self.storage = storage
            self.onRedirect = onRedirect
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            ScopedHTTPSession.storeCookies(from: response, in: storage)
            let next = ScopedHTTPSession.prepare(request, storage: storage)
            onRedirect?(response, next)
            completionHandler(next)
        }
    }
}
