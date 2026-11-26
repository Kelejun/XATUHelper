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
        let isExam: Bool?
        let seat: String?
        let begins: Date
        let start: Date
        let end: Date

        init(slot: CourseActivitySlot, prefersDarkAppearance: Bool? = nil, timeOffset: TimeInterval = 0) {
            let lesson = slot.lesson
            name = lesson.name
            room = lesson.displayRoom
            previousRoom = slot.previousRoom
            colorIndex = lesson.colorIndex
            self.prefersDarkAppearance = prefersDarkAppearance
            preparationOnly = !slot.includesClass
            isExam = false
            seat = nil
            begins = (slot.visibleFrom >= lesson.start ? lesson.start : slot.begins).addingTimeInterval(timeOffset)
            start = lesson.start.addingTimeInterval(timeOffset)
            end = lesson.end.addingTimeInterval(timeOffset)
        }

        init(examSlot slot: ExamActivitySlot, prefersDarkAppearance: Bool? = nil, timeOffset: TimeInterval = 0) {
            let exam = slot.exam
            name = exam.name
            room = exam.displayRoom
            previousRoom = nil
            colorIndex = nil
            self.prefersDarkAppearance = prefersDarkAppearance
            preparationOnly = true
            isExam = true
            seat = exam.displaySeat
            begins = slot.begins.addingTimeInterval(timeOffset)
            start = exam.start.addingTimeInterval(timeOffset)
            end = exam.end.addingTimeInterval(timeOffset)
        }
    }
}
#endif
