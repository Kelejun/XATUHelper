import Foundation

enum ElectricityRefreshSettings {
    static let automaticKey = "autoRefreshElectricity"
    static let backgroundKey = "backgroundRefreshElectricity"
    static let exitReminderKey = "backgroundElectricityExitReminder"
    static let lastAttemptKey = "electricity.background.lastAttempt"
    static let awaitingForegroundKey = "electricity.background.awaitingForeground"

    static var automaticEnabled: Bool {
        UserDefaults.standard.object(forKey: automaticKey) as? Bool ?? true
    }

    static var backgroundEnabled: Bool {
        automaticEnabled && UserDefaults.standard.bool(forKey: backgroundKey)
    }

    static var exitReminderEnabled: Bool {
        backgroundEnabled && UserDefaults.standard.bool(forKey: exitReminderKey)
    }

    static var lastBackgroundAttempt: Date? {
        get { UserDefaults.standard.object(forKey: lastAttemptKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastAttemptKey) }
    }

    /// 发起后台请求前就持久化；超时或进程中断也只能等前台补查。
    static var awaitingForeground: Bool {
        get { UserDefaults.standard.bool(forKey: awaitingForegroundKey) }
        set { UserDefaults.standard.set(newValue, forKey: awaitingForegroundKey) }
    }

    static func resetAttempts() {
        UserDefaults.standard.removeObject(forKey: lastAttemptKey)
        UserDefaults.standard.removeObject(forKey: awaitingForegroundKey)
    }
}

enum ElectricityRefreshSource: Equatable {
    case manual, automatic, background

    var isAllowed: Bool {
        switch self {
        case .manual: return true
        case .automatic: return ElectricityRefreshSettings.automaticEnabled
        case .background: return ElectricityRefreshSettings.backgroundEnabled
        }
    }
}

/// 仅计算本地日历日期，便于验证跨日、时区与夏令时；不承诺系统准时执行。
enum ElectricityRefreshPolicy {
    static func hasRefreshedToday(checkedAt: Date?, hasBalance: Bool,
                                  now: Date, calendar: Calendar = .current) -> Bool {
        guard hasBalance, let checkedAt else { return false }
        return calendar.isDate(checkedAt, inSameDayAs: now)
    }

    static func canAttempt(now: Date, checkedAt: Date?, hasBalance: Bool,
                           lastAttempt: Date?, awaitingForeground: Bool,
                           calendar: Calendar = .current) -> Bool {
        guard !awaitingForeground,
              !hasRefreshedToday(checkedAt: checkedAt, hasBalance: hasBalance, now: now, calendar: calendar),
              let start = calendar.date(bySettingHour: 0, minute: 1, second: 0, of: now),
              now >= start else { return false }
        return lastAttempt.map { !calendar.isDate($0, inSameDayAs: now) } ?? true
    }

    static func nextRequestDate(now: Date, checkedAt: Date?, hasBalance: Bool,
                                lastAttempt: Date?, awaitingForeground: Bool,
                                calendar: Calendar = .current) -> Date? {
        guard !awaitingForeground,
              let start = calendar.date(bySettingHour: 0, minute: 1, second: 0, of: now) else { return nil }
        let attemptedToday = lastAttempt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        if attemptedToday || hasRefreshedToday(checkedAt: checkedAt, hasBalance: hasBalance,
                                               now: now, calendar: calendar) {
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        return max(now, start)
    }
}
