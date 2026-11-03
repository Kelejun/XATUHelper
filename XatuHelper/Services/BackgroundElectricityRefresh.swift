import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

@MainActor
enum BackgroundElectricityRefresh {
    static let identifier = "com.cell.xatuapp.electricity.refresh"
    static let exitNotificationIdentifier = "electricity-background-exit"

    /// 每次用当前开关、账号和日期替换请求，关闭设置时同步撤销。
    static func schedule(isLoggedIn: Bool, hasDorm: Bool, checkedAt: Date?,
                         hasBalance: Bool, now: Date = Date()) -> String? {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard isLoggedIn, hasDorm, ElectricityRefreshSettings.backgroundEnabled,
              let date = ElectricityRefreshPolicy.nextRequestDate(
                now: now, checkedAt: checkedAt, hasBalance: hasBalance,
                lastAttempt: ElectricityRefreshSettings.lastBackgroundAttempt,
                awaitingForeground: ElectricityRefreshSettings.awaitingForeground
              ) else { return nil }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
            return nil
        } catch {
            return "未能安排后台刷新，请确认系统已允许本 App 的后台 App 刷新。"
        }
    }

    static func clearExitReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [exitNotificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [exitNotificationIdentifier])
    }

    /// 只在系统实际发出终止回调时尽力发送，不把普通退后台当成强制退出。
    static func notifyOnTermination() {
        guard ElectricityRefreshSettings.exitReminderEnabled,
              Preferences.studentID != nil, Preferences.dorm != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "后台电费刷新提醒"
        content.body = "App 即将退出，自动后台刷新电费可能不生效。请重新打开 App，并避免在多任务界面划掉。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: exitNotificationIdentifier,
                                            content: content, trigger: nil)
        // 终止回调中不能等待异步 Task；尽快把通知交给系统。
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

final class ElectricityRefreshAppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        BackgroundElectricityRefresh.notifyOnTermination()
    }
}
