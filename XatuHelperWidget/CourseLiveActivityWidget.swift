import ActivityKit
import SwiftUI
import WidgetKit

struct CourseLiveActivityWidget: Widget {
    private let timetable = URL(string: "xatuhelper://timetable")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            CourseActivityCard(course: CoursePresentation(context))
                .padding(14)
                .activityBackgroundTint(CourseActivityCard.background)
                .widgetURL(timetable)
        } dynamicIsland: { context in
            let course = CoursePresentation(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    CourseActivityCard(course: course)
                        .padding(10)
                        .background(CourseActivityCard.background, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 5)
                        .padding(.bottom, 3)
                }
            } compactLeading: {
                ViewThatFits(in: .horizontal) {
                    Text(course.state.room).fixedSize()
                    Image(systemName: course.symbol)
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: 47)
                .padding(.leading, 4)
                .foregroundStyle(course.tint)
                .privacySensitive()
                .accessibilityLabel(Text(course.state.room))
            } compactTrailing: {
                course.timer
                    .font(.caption.weight(.semibold))
                    .frame(width: 49)
                    .accessibilityLabel(course.label)
                    .accessibilityValue(course.finished ? Text("") : Text(timerInterval: course.interval, countsDown: true))
            } minimal: {
                Image(systemName: course.symbol)
                    .foregroundStyle(course.tint)
                    .accessibilityLabel(course.label)
            }
            .keylineTint(course.tint)
            .widgetURL(timetable)
        }
    }
}

private struct CourseActivityCard: View {
    static let background = Color(white: 0.17)
    let course: CoursePresentation
    @ScaledMetric(relativeTo: .caption) private var preparationTimerWidth = 47.0

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(course.state.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Group {
                    if course.preparing {
                        if #available(iOS 18, *) {
                            Text(.currentDate, format: .offset(to: course.state.start, allowedFields: [.minute], sign: .never)
                                .locale(Locale(identifier: "zh_CN")))
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .frame(width: preparationTimerWidth)
                        } else {
                            course.timer.frame(width: preparationTimerWidth)
                        }
                    } else {
                        Text(course.state.room)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(course.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(course.tint.opacity(0.16), in: Capsule())
            }
            HStack(spacing: 3) {
                if course.preparing {
                    if let previous = course.state.previousRoom {
                        Text(previous)
                    }
                    Spacer(minLength: 6)
                    Text(course.state.room).foregroundStyle(course.tint)
                } else {
                    Text(course.label)
                    if !course.finished {
                        course.timer.frame(width: 58, alignment: .leading)
                            .foregroundStyle(course.tint)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.68))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            course.progress
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }
}

private struct CoursePresentation {
    let state: CourseActivityAttributes.ContentState
    let preparing: Bool
    let finished: Bool

    init(_ context: ActivityViewContext<CourseActivityAttributes>) {
        state = context.state
        let now = Date()
        let hasPreparation = state.begins < state.start
        preparing = hasPreparation && !context.isStale && now < state.start
        finished = now >= state.end || (!hasPreparation && context.isStale)
    }

    var label: String { finished ? "已下课" : preparing ? "距上课" : "距下课" }
    var symbol: String { finished ? "checkmark" : preparing ? "figure.walk" : "book.fill" }
    var tint: Color { CampusCourseColors.color(index: state.colorIndex) }
    var interval: ClosedRange<Date> { preparing ? state.begins...state.start : state.start...state.end }
    var countsDown: Bool { preparing && state.previousRoom == nil }

    @ViewBuilder var timer: some View {
        if finished {
            Text("下课")
        } else {
            Text(timerInterval: interval, countsDown: true, showsHours: false)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    var progress: some View {
        ProgressView(timerInterval: interval, countsDown: countsDown) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(tint)
        .frame(height: 4)
        .background(tint.opacity(0.3), in: Capsule())
        .clipShape(Capsule())
        .accessibilityLabel(preparing ? "课前进度" : "课程进度")
    }
}
