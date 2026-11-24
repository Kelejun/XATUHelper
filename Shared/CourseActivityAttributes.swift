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
        let prefersDarkAppearance: Bool?
        let preparationOnly: Bool?
        let begins: Date
        let start: Date
        let end: Date

        init(slot: CourseActivitySlot, prefersDarkAppearance: Bool? = nil) {
            let lesson = slot.lesson
            name = lesson.name
            room = lesson.displayRoom
            previousRoom = slot.previousRoom
            colorIndex = lesson.colorIndex
            self.prefersDarkAppearance = prefersDarkAppearance
            preparationOnly = !slot.includesClass
            begins = slot.visibleFrom >= lesson.start ? lesson.start : slot.begins
            start = lesson.start
            end = lesson.end
        }
    }
}
#endif
