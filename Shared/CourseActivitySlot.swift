import Foundation

/// The current or next course that can occupy the Dynamic Island.
struct CourseActivitySlot: Equatable {
    let lesson: WatchSnapshot.Lesson
    let begins: Date
    let visibleFrom: Date
    let previousRoom: String?
    let includesClass: Bool

    init?(snapshot: WatchSnapshot, at date: Date, after boundary: Date = .distantPast,
          beforeClass: Bool = true, duringClass: Bool = true) {
        let progress = WatchCourseProgress(snapshot: snapshot, at: date)
        guard let lesson = progress.lesson else { return nil }
        self.lesson = lesson
        includesClass = duringClass
        begins = beforeClass ? (progress.preparationInterval?.lowerBound ?? lesson.start) : lesson.start
        visibleFrom = max(begins, boundary)
        previousRoom = beforeClass ? progress.previous?.displayRoom : nil
    }

    static func upcoming(in snapshot: WatchSnapshot, at now: Date,
                         beforeClass: Bool = true, duringClass: Bool = true) -> [Self] {
        guard beforeClass || duringClass,
              let first = Self(snapshot: snapshot, at: now, beforeClass: beforeClass, duringClass: duringClass) else { return [] }
        // Reserve the following course too, so a short break can start with the phone locked.
        let next = Self(snapshot: snapshot, at: first.lesson.end, after: first.lesson.end,
                        beforeClass: beforeClass, duringClass: duringClass)
        return [first, next].compactMap { $0 }.filter {
            duringClass || ($0.visibleFrom < $0.lesson.start && now < $0.lesson.start)
        }
    }
}

/// An upcoming exam that can occupy the Dynamic Island before it starts.
struct ExamActivitySlot: Equatable {
    static let defaultLeadMinutes = 60

    let exam: WatchSnapshot.Exam
    let begins: Date
    let visibleFrom: Date

    var activityID: String { "exam-\(exam.id)" }

    init?(exam: WatchSnapshot.Exam, leadMinutes: Int = defaultLeadMinutes) {
        guard exam.knowsStartTime else { return nil }
        let lead = max(1, leadMinutes)
        self.exam = exam
        begins = exam.start.addingTimeInterval(-Double(lead * 60))
        visibleFrom = begins
    }

    static func upcoming(in snapshot: WatchSnapshot, at now: Date,
                         leadMinutes: Int = defaultLeadMinutes) -> [Self] {
        guard snapshot.loggedIn else { return [] }
        return snapshot.exams
            .filter { $0.knowsStartTime && $0.start > now }
            .sorted { $0.start < $1.start }
            .prefix(2)
            .compactMap { Self(exam: $0, leadMinutes: leadMinutes) }
    }
}

extension WatchSnapshot.Lesson {
    var displayRoom: String {
        let location = room.isEmpty ? fullRoom : room
        return location.isEmpty ? "教室待定" : location
    }
}
