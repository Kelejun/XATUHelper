import Foundation

struct ReminderPreviewData {
    struct Exam {
        let name: String
        let detail: String
        let startMinutes: Int?
        let simulated: Bool
        var leadDetail: String? = nil
    }
    let before: WatchSnapshot.Lesson?
    let preparation: CourseActivitySlot?
    let between: CourseActivitySlot?
    let during: CourseActivitySlot?
    let exam: Exam?

    init(snapshot: WatchSnapshot, exams: [ExamRecord], fallbackCourses: [CourseOccurrence],
         sampleIndex: UInt64, now: Date = Date()) {
        let lessons = snapshot.lessons
        before = snapshot.nextLesson(at: now) ?? snapshot.currentLesson(at: now) ?? lessons.last
        let ordered = lessons.sorted { $0.start < $1.start }
        var preparationSlots = [CourseActivitySlot]()
        var previous: WatchSnapshot.Lesson?
        for lesson in ordered {
            guard lesson.end > lesson.start else { continue }
            defer { if lesson.end > (previous?.end ?? .distantPast) { previous = lesson } }
            var pair = WatchSnapshot.empty
            pair.loggedIn = snapshot.loggedIn
            pair.lessons = [previous, lesson].compactMap { $0 }
            if let slot = CourseActivitySlot(snapshot: pair, at: lesson.start.addingTimeInterval(-1)),
               slot.lesson.id == lesson.id, slot.begins < lesson.start {
                preparationSlots.append(slot)
            }
        }
        func example(betweenClasses: Bool) -> CourseActivitySlot? {
            let matches = preparationSlots.filter { ($0.previousRoom != nil) == betweenClasses }
            return matches.first { $0.lesson.start > now } ?? matches.last
        }
        preparation = example(betweenClasses: false)
        between = example(betweenClasses: true)
        if let lesson = snapshot.currentLesson(at: now) ?? before, lesson.end > lesson.start {
            during = CourseActivitySlot(snapshot: snapshot, at: lesson.start, beforeClass: false)
        } else {
            during = nil
        }

        let scheduled = snapshot.upcomingExams(at: now).first ?? snapshot.exams.max { $0.start < $1.start }
        if let record = exams.first(where: { $0.id == scheduled?.id }) ?? exams.first {
            exam = Exam(name: record.course, detail: record.reminderBody, startMinutes: record.startMinutes,
                        simulated: false, leadDetail: record.leadReminderBody)
        } else if !lessons.isEmpty {
            let lesson = lessons[Int(sampleIndex % UInt64(lessons.count))]
            exam = Exam(name: lesson.name, detail: "课程教室：\(lesson.displayRoom)",
                        startMinutes: Self.minutes(of: lesson.start), simulated: true)
        } else {
            let courses = fallbackCourses.filter { !$0.isPlaceholder && !$0.name.isEmpty }
            if courses.isEmpty { exam = nil }
            else {
                let course = courses[Int(sampleIndex % UInt64(courses.count))]
                exam = Exam(name: course.name, detail: "考试安排待定", startMinutes: nil, simulated: true)
            }
        }
    }

    static func minutes(of date: Date) -> Int {
        let calendar = WatchSnapshot.campusCalendar
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
