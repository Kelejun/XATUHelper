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
    let examActivity: WatchSnapshot.Exam?

    func preparationSlot(leadMinutes: Int = CourseActivitySlot.defaultBeforeLeadMinutes) -> CourseActivitySlot? {
        guard let lesson = preparation?.lesson else { return nil }
        var single = WatchSnapshot.empty
        single.loggedIn = true
        single.lessons = [lesson]
        return CourseActivitySlot(snapshot: single, at: lesson.start.addingTimeInterval(-1),
                                  beforeLeadMinutes: leadMinutes)
    }

    func examActivitySlot(leadMinutes: Int = ExamActivitySlot.defaultLeadMinutes) -> ExamActivitySlot? {
        examActivity.flatMap { ExamActivitySlot(exam: $0, leadMinutes: leadMinutes) }
    }

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
        let timedScheduled = snapshot.upcomingExams(at: now).first(where: \.knowsStartTime)
            ?? snapshot.exams.filter(\.knowsStartTime).max { $0.start < $1.start }
        if let record = exams.first(where: { $0.id == scheduled?.id }) ?? exams.first {
            exam = Exam(name: record.course, detail: record.reminderBody, startMinutes: record.startMinutes,
                        simulated: false, leadDetail: record.leadReminderBody)
            if let timedScheduled {
                examActivity = timedScheduled
            } else {
                let start = record.startMinutes != nil ? (record.startDate() ?? now.addingTimeInterval(3600)) : now.addingTimeInterval(3600)
                let end = record.endMinutes != nil ? (record.endDate() ?? start.addingTimeInterval(7200)) : start.addingTimeInterval(7200)
                examActivity = WatchSnapshot.Exam(id: record.id, name: record.course, start: start, end: end,
                                                  time: record.timeWithoutDate, room: record.room, seat: record.seat,
                                                  note: record.note, hasStartTime: true)
            }
        } else if !lessons.isEmpty {
            let lesson = lessons[Int(sampleIndex % UInt64(lessons.count))]
            exam = Exam(name: lesson.name, detail: "课程教室：\(lesson.displayRoom)",
                        startMinutes: Self.minutes(of: lesson.start), simulated: true)
            examActivity = WatchSnapshot.Exam(id: "preview-\(lesson.id)", name: lesson.name,
                                              start: lesson.start, end: lesson.end,
                                              time: "", room: lesson.displayRoom, seat: "", note: "",
                                              hasStartTime: true)
        } else {
            let courses = fallbackCourses.filter { !$0.isPlaceholder && !$0.name.isEmpty }
            if courses.isEmpty {
                exam = nil
                examActivity = nil
            } else {
                let course = courses[Int(sampleIndex % UInt64(courses.count))]
                exam = Exam(name: course.name, detail: "考试安排待定", startMinutes: nil, simulated: true)
                let start = now.addingTimeInterval(3600)
                examActivity = WatchSnapshot.Exam(id: "preview-\(course.courseKey)", name: course.name,
                                                  start: start, end: start.addingTimeInterval(7200),
                                                  time: "", room: "", seat: "", note: "", hasStartTime: true)
            }
        }
    }

    static func minutes(of date: Date) -> Int {
        let calendar = WatchSnapshot.campusCalendar
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
