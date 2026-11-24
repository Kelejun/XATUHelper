import Foundation

struct ReminderPreviewData {
    struct Exam {
        let name: String
        let detail: String
        let startMinutes: Int?
        let simulated: Bool
    }
    struct CourseBreak {
        let next: WatchSnapshot.Lesson
        let previous: WatchSnapshot.Lesson
        var minutes: Int { Int(next.start.timeIntervalSince(previous.end) / 60) }
    }

    let before: WatchSnapshot.Lesson?
    let during: WatchSnapshot.Lesson?
    let between: CourseBreak?
    let exam: Exam?

    init(snapshot: WatchSnapshot, exams: [ExamRecord], fallbackCourses: [CourseOccurrence],
         sampleIndex: UInt64, now: Date = Date()) {
        let lessons = snapshot.lessons
        before = snapshot.nextLesson(at: now) ?? snapshot.currentLesson(at: now) ?? lessons.last
        during = snapshot.currentLesson(at: now) ?? before
        let calendar = WatchSnapshot.campusCalendar
        let breaks = zip(lessons, lessons.dropFirst()).compactMap { previous, next -> CourseBreak? in
            let gap = next.start.timeIntervalSince(previous.end)
            guard gap > 0, gap <= 30 * 60,
                  calendar.isDate(previous.start, inSameDayAs: next.start) else { return nil }
            let noon = calendar.startOfDay(for: next.start).addingTimeInterval(12 * 3600)
            guard next.start < noon || previous.end > noon else { return nil }
            return CourseBreak(next: next, previous: previous)
        }
        between = breaks.first { $0.next.start > now } ?? breaks.last

        let scheduled = snapshot.upcomingExams(at: now).first ?? snapshot.exams.max { $0.start < $1.start }
        if let record = exams.first(where: { $0.id == scheduled?.id }) ?? exams.first {
            let details = [record.timeWithoutDate, record.room.isEmpty ? "" : "考场 \(record.room)",
                           record.seat.isEmpty ? "" : "座位 \(record.seat)"].filter { !$0.isEmpty }
            exam = Exam(name: record.course.isEmpty ? record.name : record.course,
                        detail: details.isEmpty ? "考试信息待定" : details.joined(separator: " · "),
                        startMinutes: record.startMinutes, simulated: false)
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
