import Foundation
import CoreLocation

@main
struct CheckinLocationSettingsTests {
    static func main() throws {
        typealias Coordinate = CheckinLocationSettings.Coordinate
        let suite = "CheckinLocationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        precondition(!defaults.bool(forKey: CheckinLocationSettings.enabledKey))
        precondition(CheckinLocationSettings.coordinate(in: defaults) == nil)
        for coordinate in [Coordinate(latitude: 0, longitude: 0),
                           Coordinate(latitude: -90, longitude: -180),
                           Coordinate(latitude: 90, longitude: 180),
                           Coordinate(latitude: 34.383123, longitude: 108.981456)] {
            let data = try JSONEncoder().encode(coordinate)
            defaults.set(data, forKey: CheckinLocationSettings.coordinateKey)
            // 重新创建存储实例，验证坐标可从持久化数据恢复，且精度不丢失。
            precondition(CheckinLocationSettings.coordinate(in: UserDefaults(suiteName: suite)!) == coordinate)
            defaults.set(true, forKey: CheckinLocationSettings.enabledKey)
            defaults.set(false, forKey: CheckinLocationSettings.enabledKey)
            precondition(CheckinLocationSettings.coordinate(in: defaults) == coordinate)
            precondition(coordinate.location.coordinate.latitude == coordinate.gpsCoordinate.latitude)
            precondition(coordinate.location.coordinate.longitude == coordinate.gpsCoordinate.longitude)
        }
        for coordinate in [Coordinate(latitude: 90.01, longitude: 0),
                           Coordinate(latitude: 0, longitude: -180.01),
                           Coordinate(latitude: .nan, longitude: 0),
                           Coordinate(latitude: 0, longitude: .infinity)] {
            precondition(!coordinate.isValid)
        }
        for invalid in ["{}", "invalid", "{\"latitude\":91,\"longitude\":0}"] {
            defaults.set(Data(invalid.utf8), forKey: CheckinLocationSettings.coordinateKey)
            precondition(CheckinLocationSettings.coordinate(in: defaults) == nil)
        }
        let legacy = Data("{\"latitude\":34.382367,\"longitude\":108.979667}".utf8)
        precondition(Coordinate.decode(legacy)?.system == .gcj02)
        let gps = CLLocationCoordinate2D(latitude: 39.916527, longitude: 116.397128)
        let map = LocationCoordinateTransform.wgs84ToGCJ02(gps)
        precondition(abs(map.latitude - 39.917930749) < 1e-8)
        precondition(abs(map.longitude - 116.403372494) < 1e-8)
        let restored = LocationCoordinateTransform.gcj02ToWGS84(map)
        precondition(abs(restored.latitude - gps.latitude) < 1e-8)
        precondition(abs(restored.longitude - gps.longitude) < 1e-8)
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        precondition(LocationCoordinateTransform.gcj02ToWGS84(london).latitude == london.latitude)
        let rawGPS = Coordinate(latitude: gps.latitude, longitude: gps.longitude, system: .wgs84)
        precondition(rawGPS.location.coordinate.latitude == gps.latitude)
        precondition(rawGPS.location.coordinate.longitude == gps.longitude)
        let rawGPSData = try JSONEncoder().encode(rawGPS)
        precondition(Coordinate.decode(rawGPSData) == rawGPS)
        print("Checkin location persistence and validation tests passed")
    }
}
