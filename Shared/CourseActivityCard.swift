#if os(iOS)
import SwiftUI

struct CourseActivityCard: View {
    let course: CoursePresentation

    var body: some View {
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
        .background(course.background)
    }
}

struct CourseDetails: View {
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
                HStack(spacing: 4) {
                    Text(course.state.room)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(course.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    if let seat = course.examSeat {
                        Text(seat)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(course.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                            .layoutPriority(1)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(course.tint)
                .frame(maxWidth: course.examSeat == nil ? 96 : 156, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
    }
}

struct CourseProgressFooter: View {
    let course: CoursePresentation
    let height: CGFloat
    var routeFont: Font = .subheadline
    var routeTruncation: Text.TruncationMode = .tail
    var spacing: CGFloat = 6

    var body: some View {
        VStack(spacing: spacing) {
            if let previous = course.routeOrigin {
                HStack(spacing: 8) {
                    Text(previous)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(course.tint)
                    Text(course.state.room)
                        .foregroundStyle(course.tint)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(routeFont.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(course.foreground.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(routeTruncation)
                .privacySensitive()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("从\(previous)到\(course.state.room)"))
            }
            course.track(height: height)
        }
    }
}

struct CoursePresentation {
    let state: CourseActivityAttributes.ContentState
    let preparing: Bool
    let finished: Bool
    let colorScheme: ColorScheme

    init(state: CourseActivityAttributes.ContentState, isStale: Bool = false, colorScheme: ColorScheme, now: Date = Date()) {
        self.colorScheme = colorScheme
        self.state = state
        let hasPreparation = state.begins < state.start
        preparing = hasPreparation && !isStale && now < state.start
        finished = (state.preparationOnly == true && !preparing) || now >= state.end || (!hasPreparation && isStale)
    }

    var isExam: Bool { state.isExam == true }

    var examSeat: String? {
        guard isExam, let seat = state.seat?.trimmingCharacters(in: .whitespacesAndNewlines), !seat.isEmpty else { return nil }
        return "座位 \(seat)"
    }

    var watchVenue: String {
        examSeat.map { "\(state.room) · \($0)" } ?? state.room
    }

    var phase: String {
        if finished {
            if isExam { return "已开考" }
            return state.preparationOnly == true ? "已上课" : "已下课"
        }
        if isExam { return "考前" }
        if !preparing { return "上课中" }
        return state.previousRoom == nil ? "课前" : "课间"
    }

    var routeOrigin: String? {
        guard preparing, let previous = state.previousRoom, previous != state.room else { return nil }
        return previous
    }

    var countdownLabel: String {
        if isExam { return "距开考" }
        return preparing ? "距上课" : "距下课"
    }

    var mark: Image {
        if finished { return Image(systemName: "checkmark") }
        if isExam { return Image(systemName: "pencil.and.list.clipboard") }
        return Image(systemName: preparing ? "figure.walk" : "book.fill")
    }
    var foreground: Color { colorScheme == .dark ? .white : Color(white: 0.12) }

    var background: Color {
        colorScheme == .dark
            ? Color(red: 0.06, green: 0.08, blue: 0.11)
            : Color(red: 0.96, green: 0.97, blue: 0.99)
    }

    var tint: Color {
        let color = isExam ? CampusFeatureColors.exam : CampusCourseColors.color(index: state.colorIndex)
        if colorScheme == .light {
            let resolved = color.resolve(in: EnvironmentValues())
            return Color(red: Double(resolved.red) * 0.72,
                         green: Double(resolved.green) * 0.72,
                         blue: Double(resolved.blue) * 0.72)
        }
        if #available(iOS 18, *) { return color.mix(with: .white, by: 0.34) }
        return color
    }
    var interval: ClosedRange<Date> { (preparing || state.preparationOnly == true) ? state.begins...state.start : state.start...state.end }

    var status: some View {
        HStack(spacing: 5) {
            mark.font(.caption.weight(.semibold)).accessibilityHidden(true)
            Text(phase).font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
    }

    @ViewBuilder func timer(
        width: CGFloat,
        font: Font,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) -> some View {
        if finished {
            completionMark(font: font)
        } else {
            Text(timerInterval: interval, countsDown: true, showsHours: false)
                .font(font.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .foregroundStyle(foreground)
                .accessibilityLabel(Text(countdownLabel))
                .accessibilityValue(Text(timerInterval: interval, countsDown: true))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(tint.opacity(0.18), in: Capsule())
        }
    }

    func completionMark(font: Font) -> some View {
        mark.font(font.weight(.semibold))
            .foregroundStyle(tint)
            .accessibilityLabel(Text(phase))
    }

    var progressRing: some View {
        progress.progressViewStyle(.circular).tint(tint)
    }

    func track(height: CGFloat) -> some View {
        progress
            .progressViewStyle(.linear)
            .tint(tint)
            .frame(height: height)
            .background(foreground.opacity(0.15), in: Capsule())
            .clipShape(Capsule())
            .accessibilityLabel(Text(isExam ? "考前进度" : (preparing ? "课前进度" : "课程进度")))
    }

    private var progress: ProgressView<EmptyView, EmptyView> {
        ProgressView(timerInterval: interval, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
    }
}
#endif
