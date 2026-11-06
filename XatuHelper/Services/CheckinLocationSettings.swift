import CoreLocation
import Foundation

/// 仅供签到网页使用；开关和坐标独立保存，关闭后仍保留上次选点。
enum CheckinLocationSettings {
    static let enabledKey = "checkinCustomLocationEnabled"
    static let coordinateKey = "checkinCustomLocationCoordinate"
    static let revealedKey = "checkinCustomLocationRevealed"

    struct Coordinate: Codable, Equatable {
        enum System: String, Codable, CaseIterable {
            case gcj02, wgs84

            var title: String {
                switch self {
                case .gcj02: return "地图 / 高德（GCJ02）"
                case .wgs84: return "GPS（WGS84）"
                }
            }
        }
        let latitude: Double
        let longitude: Double
        let system: System

        init(latitude: Double, longitude: Double, system: System = .gcj02) {
            self.latitude = latitude
            self.longitude = longitude
            self.system = system
        }

        private enum CodingKeys: String, CodingKey { case latitude, longitude, system }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            latitude = try values.decode(Double.self, forKey: .latitude)
            longitude = try values.decode(Double.self, forKey: .longitude)
            // 首版保存的是地图原始坐标，没有坐标系字段。
            system = try values.decodeIfPresent(System.self, forKey: .system) ?? .gcj02
        }

        var isValid: Bool {
            latitude.isFinite && longitude.isFinite
                && (-90...90).contains(latitude) && (-180...180).contains(longitude)
        }

        static func decode(_ data: Data) -> Self? {
            guard let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
            return value
        }

        var location: CLLocation {
            CLLocation(coordinate: gpsCoordinate,
                       altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: Date())
        }

        var gpsCoordinate: CLLocationCoordinate2D {
            let point = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return system == .gcj02 ? LocationCoordinateTransform.gcj02ToWGS84(point) : point
        }

        var mapCoordinate: CLLocationCoordinate2D {
            let point = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return system == .wgs84 ? LocationCoordinateTransform.wgs84ToGCJ02(point) : point
        }
    }

    static func coordinate(in defaults: UserDefaults = .standard) -> Coordinate? {
        Coordinate.decode(defaults.data(forKey: coordinateKey) ?? Data())
    }
}
