#if os(iOS)
import ActivityKit
import Foundation

struct CourseActivityAttributes: ActivityAttributes, Equatable {
    let accountID: String
    let lessonID: String
    let scheduledStart: Date?

    struct ContentState: Codable, Hashable {
        let name: String
        let room: String
        let previousRoom: String?
        let colorIndex: Int?
        let begins: Date
        let start: Date
        let end: Date

        init(slot: CourseActivitySlot) {
            let lesson = slot.lesson
            name = lesson.name
            room = lesson.displayRoom
            previousRoom = slot.previousRoom
            colorIndex = lesson.colorIndex
            begins = slot.visibleFrom >= lesson.start ? lesson.start : slot.begins
            start = lesson.start
            end = lesson.end
        }
    }
}
#endif
