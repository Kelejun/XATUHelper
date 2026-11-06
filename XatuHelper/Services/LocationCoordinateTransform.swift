import CoreLocation
import Foundation

/// 网页 Geolocation 返回 WGS84；国内地图选点使用 GCJ02，必须在原生边界转换一次。
enum LocationCoordinateTransform {
    static func wgs84ToGCJ02(_ point: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lat = point.latitude, lng = point.longitude
        guard (72.004...137.8347).contains(lng), (0.8293...55.8271).contains(lat) else { return point }
        let x = lng - 105, y = lat - 35
        var dLat = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        dLat += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        dLat += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        dLat += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        var dLng = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        dLng += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        dLng += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        dLng += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        let radLat = lat / 180 * .pi
        let magic = 1 - 0.00669342162296594323 * pow(sin(radLat), 2)
        let root = sqrt(magic)
        dLat = dLat * 180 / ((6378245 * (1 - 0.00669342162296594323)) / (magic * root) * .pi)
        dLng = dLng * 180 / (6378245 / root * cos(radLat) * .pi)
        return CLLocationCoordinate2D(latitude: lat + dLat, longitude: lng + dLng)
    }

    static func gcj02ToWGS84(_ point: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        var result = point
        for _ in 0..<8 {
            let converted = wgs84ToGCJ02(result)
            let dLat = converted.latitude - point.latitude
            let dLng = converted.longitude - point.longitude
            result.latitude -= dLat
            result.longitude -= dLng
            if max(abs(dLat), abs(dLng)) < 1e-9 { break }
        }
        return result
    }
}
