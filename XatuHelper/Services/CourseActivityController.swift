import ActivityKit
import Foundation

@MainActor
final class CourseActivityController {
    static let shared = CourseActivityController()
    static let beforeKey = "courseProgress.beforeClass"
    static let duringKey = "courseProgress.duringClass"
    static let beforeLeadKey = "courseProgress.beforeClassLeadMinutes"
    static let defaultBeforeLeadMinutes = CourseActivitySlot.defaultBeforeLeadMinutes
    static let beforeLeadOptions = [10, 15, 20, 30, 45, 60]
    static let beforeExamKey = "courseProgress.beforeExam"
    static let examLeadKey = "courseProgress.examLeadMinutes"
    static let defaultExamLeadMinutes = ExamActivitySlot.defaultLeadMinutes
    static let examLeadOptions = [15, 30, 45, 60, 90, 120]
    static let promptedKey = "courseProgress.prompted.2026-11-26"
    static let examPromptedKey = "courseProgress.examPrompted.2026-11-26"

    static var beforeLeadMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: beforeLeadKey)
        return value > 0 ? value : defaultBeforeLeadMinutes
    }

    static var examLeadMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: examLeadKey)
        return value > 0 ? value : defaultExamLeadMinutes
    }

    static func migratePreferences() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.object(forKey: "courseProgress.liveActivity") as? Bool else { return }
        for key in [beforeKey, duringKey] where defaults.object(forKey: key) == nil {
            defaults.set(legacy, forKey: key)
        }
        defaults.removeObject(forKey: "courseProgress.liveActivity")
    }
    private static let darkAppearanceKey = "courseProgress.prefersDarkAppearance"
    private typealias CourseActivity = Activity<CourseActivityAttributes>

    private var snapshot = WatchSnapshot.empty
    private var issued: [String: String] = [:]
    private var foreground = false
    private var needsRefresh = false
    private var worker: Task<Void, Never>?
    private var wakeup: Task<Void, Never>?

    func receive(_ snapshot: WatchSnapshot) {
        self.snapshot = snapshot
        refresh()
    }

    func setForeground(_ foreground: Bool) {
        self.foreground = foreground
        refresh()
    }

    func setDarkAppearance(_ dark: Bool) {
        // The Lock Screen's appearance can follow its wallpaper rather than the device setting.
        guard #available(iOS 26, *) else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.darkAppearanceKey) as? Bool != dark else { return }
        defaults.set(dark, forKey: Self.darkAppearanceKey)
        refresh()
    }

    func refresh() {
        needsRefresh = true
        guard worker == nil else { return }
        worker = Task {
            while needsRefresh {
                needsRefresh = false
                await reconcile()
            }
            worker = nil
        }
    }

    private struct ScheduledSlot {
        let id: String
        let visibleFrom: Date
        let start: Date
        let end: Date
        let alertTitle: String
        let alertBody: String
        let state: (Bool?) -> CourseActivityAttributes.ContentState

        init(_ slot: CourseActivitySlot) {
            id = slot.lesson.id
            visibleFrom = slot.visibleFrom
            start = slot.lesson.start
            end = slot.lesson.end
            alertTitle = "课程进度"
            alertBody = "\(slot.lesson.name) · \(slot.lesson.displayRoom)"
            state = { CourseActivityAttributes.ContentState(slot: slot, prefersDarkAppearance: $0) }
        }

        init(_ slot: ExamActivitySlot) {
            id = slot.activityID
            visibleFrom = slot.visibleFrom
            start = slot.exam.start
            end = slot.exam.end
            alertTitle = "考试提醒"
            alertBody = [slot.exam.name, slot.exam.displayRoom, slot.exam.displaySeat.map { "座位 \($0)" }]
                .compactMap { $0 }
                .joined(separator: " · ")
            state = { CourseActivityAttributes.ContentState(examSlot: slot, prefersDarkAppearance: $0) }
        }
    }

    private func reconcile() async {
        wakeup?.cancel()
        let now = Date()
        let defaults = UserDefaults.standard
        let before = defaults.bool(forKey: Self.beforeKey)
        let during = defaults.bool(forKey: Self.duringKey)
        let beforeExam = defaults.bool(forKey: Self.beforeExamKey)
        let enabled = (before || during || beforeExam) && ActivityAuthorizationInfo().areActivitiesEnabled
        var slots: [ScheduledSlot] = []
        if enabled && (before || during) {
            slots += CourseActivitySlot.upcoming(in: snapshot, at: now, beforeClass: before, duringClass: during,
                                                 beforeLeadMinutes: Self.beforeLeadMinutes)
                .map(ScheduledSlot.init)
        }
        if enabled && beforeExam {
            slots += ExamActivitySlot.upcoming(in: snapshot, at: now, leadMinutes: Self.examLeadMinutes)
                .map(ScheduledSlot.init)
        }
        let wanted = Set(slots.map { requestKey(account: snapshot.accountID, item: $0.id) })
        issued = issued.filter { wanted.contains($0.key) }
        var retained = Set<String>()
        for activity in CourseActivity.activities {
            let key = requestKey(account: activity.attributes.accountID, item: activity.attributes.lessonID)
            guard let slot = slots.first(where: { $0.id == activity.attributes.lessonID }),
                  activity.attributes.accountID == snapshot.accountID,
                  canKeep(activity, for: slot, now: now),
                  retained.insert(slot.id).inserted else {
                if issued[key] == activity.id { issued.removeValue(forKey: key) }
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            issued[key] = activity.id
            let content = content(for: slot, now: now)
            if activity.content.state != content.state || activity.content.staleDate != content.staleDate {
                await activity.update(content)
            }
        }
        guard foreground, !needsRefresh else { return }
        for slot in slots where !retained.contains(slot.id) {
            let key = requestKey(account: snapshot.accountID, item: slot.id)
            // Avoid reopening a dismissed card on every snapshot or foreground change.
            guard issued[key] == nil else { continue }
            issued[key] = request(slot, now: now)?.id
        }
        // ActivityKit renders the timers. Wake the foreground app only at a schedule boundary.
        var boundaries = slots.flatMap { [$0.visibleFrom, $0.start, $0.end] }
        guard enabled else { return }
        if before || during {
            if let end = snapshot.currentLesson(at: now)?.end { boundaries.append(end) }
            if let start = snapshot.nextLesson(at: now)?.start { boundaries.append(start) }
        }
        if let next = boundaries.filter({ $0 > now }).min() {
            wakeup = Task {
                do { try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow))) }
                catch { return }
                refresh()
            }
        }
    }

    private func requestKey(account: String, item: String) -> String {
        "\(account)|\(item)"
    }

    private func canKeep(_ activity: CourseActivity, for slot: ScheduledSlot, now: Date) -> Bool {
        if #available(iOS 26, *), activity.activityState == .pending {
            return activity.attributes.scheduledStart == slot.visibleFrom
        }
        return slot.visibleFrom <= now && (activity.activityState == .active || activity.activityState == .stale)
    }

    private func content(for slot: ScheduledSlot, now: Date) -> ActivityContent<CourseActivityAttributes.ContentState> {
        let darkAppearance = UserDefaults.standard.object(forKey: Self.darkAppearanceKey) as? Bool
        let state = slot.state(darkAppearance)
        // A stale preparation presentation transitions at start even if iOS suspended the app.
        let boundary = state.begins < state.start && now < state.start ? state.start : state.end
        return ActivityContent(state: state, staleDate: boundary, relevanceScore: slot.start.timeIntervalSince1970)
    }

    private func request(_ slot: ScheduledSlot, now: Date) -> CourseActivity? {
        let future = slot.visibleFrom > now
        let attributes = CourseActivityAttributes(accountID: snapshot.accountID, lessonID: slot.id,
                                                  scheduledStart: future ? slot.visibleFrom : nil)
        let content = content(for: slot, now: now)
        do {
            if future {
                if #available(iOS 26, *) {
                    let alert = AlertConfiguration(title: LocalizedStringResource(stringLiteral: slot.alertTitle),
                                                   body: LocalizedStringResource(stringLiteral: slot.alertBody),
                                                   sound: .default)
                    return try CourseActivity.request(attributes: attributes, content: content, style: .standard,
                                                      alertConfiguration: alert, start: slot.visibleFrom)
                }
            } else {
                return try CourseActivity.request(attributes: attributes, content: content)
            }
        } catch {
            NSLog("Course Live Activity: %@", error.localizedDescription)
        }
        return nil
    }
}
