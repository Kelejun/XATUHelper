import Foundation

/// Built only when source occurrences change, never while the pager is scrolling.
struct TimetableIndex {
    let occurrences: [Int: [CourseOccurrence]]
    let blocks: [Int: [CourseBlock]]

    init(_ source: [CourseOccurrence]) {
        var weeks: [Int: [CourseOccurrence]] = [:]
        for occurrence in source {
            for week in Set(occurrence.weeks) {
                weeks[week, default: []].append(occurrence)
            }
        }
        occurrences = weeks
        blocks = weeks.mapValues { $0.courseBlocks() }
    }
}
