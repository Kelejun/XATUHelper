import SwiftUI

/// 未央校区的作息表。教务系统只给节次，时间是我们补的，用来把网格画得像系统日历。
enum PeriodSchedule {
    static let start = ["08:20", "09:10", "10:20", "11:10", "14:00", "14:50",
                        "16:00", "16:50", "18:10", "19:05", "20:00", "20:55"]
    static let end = ["09:05", "10:00", "11:05", "12:00", "14:45", "15:40",
                      "16:45", "17:40", "18:55", "19:50", "20:45", "21:40"]

    static func startTime(_ period: Int) -> String { value(start, period - 1) }
    static func endTime(_ period: Int) -> String { value(end, period - 1) }

    /// 从零点算起的分钟数，用来判断"现在上的是哪一节"
    static func startMinutes(_ period: Int) -> Int { minutes(startTime(period)) }
    static func endMinutes(_ period: Int) -> Int { minutes(endTime(period)) }

    private static func minutes(_ hm: String) -> Int {
        let parts = hm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return 0 }
        return hour * 60 + minute
    }

    static func range(from: Int, to: Int) -> String {
        "\(startTime(from))-\(endTime(to))"
    }

    /// 教3 楼早上 3-4 节的作息跟其他楼不一样，教务排的是 10:10-11:40
    static func isJiaoSanEarly(_ block: CourseBlock) -> Bool {
        block.startPeriod == 3 && block.endPeriod == 4 && block.room.contains("教3")
    }

    static func range(for block: CourseBlock) -> String {
        isJiaoSanEarly(block) ? "10:10-11:40" : range(from: block.startPeriod, to: block.endPeriod)
    }

    static func isJiaoSanEarly(room: String, period: Int) -> Bool {
        period == 3 && room.contains("教3")
    }

    static func startMinutes(of block: CourseBlock) -> Int {
        isJiaoSanEarly(block) ? minutes("10:10") : startMinutes(block.startPeriod)
    }

    static func endMinutes(of block: CourseBlock) -> Int {
        isJiaoSanEarly(block) ? minutes("11:40") : endMinutes(block.endPeriod)
    }

    private static func value(_ list: [String], _ index: Int) -> String {
        guard index >= 0, index < list.count else { return "" }
        return list[index]
    }
}

/// 周课表：宽窗口提供节次时间轴，窄窗口保留紧凑网格。
struct WeekGrid: View {
    let blocks: [CourseBlock]
    let unitCount: Int
    /// 这一周的周一，非当前学期传 nil，表头就只显示星期
    var monday: Date?
    /// 只显示周一到周五
    var showWeekend: Bool = true
    var onSelect: (CourseBlock) -> Void

    @Environment(\.campusNavigation) private var navigate
    @ScaledMetric(relativeTo: .caption) private var minimumRowHeight: CGFloat = 44

    private var headerHeight: CGFloat { navigate == nil ? 40 : 56 }
    private let maxRowHeight: CGFloat = 84
    private let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    /// iPad 展示完整作息轴；手机只画到这一周最后一节课。
    private var periods: Int {
        let latest = blocks.map(\.endPeriod).max() ?? 0
        return max(latest, navigate == nil ? 4 : max(unitCount, 4))
    }

    private var dayCount: Int { showWeekend ? 7 : 5 }

