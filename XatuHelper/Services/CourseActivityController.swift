import ActivityKit
import Foundation

@MainActor
final class CourseActivityController {
    static let shared = CourseActivityController()
    static let enabledKey = "courseProgress.liveActivity"
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

    private func reconcile() async {
        wakeup?.cancel()
        let now = Date()
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
            && ActivityAuthorizationInfo().areActivitiesEnabled
        let slots = enabled ? CourseActivitySlot.upcoming(in: snapshot, at: now) : []
        let wanted = Set(slots.map { requestKey(account: snapshot.accountID, lesson: $0.lesson.id) })
        issued = issued.filter { wanted.contains($0.key) }
        var retained = Set<String>()
        for activity in CourseActivity.activities {
            let key = requestKey(account: activity.attributes.accountID, lesson: activity.attributes.lessonID)
            guard let slot = slots.first(where: { $0.lesson.id == activity.attributes.lessonID }),
                  activity.attributes.accountID == snapshot.accountID,
                  canKeep(activity, for: slot, now: now),
                  retained.insert(slot.lesson.id).inserted else {
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
        for slot in slots where !retained.contains(slot.lesson.id) {
            let key = requestKey(account: snapshot.accountID, lesson: slot.lesson.id)
            // Avoid reopening a dismissed card on every snapshot or foreground change.
            guard issued[key] == nil else { continue }
            issued[key] = request(slot, now: now)?.id
        }
        // ActivityKit renders the timers. Wake the foreground app only at a course boundary.
        let boundaries = slots.flatMap { [$0.visibleFrom, $0.lesson.start, $0.lesson.end] }
        guard enabled else { return }
        let nextStart = snapshot.nextLesson(at: now)?.start ?? .distantFuture
        if let next = boundaries.filter({ $0 > now }).min() {
            wakeup = Task {
                do { try await Task.sleep(for: .seconds(max(0, min(next, nextStart).timeIntervalSinceNow))) }
                catch { return }
                refresh()
            }
        }
    }

    private func requestKey(account: String, lesson: String) -> String {
        "\(account)|\(lesson)"
    }

    private func canKeep(_ activity: CourseActivity, for slot: CourseActivitySlot, now: Date) -> Bool {
        if #available(iOS 26, *), activity.activityState == .pending {
            return activity.attributes.scheduledStart == slot.visibleFrom
        }
        return slot.visibleFrom <= now && (activity.activityState == .active || activity.activityState == .stale)
    }

    private func content(for slot: CourseActivitySlot, now: Date) -> ActivityContent<CourseActivityAttributes.ContentState> {
        let darkAppearance = UserDefaults.standard.object(forKey: Self.darkAppearanceKey) as? Bool
        let state = CourseActivityAttributes.ContentState(slot: slot, prefersDarkAppearance: darkAppearance)
        // A stale preparation presentation renders the class timer even if iOS suspended the app.
        let boundary = state.begins < state.start && now < state.start ? state.start : state.end
        return ActivityContent(state: state, staleDate: boundary, relevanceScore: slot.lesson.start.timeIntervalSince1970)
    }

    private func request(_ slot: CourseActivitySlot, now: Date) -> CourseActivity? {
        let future = slot.visibleFrom > now
        let attributes = CourseActivityAttributes(accountID: snapshot.accountID, lessonID: slot.lesson.id,
                                                  scheduledStart: future ? slot.visibleFrom : nil)
        let content = content(for: slot, now: now)
        do {
            if future {
                if #available(iOS 26, *) {
                    let alert = AlertConfiguration(title: "课程进度", body: "\(slot.lesson.name) · \(slot.lesson.displayRoom)", sound: .default)
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
