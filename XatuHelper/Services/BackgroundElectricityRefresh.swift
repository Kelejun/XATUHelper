import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

@MainActor
enum BackgroundElectricityRefresh {
    static let identifier = "com.cell.xatuapp.electricity.refresh"
    static let terminationCallbackKey = "electricity.exit.lastTerminationCallback"
    static let exitNotificationErrorKey = "electricity.exit.lastNotificationError"
    static let exitNotificationStatusKey = "electricity.exit.lastNotificationStatus"
    static let testNotificationIdentifier = "electricity-background-exit-test"
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

    static var lastTerminationCallback: Date? {
        UserDefaults.standard.object(forKey: terminationCallbackKey) as? Date
    }

    static var lastExitNotificationError: String? {
        UserDefaults.standard.string(forKey: exitNotificationErrorKey)
    }

    static var lastExitNotificationStatus: String? {
        UserDefaults.standard.string(forKey: exitNotificationStatusKey)
    }

    /// 在进程仍运行时交给系统，单独验证通知通道，不依赖终止回调。
    static func scheduleTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "后台电费刷新提醒（测试）"
        content.body = "这是一条测试通知。实际退出提醒仍依赖系统退出回调，后台自动刷新电费可能不生效。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: testNotificationIdentifier, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        try await UNUserNotificationCenter.current().add(request)
    }

    static func clearExitReminder(includingTests: Bool = true) {
        let center = UNUserNotificationCenter.current()
        let identifiers = includingTests
            ? [exitNotificationIdentifier, testNotificationIdentifier] : [exitNotificationIdentifier]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// 只在系统实际发出终止回调时尽力发送，不把普通退后台当成强制退出。
    static func notifyOnTermination() {
        UserDefaults.standard.set(Date(), forKey: terminationCallbackKey)
        UserDefaults.standard.removeObject(forKey: exitNotificationErrorKey)
        guard ElectricityRefreshSettings.exitReminderEnabled else {
            UserDefaults.standard.set("提醒开关未开启", forKey: exitNotificationStatusKey)
            return
        }
        guard Preferences.studentID != nil, Preferences.dorm != nil else {
            UserDefaults.standard.set("缺少已保存的账号或宿舍信息", forKey: exitNotificationStatusKey)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "后台电费刷新提醒"
        content.body = "App 即将退出，自动后台刷新电费可能不生效。请重新打开 App，并避免在多任务界面划掉。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: exitNotificationIdentifier,
                                            content: content, trigger: nil)
        // 不能用会随进程退出而丢失的 Task。给同步终止回调最多一秒，等待系统确认提交。
        // 回调不要求主线程；无论回调是否及时到达，都不会无限阻塞退出。
        UserDefaults.standard.set("已尝试提交通知", forKey: exitNotificationStatusKey)
        let errorKey = exitNotificationErrorKey
        let statusKey = exitNotificationStatusKey
        let submission = TerminationNotificationSubmission()
        UNUserNotificationCenter.current().add(request) { error in
            submission.complete {
                if let error {
                    UserDefaults.standard.set(error.localizedDescription, forKey: errorKey)
                    UserDefaults.standard.set("通知提交失败", forKey: statusKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: errorKey)
                    UserDefaults.standard.set("通知已提交系统", forKey: statusKey)
                }
            }
        }
        submission.wait(timeout: 1) {
            UserDefaults.standard.set("退出前未等到通知提交确认", forKey: statusKey)
        }
    }
}

final class ElectricityRefreshAppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        BackgroundElectricityRefresh.notifyOnTermination()
    }
}
