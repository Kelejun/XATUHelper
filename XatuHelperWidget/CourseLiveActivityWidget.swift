import ActivityKit
import SwiftUI
import WidgetKit

struct CourseLiveActivityWidget: Widget {
    private let timetable = URL(string: "xatuhelper://timetable")

    var body: some WidgetConfiguration {
        if #available(iOS 18, *) {
            return configuration.supplementalActivityFamilies([.small])
        } else {
            return configuration
        }
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            Group {
                if #available(iOS 18, *) {
                    CourseActivityContent(context: context)
                } else {
                    CourseLockScreen(context: context)
                }
            }
            .widgetURL(timetable)
        } dynamicIsland: { context in
            let course = CoursePresentation(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    course.status
                        .modifier(CourseExpandedHeaderAlignment())
                        .padding(.leading, 5)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    course.timer(width: 55, font: .headline)
                        .modifier(CourseExpandedHeaderAlignment())
                        .padding(.trailing, 5)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 11) {
                        CourseDetails(course: course, titleFont: .title3)
                        CourseProgressFooter(course: course, height: 5)
                    }
                    .padding(.horizontal, 7)
                    .padding(.top, 11)
                    .padding(.bottom, 8)
                }
            } compactLeading: {
                let room = Text(course.state.room).font(.system(size: 11, weight: .semibold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) {
                        course.mark.font(.system(size: 10, weight: .semibold))
                        room
                    }
                    .fixedSize()
                    room
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.head)
                }
                .frame(maxWidth: 59, alignment: .leading)
                .padding(.leading, 3)
                .foregroundStyle(course.tint)
                .privacySensitive()
                .accessibilityLabel(Text("\(course.phase)，\(course.state.room)"))
            } compactTrailing: {
                CourseCompactTimer(course: course)
                    .padding(.trailing, 3)
            } minimal: {
                CourseActivityEmblem(course: course)
            }
            .keylineTint(course.tint)
            .widgetURL(timetable)
        }
    }
}

@available(iOS 18, *)
private struct CourseActivityContent: View {
    let context: ActivityViewContext<CourseActivityAttributes>
    @Environment(\.activityFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        if family == .small {
            CourseWatchActivityView(course: CoursePresentation(context, colorScheme: luminanceReduced ? .dark : colorScheme))
        } else {
            CourseLockScreen(context: context)
        }
    }
}

private struct CourseWatchActivityView: View {
    let course: CoursePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(course.state.name)
                    .font(.headline)
                    .foregroundStyle(course.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .privacySensitive()
                course.timer(width: 43, font: .caption, horizontalPadding: 6, verticalPadding: 3)
            }
            if course.routeOrigin == nil {
                HStack(spacing: 6) {
                    Text(course.phase)
                        .foregroundStyle(course.foreground.opacity(0.72))
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Text(course.state.room)
                        .foregroundStyle(course.tint)
                        .truncationMode(.head)
                        .privacySensitive()
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            if !course.finished {
                CourseProgressFooter(course: course, height: 4, routeFont: .caption, routeTruncation: .head, spacing: 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct CourseExpandedHeaderAlignment: ViewModifier {
    @ScaledMetric(relativeTo: .headline) private var height = 32.0

    func body(content: Content) -> some View {
        content.frame(height: height)
    }
}

private struct CourseLockScreen: View {
    let context: ActivityViewContext<CourseActivityAttributes>
    @Environment(\.isActivityFullscreen) private var fullscreen
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        let preferredScheme = context.state.prefersDarkAppearance.map { $0 ? ColorScheme.dark : .light }
        let course = CoursePresentation(context, colorScheme: luminanceReduced ? .dark : (preferredScheme ?? colorScheme))

        return Group {
            if fullscreen {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            course.status
                            CourseDetails(course: course, titleFont: .title3)
                        }
                        VStack(alignment: .trailing, spacing: 4) {
                            course.timer(width: 100, font: .title, horizontalPadding: 13, verticalPadding: 7)
                            if !course.finished {
                                Text(course.countdownLabel)
                                    .font(.caption)
                                    .foregroundStyle(course.foreground.opacity(0.67))
                            }
                        }
                    }
                    CourseProgressFooter(course: course, height: 5)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CourseActivityCard(course: course)
            }
        }
        .background(course.background)
        .activityBackgroundTint(fullscreen ? course.background : .clear)
        .activitySystemActionForegroundColor(course.foreground)
    }
}

private struct CourseCompactTimer: View {
    let course: CoursePresentation

    var body: some View {
        Group {
            if course.finished {
                course.completionMark(font: .caption)
            } else {
                course.progressRing
                    .accessibilityLabel(Text(course.countdownLabel))
                    .accessibilityValue(Text(timerInterval: course.interval, countsDown: true))
            }
        }
        .frame(width: 20, height: 20)
    }
}

private struct CourseActivityEmblem: View {
    let course: CoursePresentation

    var body: some View {
        ZStack {
            if !course.finished {
                course.progressRing.accessibilityHidden(true)
            }
            course.mark.font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(course.tint)
        .frame(width: 23, height: 23)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("课程进度，\(course.phase)"))
    }
}

private extension CoursePresentation {
    init(_ context: ActivityViewContext<CourseActivityAttributes>, colorScheme: ColorScheme = .dark) {
        self.init(state: context.state, isStale: context.isStale, colorScheme: colorScheme)
    }
}
