import Foundation

struct WatchCourseProgress {
    static let preparationMinutes = 30

    var date: Date
    let loggedIn: Bool
    let lesson: WatchSnapshot.Lesson?
    let previous: WatchSnapshot.Lesson?

    init(snapshot: WatchSnapshot, at date: Date) {
        self.date = date
        loggedIn = snapshot.loggedIn
        if let current = snapshot.currentLesson(at: date) {
            lesson = current
            previous = nil
            return
        }
        lesson = snapshot.nextLesson(at: date)
        guard let lesson else {
            previous = nil
            return
        }
        let calendar = WatchSnapshot.campusCalendar
        let earliest = lesson.start.addingTimeInterval(-Double(Self.preparationMinutes * 60))
        let noon = calendar.startOfDay(for: lesson.start).addingTimeInterval(12 * 3600)
        previous = snapshot.lessons.lazy.filter {
            $0.end >= earliest && $0.end <= date &&
            calendar.isDate($0.start, inSameDayAs: lesson.start) &&
            (lesson.start < noon || $0.end > noon)
        }.max { $0.end < $1.end }
    }

    var preparationInterval: ClosedRange<Date>? {
        guard let lesson, date < lesson.start else { return nil }
        let start = previous?.end ?? lesson.start.addingTimeInterval(-Double(Self.preparationMinutes * 60))
        return start...lesson.start
    }

    var minutesUntilClass: Int? {
        guard let interval = preparationInterval, interval.contains(date) else { return nil }
        return Int(ceil(interval.upperBound.timeIntervalSince(date) / 60))
    }

    static func timeline(snapshot: WatchSnapshot, from now: Date, horizon: TimeInterval = 48 * 3600) -> [Self] {
        let limit = now.addingTimeInterval(horizon)
        let transitions = [now] + snapshot.timelineDates(after: now, horizon: horizon)
        var entries: [Self] = []
        for (index, date) in transitions.enumerated() {
            var entry = Self(snapshot: snapshot, at: date)
            entries.append(entry)
            guard let interval = entry.preparationInterval else { continue }
            let nextTransition = transitions.dropFirst(index + 1).first
            for minute in (1...preparationMinutes).reversed() {
                let tick = interval.upperBound.addingTimeInterval(-Double(minute * 60))
                guard tick > date, tick >= interval.lowerBound, tick <= limit,
                      nextTransition.map({ tick < $0 }) ?? true else { continue }
                entry.date = tick
                entries.append(entry)
            }
        }
        return entries
    }
}
