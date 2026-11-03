import Foundation

@main
struct ElectricityRefreshPolicyTests {
    static func main() {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            assertions += 1
        }
        let formatter = ISO8601DateFormatter()
        func date(_ text: String) -> Date { formatter.date(from: text)! }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let yesterday = date("2026-11-02T22:00:00+08:00")
        let midnight = date("2026-11-03T00:00:00+08:00")
        let start = date("2026-11-03T00:01:00+08:00")
        let morning = date("2026-11-03T08:00:00+08:00")
        let tomorrow = date("2026-11-04T00:01:00+08:00")
        func next(_ now: Date, _ checked: Date? = nil, _ hasBalance: Bool = false,
                  _ attempt: Date? = nil, _ waiting: Bool = false) -> Date? {
            ElectricityRefreshPolicy.nextRequestDate(now: now, checkedAt: checked,
                hasBalance: hasBalance, lastAttempt: attempt, awaitingForeground: waiting, calendar: calendar)
        }
        check(next(midnight) == start, "Before 00:01, wait until 00:01")
        check(next(start) == start, "At 00:01, today is eligible")
        check(next(morning) == morning, "Missed 00:01 may run later today")
        check(next(morning, morning, true) == tomorrow, "Foreground success skips today's background request")
        check(next(morning, yesterday, true) == morning, "Yesterday's balance is stale")
        check(next(morning, morning, false) == morning, "Missing balance is not a successful refresh")
        check(next(morning, nil, false, start) == tomorrow, "One background attempt per day")
        check(next(morning, nil, false, yesterday) == morning, "Previous day's attempt allows today")
        check(next(morning, nil, false, start, true) == nil, "Failure stops all background requests")
        check(next(tomorrow, nil, false, start, true) == nil, "Failure stays paused across days until foreground success")
        check(next(tomorrow, morning, true, start, false) == tomorrow, "Foreground recovery re-enables background refresh")

        for now in [midnight, start, morning] {
            for checked in [nil, yesterday, morning] as [Date?] {
                for balance in [false, true] {
                    for attempt in [nil, yesterday, start] as [Date?] {
                        for waiting in [false, true] {
                            let eligible = ElectricityRefreshPolicy.canAttempt(now: now, checkedAt: checked,
                                hasBalance: balance, lastAttempt: attempt, awaitingForeground: waiting, calendar: calendar)
                            let fresh = balance && checked == morning
                            let expected = now >= start && !fresh && attempt != start && !waiting
                            check(eligible == expected, "Daily eligibility matrix")
                        }
                    }
                }
            }
        }
        // Calendar arithmetic must preserve 00:01 over DST, rather than add 24 hours.
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstMorning = date("2026-11-01T08:00:00-08:00")
        check(next(dstMorning, dstMorning, true) == date("2026-11-02T00:01:00-08:00"), "DST fall transition")
        let beforeSpring = date("2026-03-08T00:01:00-08:00")
        check(next(beforeSpring, beforeSpring, true) == date("2026-03-09T00:01:00-07:00"), "DST spring transition")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let yearEnd = date("2026-12-31T23:00:00+08:00")
        check(next(yearEnd, yearEnd, true) == date("2027-01-01T00:01:00+08:00"), "Year boundary")

        let defaults = UserDefaults.standard
        let keys = [ElectricityRefreshSettings.automaticKey, ElectricityRefreshSettings.backgroundKey,
                    ElectricityRefreshSettings.exitReminderKey, ElectricityRefreshSettings.lastAttemptKey,
                    ElectricityRefreshSettings.awaitingForegroundKey]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        check(ElectricityRefreshSettings.automaticEnabled, "Automatic refresh defaults on")
        check(!ElectricityRefreshSettings.backgroundEnabled, "Background refresh defaults off")
        check(!ElectricityRefreshSettings.exitReminderEnabled, "Reminder defaults off")
        for automatic in [false, true] {
            for background in [false, true] {
                for reminder in [false, true] {
                    defaults.set(automatic, forKey: ElectricityRefreshSettings.automaticKey)
                    defaults.set(background, forKey: ElectricityRefreshSettings.backgroundKey)
                    defaults.set(reminder, forKey: ElectricityRefreshSettings.exitReminderKey)
                    check(ElectricityRefreshSettings.backgroundEnabled == (automatic && background), "Nested background switch")
                    check(ElectricityRefreshSettings.exitReminderEnabled == (automatic && background && reminder), "Nested reminder switch")
                    check(ElectricityRefreshSource.manual.isAllowed, "Manual refresh always remains available")
                    check(ElectricityRefreshSource.automatic.isAllowed == automatic, "Foreground automatic gate")
                    check(ElectricityRefreshSource.background.isAllowed == (automatic && background), "Background automatic gate")
                }
            }
        }
        ElectricityRefreshSettings.lastBackgroundAttempt = morning
        ElectricityRefreshSettings.awaitingForeground = true
        check(ElectricityRefreshSettings.lastBackgroundAttempt == morning, "Attempt persists before network request")
        check(ElectricityRefreshSettings.awaitingForeground, "Failure/cancellation state persists")
        ElectricityRefreshSettings.resetAttempts()
        check(ElectricityRefreshSettings.lastBackgroundAttempt == nil && !ElectricityRefreshSettings.awaitingForeground,
              "Logout/dorm change reset attempt state")

        let first = ElectricityRecord(day: "2026-11-03", balance: 42)
        let second = ElectricityRecord(day: "2026-11-03", balance: 41)
        let records = ElectricityHistoryStore.upserting(second, into: [first])
        check(records.count == 1 && records[0].balance == 41, "Only one saved balance record per day")
        print("PASS: \(assertions) electricity refresh policy checks")
    }
}
