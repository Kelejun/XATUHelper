import ActivityKit
import SwiftUI
import WidgetKit

struct CourseLiveActivityWidget: Widget {
    private let timetable = URL(string: "xatuhelper://timetable")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            let course = CoursePresentation(context)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(course.state.name).font(.headline).lineLimit(2)
                    Spacer(minLength: 8)
                    course.countdown.font(.headline)
                }
                course.details
                course.progress
            }
            .padding()
            .privacySensitive()
            .widgetURL(timetable)
        } dynamicIsland: { context in
            let course = CoursePresentation(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(course.state.name).font(.headline).lineLimit(1).privacySensitive()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    course.countdown.font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        course.details
                        course.progress
                    }.privacySensitive()
                }
            } compactLeading: {
                ViewThatFits(in: .horizontal) {
                    Text(course.state.room).font(.caption.weight(.semibold)).fixedSize()
                    Image(systemName: course.symbol)
                }
                .frame(maxWidth: 52)
                .foregroundStyle(course.tint)
                .privacySensitive()
                .accessibilityLabel(Text(course.state.room))
            } compactTrailing: {
                course.timer.font(.caption.weight(.semibold)).frame(width: 49)
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
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .accessibilityLabel(label)
                .accessibilityValue(Text(timerInterval: interval, countsDown: true))
        }
    }

    var countdown: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption)
            if !finished { timer.frame(width: 62, alignment: .trailing) }
        }
        .foregroundStyle(tint)
    }

    var details: some View {
        HStack(spacing: 5) {
            if preparing, let from = state.previousRoom {
                Text(from)
                Image(systemName: "arrow.right").font(.caption2)
            } else {
                Image(systemName: "mappin")
            }
            Text(state.room).fontWeight(.semibold)
            Spacer(minLength: 6)
            Text(WatchSnapshot.clock(state.start) + "–" + WatchSnapshot.clock(state.end))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    var progress: some View {
        ProgressView(timerInterval: interval, countsDown: countsDown) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(tint)
        .accessibilityLabel(label)
    }
}
