import Foundation

/// The current or next course that can occupy the Dynamic Island.
struct CourseActivitySlot: Equatable {
    let lesson: WatchSnapshot.Lesson
    let begins: Date
    let visibleFrom: Date
    let previousRoom: String?

    init?(snapshot: WatchSnapshot, at date: Date, after boundary: Date = .distantPast) {
        let progress = WatchCourseProgress(snapshot: snapshot, at: date)
        guard let lesson = progress.lesson else { return nil }
        self.lesson = lesson
        begins = progress.preparationInterval?.lowerBound ?? lesson.start
        visibleFrom = max(begins, boundary)
        previousRoom = progress.previous?.displayRoom
    }

    static func upcoming(in snapshot: WatchSnapshot, at now: Date) -> [Self] {
        guard let first = Self(snapshot: snapshot, at: now) else { return [] }
        // Reserve the following course too, so a short break can start with the phone locked.
        guard let next = Self(snapshot: snapshot, at: first.lesson.end, after: first.lesson.end) else {
            return [first]
        }
        return [first, next]
    }
}

extension WatchSnapshot.Lesson {
    var displayRoom: String {
        let location = room.isEmpty ? fullRoom : room
        return location.isEmpty ? "教室待定" : location
    }
}