    var body: some View {
        GeometryReader { proxy in
            let axisWidth: CGFloat = proxy.size.width >= 600 ? 60 : 0
            let gridWidth = max(0, proxy.size.width - axisWidth)
            let dayWidth = gridWidth / CGFloat(dayCount)
            let available = max(proxy.size.height - headerHeight, 0)
            let minimum = max(minimumRowHeight, navigate == nil ? 44 : 56)
            let rowHeight = max(minimum, min(maxRowHeight, available / CGFloat(periods)))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if axisWidth > 0 {
                        Text("节次").font(.caption2).foregroundStyle(.secondary)
                            .frame(width: axisWidth, height: headerHeight)
                    }
                    headerRow(dayWidth: dayWidth)
                }
                .background(Color(.systemBackground))

                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        if axisWidth > 0 { timeAxis(width: axisWidth, rowHeight: rowHeight) }
                        ZStack(alignment: .topLeading) {
                            gridLines(dayWidth: dayWidth, rowHeight: rowHeight)
                            blockLayer(dayWidth: dayWidth, rowHeight: rowHeight)
                        }
                        .frame(width: gridWidth, height: CGFloat(periods) * rowHeight, alignment: .topLeading)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(Color(.systemBackground))
        }
    }

    private func timeAxis(width: CGFloat, rowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(1...periods, id: \.self) { period in
                VStack(spacing: 4) {
                    Text("\(period)").font(.caption.weight(.medium))
                    Text(PeriodSchedule.startTime(period))
                        .font(.system(size: 10)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .frame(width: width, height: rowHeight, alignment: .top)
            }
        }
        .background(Color(.secondarySystemBackground).opacity(0.55))
    }

    // MARK: - 表头

    private func headerRow(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<dayCount, id: \.self) { index in
                let day = date(at: index)
                let isToday = day.map { Calendar.current.isDateInToday($0) } ?? false

                VStack(spacing: 1) {
                    Text(dayLabels[index])
                        .font(.system(size: navigate == nil ? 11 : 13, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                    if let day {
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.system(size: navigate == nil ? 15 : 20, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                    }
                }
                .frame(width: dayWidth, height: headerHeight)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.6))
                .frame(height: 0.5)
        }
    }

    private func date(at index: Int) -> Date? {
        guard let monday else { return nil }
        return Calendar.current.date(byAdding: .day, value: index, to: monday)
    }

    // MARK: - 网格

    private func gridLines(dayWidth: CGFloat, rowHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<dayCount, id: \.self) { index in
                let today = date(at: index).map { Calendar.current.isDateInToday($0) } ?? false
                Rectangle()
                    .fill(today ? Color.accentColor.opacity(0.04) : (index >= 5 ? Color(.secondarySystemBackground).opacity(0.4) : Color.clear))
                    .frame(width: dayWidth, height: CGFloat(periods) * rowHeight)
                    .offset(x: CGFloat(index) * dayWidth)
            }
            ForEach(0...periods, id: \.self) { row in
                Rectangle()
                    .fill(Color(.separator).opacity(0.5))
                    .frame(width: dayWidth * CGFloat(dayCount), height: 0.5)
                    .offset(y: CGFloat(row) * rowHeight)
            }
            ForEach(1..<dayCount, id: \.self) { column in
                Rectangle()
                    .fill(Color(.separator).opacity(0.5))
                    .frame(width: 0.5, height: CGFloat(periods) * rowHeight)
                    .offset(x: CGFloat(column) * dayWidth)
            }
        }
    }

    // MARK: - 课程块

    private func blockLayer(dayWidth: CGFloat, rowHeight: CGFloat) -> some View {
        ForEach(blocks.filter { $0.day <= dayCount }) { block in
            blockView(block, dayWidth: dayWidth, rowHeight: rowHeight)
                .offset(
                    x: CGFloat(block.day - 1) * dayWidth + 1.5,
                    y: CGFloat(block.startPeriod - 1) * rowHeight + 1
                )
        }
    }

    private func blockView(_ block: CourseBlock, dayWidth: CGFloat, rowHeight: CGFloat) -> some View {
        let tint = color(for: block)
        let height = rowHeight * CGFloat(block.span) - 2

        return Button {
            onSelect(block)
        } label: {
            HStack(alignment: .top, spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: 2.5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(block.name)
                        .font(dayWidth >= 90 ? .subheadline.weight(.semibold) : .caption2.weight(.semibold))
                        .lineLimit(dayWidth >= 90 ? 2 : (block.span >= 2 ? 4 : 2))
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    if dayWidth >= 90, height >= 110, !block.teacher.isEmpty {
                        Text(block.teacher)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    if block.span >= 2, !block.room.isEmpty {
                        Text(block.shortRoom)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.vertical, dayWidth >= 90 ? 7 : 3)

                Spacer(minLength: 0)
            }
            .padding(.leading, 3)
            .padding(.trailing, 4)
            .foregroundStyle(tint)
            .frame(width: dayWidth - 3, height: height, alignment: .topLeading)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: navigate == nil ? 6 : 10))
        }
        .buttonStyle(.plain)
    }

    private func color(for block: CourseBlock) -> Color {
        CoursePalette.color(for: block)
    }
}
