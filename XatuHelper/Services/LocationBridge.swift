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
    private var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// 取一次定位，结果回主线程
    func request(completion: @escaping (Result<CLLocation, Error>) -> Void) {
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

    /// watchPosition：先立刻取一次，再按间隔回传最后一次的位置
    func startWatching(id: Int, handler: @escaping (CLLocation?) -> Void) {
        watchTimers[id]?.invalidate()
        request { result in
            if case let .success(location) = result {
                self.lastLocation = location
            }
        }
        watchTimers[id] = Timer.scheduledTimer(withTimeInterval: watchInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            handler(self.lastLocation)
        }
    }

    func stopWatching(id: Int) {
        watchTimers[id]?.invalidate()
        watchTimers[id] = nil
    }

    enum BridgeError: LocalizedError {
        case denied

        var errorDescription: String? {
            switch self {
            case .denied: return "App 没有定位权限"
            }
        }
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
        lastLocation = location
        flush(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        flush(.failure(error))
    }

    private func flush(_ result: Result<CLLocation, Error>) {
        let handlers = pending
        pending = []
        DispatchQueue.main.async {
            handlers.forEach { $0(result) }
        }
    }
}
