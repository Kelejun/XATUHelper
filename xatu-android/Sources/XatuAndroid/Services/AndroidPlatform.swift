#if os(Android)
import Foundation
import SwiftUI
import SkipFuse

/// Small JNI boundary for Android APIs that have no Apple framework equivalent.
enum AndroidPlatform {
    static func call(_ operation: String, _ payload: String = "") -> String? {
        do {
            return try jniContext {
                let type = try JClass(name: "xatu/android/PlatformServices")
                guard let method = type.getStaticMethodID(name: "call", sig: "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;") else { return nil }
                let value: String = try type.callStatic(method: method, options: [], args: [operation.toJavaParameter(options: []), payload.toJavaParameter(options: [])])
                return value
            }
        } catch {
            logger.error("Android API failed: \(error)")
            return nil
        }
    }
}

extension CalendarService {
    static func ocr(_ data: Data, region: Foundation.CGRect) -> String? {
        // The ML Kit recognizer runs on the detached OCR task used by SchoolCalendarView.
        let payload: [String: Any] = ["image": data.base64EncodedString(), "x": Double(region.origin.x), "y": Double(region.origin.y), "width": Double(region.width), "height": Double(region.height)]
        guard let json = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: json, encoding: .utf8) else { return nil }
        return AndroidPlatform.call("ocr", text)
    }
}

// Adapt the existing reminder planner to Android AlarmManager.
enum UNAuthorizationStatus { case notDetermined, denied, authorized }
struct UNAuthorizationOptions: OptionSet {
    let rawValue: Int
    static let alert = Self(rawValue: 1), sound = Self(rawValue: 2), badge = Self(rawValue: 4)
}
final class UNMutableNotificationContent {
    var title = "", body = ""
    var sound: Sound?; enum Sound { case `default` }
    var interruptionLevel: Interruption = .active; enum Interruption { case active, timeSensitive }
}
struct UNCalendarNotificationTrigger {
    let dateMatching: DateComponents
    let repeats: Bool
}
struct UNNotificationRequest {
    let identifier: String
    let content: UNMutableNotificationContent
    let trigger: UNCalendarNotificationTrigger
}
struct AndroidNotificationSettings { let authorizationStatus: UNAuthorizationStatus }
final class UNUserNotificationCenter {
    static func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        AndroidPlatform.call("requestNotifications") == "authorized"
    }
    func notificationSettings() async -> AndroidNotificationSettings {
        let status = AndroidPlatform.call("notificationStatus")
        return AndroidNotificationSettings(authorizationStatus: status == "authorized" ? .authorized : status == "notDetermined" ? .notDetermined : .denied)
    }
    func add(_ request: UNNotificationRequest) async throws {
        guard let fire = Calendar.current.date(from: request.trigger.dateMatching) else { return }
        let payload: [String: Any] = ["id": request.identifier, "title": request.content.title, "body": request.content.body, "time": Int64(fire.timeIntervalSince1970 * 1000)]
        let data = try JSONSerialization.data(withJSONObject: payload)
        _ = AndroidPlatform.call("schedule", String(decoding: data, as: UTF8.self))
    }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) {
        // The planner clears and replaces all of its reminders as one batch.
        _ = AndroidPlatform.call("clearReminders")
    }
    func getPendingNotificationRequests(completion: ([UNNotificationRequest]) -> Void) { completion([]) }
}
#endif
