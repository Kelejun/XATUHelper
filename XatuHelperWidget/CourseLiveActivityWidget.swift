import ActivityKit
import SwiftUI
import WidgetKit

struct CourseLiveActivityWidget: Widget {
    private let timetable = URL(string: "xatuhelper://timetable")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            CourseLockScreen(context: context)
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
                    course.timer(width: 55, font: .headline, capsule: false)
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
                            .foregroundStyle(course.tint)
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
                .foregroundStyle(course.foreground)
                .privacySensitive()
                .accessibilityLabel(Text("\(course.phase)，\(course.state.room)"))
            } compactTrailing: {
                course.timer(width: 46, font: .caption, capsule: false)
                    .padding(.trailing, 3)
            } minimal: {
                CourseActivityEmblem(course: course)
            }
            .widgetURL(timetable)
        }
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
        let scheme: ColorScheme = luminanceReduced ? .dark : (preferredScheme ?? colorScheme)
        let course = CoursePresentation(context, lockScreenColorScheme: scheme)
        let background = scheme == .dark
            ? Color(red: 0.06, green: 0.08, blue: 0.11)
            : Color(red: 0.96, green: 0.97, blue: 0.99)

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
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        course.status
                        Spacer(minLength: 10)
                        course.timer(width: 60, font: .headline, horizontalPadding: 10, verticalPadding: 5)
                    }
                    CourseDetails(course: course, titleFont: .title3)
                    CourseProgressFooter(course: course, height: 5)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
        .background(background)
        .activityBackgroundTint(fullscreen ? background : .clear)
        .activitySystemActionForegroundColor(course.foreground)
    }
}

private struct CourseDetails: View {
    let course: CoursePresentation
    let titleFont: Font

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(course.state.name)
                .font(titleFont.weight(.semibold))
                .foregroundStyle(course.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if course.routeOrigin == nil {
                Spacer(minLength: 0)
                let room = Text(course.state.room)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if course.isOnIsland {
                        room.foregroundStyle(.secondary)
                    } else {
                        room.foregroundStyle(course.tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(course.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: 96, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
    }
}

private struct CourseProgressFooter: View {
    let course: CoursePresentation
    let height: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            if let previous = course.routeOrigin {
                HStack(spacing: 8) {
                    Text(previous)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(course.tint)
                    Text(course.state.room)
                        .foregroundStyle(course.isOnIsland ? course.foreground : course.tint)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(course.foreground.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .privacySensitive()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("从\(previous)到\(course.state.room)"))
            }
            course.track(height: height)
        }
    }
}

private struct CourseActivityEmblem: View {
    let course: CoursePresentation

    var body: some View {
        ZStack {
            if !course.finished {
                ProgressView(timerInterval: course.interval, countsDown: course.countsDown) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(course.tint)
                .accessibilityHidden(true)
            }
            course.mark.font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(course.tint)
        .frame(width: 23, height: 23)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("课程进度，\(course.phase)"))
    }
}

private struct CoursePresentation {
    let state: CourseActivityAttributes.ContentState
    let preparing: Bool
    let finished: Bool
    let lockScreenColorScheme: ColorScheme?

    var isOnIsland: Bool { lockScreenColorScheme == nil }

    init(_ context: ActivityViewContext<CourseActivityAttributes>, lockScreenColorScheme: ColorScheme? = nil) {
        self.lockScreenColorScheme = lockScreenColorScheme
        state = context.state
        let now = Date()
        let hasPreparation = state.begins < state.start
        preparing = hasPreparation && !context.isStale && now < state.start
        finished = now >= state.end || (!hasPreparation && context.isStale)
    }

    var phase: String {
        if finished { return "已下课" }
        if !preparing { return "上课中" }
        return state.previousRoom == nil ? "课前" : "课间"
    }

    var routeOrigin: String? {
        guard preparing, let previous = state.previousRoom, previous != state.room else { return nil }
        return previous
    }

    var countdownLabel: String { preparing ? "距上课" : "距下课" }
    var mark: Image {
        Image(systemName: finished ? "checkmark" : preparing ? "figure.walk" : "book.fill")
    }
    var foreground: Color { lockScreenColorScheme == .light ? Color(white: 0.12) : .white }

    var tint: Color {
        guard let colorScheme = lockScreenColorScheme else { return .blue }
        let color = CampusCourseColors.color(index: state.colorIndex)
        if colorScheme == .light {
            let resolved = color.resolve(in: EnvironmentValues())
            return Color(red: Double(resolved.red) * 0.72,
                         green: Double(resolved.green) * 0.72,
                         blue: Double(resolved.blue) * 0.72)
        }
        if #available(iOS 18, *) { return color.mix(with: .white, by: 0.34) }
        return color
    }
    var interval: ClosedRange<Date> { preparing ? state.begins...state.start : state.start...state.end }
    var countsDown: Bool { preparing && state.previousRoom == nil }

    var status: some View {
        HStack(spacing: 5) {
            mark.font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(phase).font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isOnIsland ? foreground.opacity(0.75) : tint)
    }

    @ViewBuilder func timer(
        width: CGFloat,
        font: Font,
        capsule: Bool = true,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) -> some View {
        if finished {
            Image(systemName: "checkmark")
                .font(font.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityLabel(Text(phase))
        } else {
            let countdown = Text(timerInterval: interval, countsDown: true, showsHours: false)
                .font(font.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(capsule ? .center : .trailing)
                .frame(width: width, alignment: capsule ? .center : .trailing)
                .foregroundStyle(foreground)
                .accessibilityLabel(Text(countdownLabel))
                .accessibilityValue(Text(timerInterval: interval, countsDown: true))
            if capsule {
                countdown
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background(tint.opacity(0.18), in: Capsule())
            } else {
                countdown
            }
        }
    }

    func track(height: CGFloat) -> some View {
        ProgressView(timerInterval: interval, countsDown: countsDown) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(tint)
        .frame(height: height)
        .background(foreground.opacity(0.15), in: Capsule())
        .clipShape(Capsule())
        .accessibilityLabel(Text(preparing ? "课前进度" : "课程进度"))
    }
}
