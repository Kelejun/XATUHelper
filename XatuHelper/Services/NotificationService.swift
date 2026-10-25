import Foundation
import UserNotifications

/// 通知相关开关都存在 UserDefaults 里，视图和 service 都读这里
enum NotificationSettings {
    static let classEnabled = "notify.class.enabled"
    static let classLead = "notify.class.lead"
    static let examEnabled = "notify.exam.enabled"
    static let examLead = "notify.exam.lead"
    static let prompted = "notify.prompted"

    static let defaultClassLead = 30
    static let defaultExamLead = 30

    static let classLeadOptions = [5, 10, 15, 20, 30, 45, 60]
    static let examLeadOptions = [10, 15, 20, 30, 45, 60]

    static var classLeadMinutes: Int {
        UserDefaults.standard.object(forKey: classLead) as? Int ?? defaultClassLead
    }

    static var examLeadMinutes: Int {
        UserDefaults.standard.object(forKey: examLead) as? Int ?? defaultExamLead
    }

    static var classOn: Bool {
        UserDefaults.standard.bool(forKey: classEnabled)
    }

    static var examOn: Bool {
        UserDefaults.standard.bool(forKey: examEnabled)
    }

    static var hasPrompted: Bool {
        get { UserDefaults.standard.bool(forKey: prompted) }
        set { UserDefaults.standard.set(newValue, forKey: prompted) }
    }
}

/// 本地通知：系统自己排期，App 被完全杀掉也会到点弹。
/// 代价是内容在排期那一刻就固定了，所以每次拉到新课表/新考试都要重排一遍。
enum NotificationService {
    private static let prefixes = ["class-", "exam-"]
    /// 只排未来这么多天的，免得一学期的课把 64 条额度占满
    private static let daysAhead = 7
    private static let maxPending = 60

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 全部重排。关掉的类型传空数组即可。
    static func reschedule(
        occurrences: [CourseOccurrence],
        weekOneMonday: Date,
        exams: [ExamRecord],
        classLeadMinutes: Int,
        examLeadMinutes: Int,
        now: Date = Date()
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers())

        var planned: [(Date, UNNotificationRequest)] = []
        planned += classReminders(
            occurrences: occurrences,
            weekOneMonday: weekOneMonday,
            leadMinutes: classLeadMinutes,
            now: now
        )
        planned += examReminders(exams: exams, leadMinutes: examLeadMinutes, now: now)

        for (_, request) in planned.sorted(by: { $0.0 < $1.0 }).prefix(maxPending) {
            try? await center.add(request)
        }
    }

    /// 清掉本 App 排的所有课/考试提醒（退出登录时用）
    static func clearAll() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: pendingIdentifiers())
    }

    // MARK: - 上课提醒

    private static func classReminders(
        occurrences: [CourseOccurrence],
        weekOneMonday: Date,
        leadMinutes: Int,
        now: Date
    ) -> [(Date, UNNotificationRequest)] {
        let calendar = Calendar.current
        let monday = calendar.startOfDay(for: weekOneMonday)
        let limit = calendar.date(byAdding: .day, value: daysAhead, to: now) ?? now
        var result: [(Date, UNNotificationRequest)] = []

        for item in occurrences where !item.isPlaceholder && !item.isRemote {
            let startMinutes = PeriodSchedule.isJiaoSanEarly(room: item.room, period: item.period)
                ? 10 * 60 + 10
                : PeriodSchedule.startMinutes(item.period)
            for week in item.weeks {
                guard let day = calendar.date(
                    byAdding: .day,
                    value: (week - 1) * 7 + (item.day - 1),
                    to: monday
                ) else { continue }

                let dayStart = calendar.startOfDay(for: day)
                let fire = dayStart.addingTimeInterval(TimeInterval((startMinutes - leadMinutes) * 60))
                guard fire > now, fire <= limit else { continue }

                let content = UNMutableNotificationContent()
                content.title = "下一节课：\(item.name)"
                content.body = item.room.isEmpty ? "教室待定" : "教室 \(item.room)"
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                    repeats: false
                )
                let identifier = "class-\(item.courseKey)-\(week)-\(item.day)-\(item.period)"
                result.append((fire, UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)))
            }
        }
        return result
    }

    // MARK: - 考试提醒

    private static func examReminders(
        exams: [ExamRecord],
        leadMinutes: Int,
        now: Date
    ) -> [(Date, UNNotificationRequest)] {
        let calendar = Calendar.current
        var result: [(Date, UNNotificationRequest)] = []

        for exam in exams {
            guard let day = day(from: exam.dateKey) else { continue }
            let detail = [exam.timeWithoutDate,
                          exam.room.isEmpty ? nil : "考场 \(exam.room)",
                          exam.seat.isEmpty ? nil : "座位 \(exam.seat)"]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")

            // 前一天 21:00
            if let fire = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day),
               let eve = calendar.date(byAdding: .day, value: -1, to: fire),
               eve > now {
                result.append((eve, request(
                    id: "exam-\(exam.id)-eve",
                    title: "明天考试：\(exam.course)",
                    body: detail.isEmpty ? exam.name : detail,
                    fire: eve
                )))
            }

            // 当天 08:00
            if let fire = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day), fire > now {
                result.append((fire, request(
                    id: "exam-\(exam.id)-morning",
                    title: "今天考试：\(exam.course)",
                    body: detail.isEmpty ? exam.name : detail,
                    fire: fire
                )))
            }

            // 开考前 N 分钟
            if let start = startOfExam(exam.time, on: day) {
                let fire = start.addingTimeInterval(TimeInterval(-leadMinutes * 60))
                if fire > now {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    result.append((fire, request(
                        id: "exam-\(exam.id)-lead",
                        title: "快考试了：\(exam.course)",
                        body: "\(formatter.string(from: start)) 开考"
                            + (detail.isEmpty ? "" : " · \(detail)"),
                        fire: fire,
                        timeSensitive: true
                    )))
                }
            }
        }
        return result
    }

    // MARK: - 小工具

    private static func request(
        id: String,
        title: String,
        body: String,
        fire: Date,
        timeSensitive: Bool = false
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if timeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
            repeats: false
        )
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private static func pendingIdentifiers() -> [String] {
        var result: [String] = []
        let semaphore = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            result = requests
                .map(\.identifier)
                .filter { id in prefixes.contains { id.hasPrefix($0) } }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private static func day(from key: String) -> Date? {
        guard !key.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: key)
    }

    /// 从 "09:00-11:00" 这类文本里取出开考时间，日期用考试当天
    private static func startOfExam(_ text: String, on day: Date) -> Date? {
        guard let groups = text.regexGroups(#"(\d{1,2})\s*[:：]\s*(\d{2})"#).first,
              groups.count >= 2,
              let hour = Int(groups[0]), let minute = Int(groups[1]),
              hour < 24, minute < 60 else { return nil }
        let calendar = Calendar.current
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
