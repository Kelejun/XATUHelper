import SwiftUI

private struct PreviewDataKey: EnvironmentKey {
    static let defaultValue: ReminderPreviewData? = nil
}

private extension EnvironmentValues {
    var reminderPreview: ReminderPreviewData? {
        get { self[PreviewDataKey.self] }
        set { self[PreviewDataKey.self] = newValue }
    }
}

private struct PreviewInputs: Equatable {
    let account: String
    let loggedIn: Bool
    let monday: Date
    let courses: [CourseOccurrence]
    let exams: [ExamRecord]
}

private struct ReminderPreviewProvider: ViewModifier {
    @EnvironmentObject private var app: AppState
    @State private var sampleIndex = UInt64.random(in: .min ... .max)
    @State private var data: ReminderPreviewData?

    func body(content: Content) -> some View {
        let hasLocalExamList = app.isDemoMode || app.hasExamContext(app.currentSemesterID)
        let exams = app.currentExams.isEmpty && hasLocalExamList ? app.exams : app.currentExams
        let inputs = PreviewInputs(account: app.studentID, loggedIn: app.isLoggedIn, monday: app.reminderMonday,
                                   courses: app.reminderOccurrences, exams: exams)
        content
            .environment(\.reminderPreview, data)
            .onChange(of: inputs, initial: true) { _, inputs in
                data = inputs.loggedIn ? ReminderPreviewData(snapshot: app.makeWatchSnapshot(), exams: inputs.exams,
                                                             fallbackCourses: inputs.courses, sampleIndex: sampleIndex) : nil
            }
    }
}

extension View {
    func withReminderPreviewData() -> some View { modifier(ReminderPreviewProvider()) }
}

private func clockText(_ minutes: Int) -> String {
    let time = (minutes % 1440 + 1440) % 1440
    return String(format: "%02d:%02d", time / 60, time % 60)
}

private struct NotificationAppIcon: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Icon Composer app icons aren't ordinary UIImage assets.
        Image("XATuneMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(scheme == .dark ? Color(red: 105 / 255, green: 180 / 255, blue: 1) : .white)
            .frame(width: 24, height: 24)
            .frame(width: 36, height: 36)
            .background(scheme == .dark ? Color(white: 0.1) : Color(red: 1 / 255, green: 89 / 255, blue: 218 / 255))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

struct NotificationSample: View {
    enum Trigger { case course(Int), eve(Int), morning(Int), examLead(Int) }
    let trigger: Trigger
    @Environment(\.reminderPreview) private var data
    @Environment(\.colorScheme) private var scheme

    private struct Sample {
        let time: String
        let timing: String
        let title: String
        let detail: String
        var simulated = false
    }

    private var sample: Sample? {
        if case .course(let lead) = trigger {
            guard let lesson = data?.before else { return nil }
            let room = lesson.fullRoom.isEmpty ? lesson.room : lesson.fullRoom
            return Sample(time: clockText(ReminderPreviewData.minutes(of: lesson.start) - lead),
                          timing: "课前 \(lead) 分钟", title: "下一节课：\(lesson.name)",
                          detail: room.isEmpty ? "教室待定" : "教室 \(room)")
        }
        guard let exam = data?.exam else { return nil }
        switch trigger {
        case .eve(let minutes):
            return Sample(time: clockText(minutes), timing: "考试前一天", title: "明天考试：\(exam.name)",
                          detail: exam.detail, simulated: exam.simulated)
        case .morning(let minutes):
            return Sample(time: clockText(minutes), timing: "当天早间", title: "今天考试：\(exam.name)",
                          detail: exam.detail, simulated: exam.simulated)
        case .examLead(let lead):
            return Sample(time: exam.startMinutes.map { clockText($0 - lead) } ?? "待定",
                          timing: "开考前 \(lead) 分钟", title: "快考试了：\(exam.name)",
                          detail: exam.leadDetail ?? exam.detail, simulated: exam.simulated)
        case .course: return nil
        }
    }

    var body: some View {
        if let sample {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sample.time).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text(sample.timing).font(.caption.weight(.medium))
                    Spacer(minLength: 3)
                    Text(sample.simulated ? "课程模拟" : "通知示例").font(.caption.weight(.medium))
                }
                .foregroundStyle(scheme == .dark ? Color(red: 0.69, green: 0.82, blue: 1) : Color(red: 0.16, green: 0.33, blue: 0.55))
                HStack(spacing: 11) {
                    NotificationAppIcon()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sample.title).font(.subheadline.weight(.semibold))
                        Text(sample.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
            }
            .padding(14)
            .background(scheme == .dark ? Color(red: 0.14, green: 0.20, blue: 0.31) : Color(red: 0.89, green: 0.94, blue: 1),
                        in: RoundedRectangle(cornerRadius: 18))
        } else {
            Text("暂无可预览的本地安排").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct CourseActivityPreview: View {
    enum Phase { case before(Int), between, during, exam(Int) }
    let phase: Phase
    @Environment(\.reminderPreview) private var data
    @Environment(\.colorScheme) private var scheme
    @State private var anchor = Date()

    private var courseSlot: CourseActivitySlot? {
        switch phase {
        case .before(let lead): data?.preparationSlot(leadMinutes: lead)
        case .between: data?.between
        case .during: data?.during
        case .exam: nil
        }
    }

    private var examSlot: ExamActivitySlot? {
        guard case .exam(let lead) = phase else { return nil }
        return data?.examActivitySlot(leadMinutes: lead)
    }

    private var emptyMessage: String {
        switch phase {
        case .between: "本地课表暂无课间安排"
        case .exam: "暂无可预览的本地安排"
        case .before, .during: "暂无可预览的本地课程"
        }
    }

    var body: some View {
        if let slot = courseSlot {
            let end = isDuring ? slot.lesson.end : slot.lesson.start
            let remaining = end.timeIntervalSince(slot.begins) / 2
            TimelineView(.periodic(from: anchor, by: remaining)) { tick in
                let offset = tick.date.addingTimeInterval(remaining).timeIntervalSince(end)
                let state = CourseActivityAttributes.ContentState(slot: slot, timeOffset: offset)
                CourseActivityCard(course: CoursePresentation(state: state, colorScheme: scheme, now: tick.date))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        } else if let slot = examSlot {
            let end = slot.exam.start
            let remaining = end.timeIntervalSince(slot.begins) / 2
            TimelineView(.periodic(from: anchor, by: remaining)) { tick in
                let offset = tick.date.addingTimeInterval(remaining).timeIntervalSince(end)
                let state = CourseActivityAttributes.ContentState(examSlot: slot, timeOffset: offset)
                CourseActivityCard(course: CoursePresentation(state: state, colorScheme: scheme, now: tick.date))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        } else {
            Text(emptyMessage)
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var isDuring: Bool {
        if case .during = phase { return true }
        return false
    }
}
