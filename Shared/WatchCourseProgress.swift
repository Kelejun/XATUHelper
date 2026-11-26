import Foundation

struct WatchCourseProgress {
    static let defaultPreparationMinutes = 30
    private static let breakWindowMinutes = 30

    private let date: Date
    private let preparationMinutes: Int
    let lesson: WatchSnapshot.Lesson?
    let previous: WatchSnapshot.Lesson?

    init(snapshot: WatchSnapshot, at date: Date, preparationMinutes: Int = defaultPreparationMinutes) {
        self.date = date
        self.preparationMinutes = max(1, preparationMinutes)
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
        let earliest = lesson.start.addingTimeInterval(-Double(Self.breakWindowMinutes * 60))
        let noon = calendar.startOfDay(for: lesson.start).addingTimeInterval(12 * 3600)
        previous = snapshot.lessons.lazy.filter {
            $0.end >= earliest && $0.end <= date &&
            calendar.isDate($0.start, inSameDayAs: lesson.start) &&
            (lesson.start < noon || $0.end > noon)
        }.max { $0.end < $1.end }
    }

    var preparationInterval: ClosedRange<Date>? {
        guard let lesson, date < lesson.start else { return nil }
        let start = previous?.end ?? lesson.start.addingTimeInterval(-Double(preparationMinutes * 60))
        return start...lesson.start
    }
}
