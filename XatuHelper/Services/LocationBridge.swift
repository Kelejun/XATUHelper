import CoreLocation
import Foundation

/// WKWebView 里 navigator.geolocation 是空的，签到那种必须定位的页面会直接转圈。
/// 这里补一个原生的定位服务，配合注入的 JS 把 getCurrentPosition 接到 CLLocationManager。
final class LocationBridge: NSObject, CLLocationManagerDelegate {
    /// watchPosition 时按这个间隔持续回传
    private let watchInterval: TimeInterval = 3

    private let manager = CLLocationManager()
    private var pending: [(Result<CLLocation, Error>) -> Void] = []
    private var watchTimers: [Int: Timer] = [:]
    private let allowsCustomLocation: Bool

    init(allowsCustomLocation: Bool = false) {
        self.allowsCustomLocation = allowsCustomLocation
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// 取一次定位，结果回主线程
    func request(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        if usesCustomLocation {
            if let coordinate = CheckinLocationSettings.coordinate() {
                completion(.success(coordinate.location))
            } else {
                completion(.failure(BridgeError.missingCustomLocation))
            }
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            pending.append(completion)
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            pending.append(completion)
            manager.requestLocation()
        default:
            completion(.failure(BridgeError.denied))
        }
    }

    /// watchPosition：立即回传，并定期从当前选定的定位来源重新取值。
    func startWatching(id: Int, handler: @escaping (CLLocation?) -> Void) {
        watchTimers[id]?.invalidate()
        request { result in
            if case let .success(location) = result {
                handler(location)
            }
        }
        watchTimers[id] = Timer.scheduledTimer(withTimeInterval: watchInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.request { result in
                if case let .success(location) = result {
                    handler(location)
                }
            }
        }
    }

    func stopWatching(id: Int) {
        watchTimers[id]?.invalidate()
        watchTimers[id] = nil
    }

    func stopAllWatching() {
        watchTimers.values.forEach { $0.invalidate() }
        watchTimers.removeAll()
        pending.removeAll()
        manager.stopUpdatingLocation()
    }

    deinit { watchTimers.values.forEach { $0.invalidate() } }

    enum BridgeError: LocalizedError {
        case denied
        case missingCustomLocation

        var errorDescription: String? {
            switch self {
            case .denied: return "App 没有定位权限"
            case .missingCustomLocation: return "请先在设置中选择有效的签到位置"
            }
        }
    }

    private var usesCustomLocation: Bool {
        allowsCustomLocation && UserDefaults.standard.bool(forKey: CheckinLocationSettings.enabledKey)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if !pending.isEmpty { manager.requestLocation() }
        case .denied, .restricted:
            flush(.failure(BridgeError.denied))
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        flush(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        flush(.failure(error))
    }

    private func flush(_ result: Result<CLLocation, Error>) {
        let handlers = pending
        pending = []
        DispatchQueue.main.async {
            // 若真实定位尚未完成时打开了测试开关，也不能回传实际坐标。
            let resolved: Result<CLLocation, Error>
            if self.usesCustomLocation {
                resolved = CheckinLocationSettings.coordinate().map { .success($0.location) }
                    ?? .failure(BridgeError.missingCustomLocation)
            } else {
                resolved = result
            }
            handlers.forEach { $0(resolved) }
        }
    }
}
