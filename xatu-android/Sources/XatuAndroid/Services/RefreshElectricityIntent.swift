#if canImport(AppIntents)
import AppIntents
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum RefreshRequest {
    static let electricityKey = "xatu.pendingElectricityRefresh"
    static let notification = Notification.Name("xatu.refreshElectricityRequested")

    static func pendingElectricityRefresh() -> Bool {
        UserDefaults.standard.bool(forKey: electricityKey)
    }

    static func clearElectricityRefresh() {
        UserDefaults.standard.removeObject(forKey: electricityKey)
    }
}

/// 点小组件右上角的刷新：带 openAppWhenRun，系统会先拉起 App 再执行，
/// 执行完往 App 里丢一个标记，App 收到就去刷电费。
#if canImport(AppIntents)
struct RefreshElectricityIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新电费"
    static var description = IntentDescription("打开 App 并刷新电费余额。")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: RefreshRequest.electricityKey)
        NotificationCenter.default.post(name: RefreshRequest.notification, object: nil)
        return .result()
    }
}

#endif
