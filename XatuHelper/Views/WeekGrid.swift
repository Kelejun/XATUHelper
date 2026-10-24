import SwiftUI

/// 未央校区的作息表。教务系统只给节次，时间是我们补的，用来把网格画得像系统日历。
enum PeriodSchedule {
    static let start = ["08:20", "09:10", "10:20", "11:10", "14:00", "14:50",
                        "16:00", "16:50", "19:00", "19:50", "20:45", "21:30"]
    static let end = ["09:05", "10:00", "11:05", "12:00", "14:45", "15:40",
                      "16:45", "17:40", "19:45", "20:40", "21:25", "22:20"]

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

    private static func value(_ list: [String], _ index: Int) -> String {
        guard index >= 0, index < list.count else { return "" }
        return list[index]
    }
}

/// 一周课表网格，样式照着系统日历的周视图来。不留时间轴，整宽平分给各天。
struct WeekGrid: View {
    let blocks: [CourseBlock]
    let unitCount: Int
    /// 这一周的周一，非当前学期传 nil，表头就只显示星期
    var monday: Date?
    /// 只显示周一到周五
    var showWeekend: Bool = true
    var onSelect: (CourseBlock) -> Void

    private let headerHeight: CGFloat = 40
    private let minRowHeight: CGFloat = 28
    private let maxRowHeight: CGFloat = 84
    private let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    private let palette: [Color] = [
        Color(red: 0.20, green: 0.47, blue: 0.90),
        Color(red: 0.85, green: 0.42, blue: 0.20),
        Color(red: 0.18, green: 0.60, blue: 0.45),
        Color(red: 0.58, green: 0.35, blue: 0.75),
        Color(red: 0.82, green: 0.55, blue: 0.12),
        Color(red: 0.12, green: 0.53, blue: 0.68),
        Color(red: 0.74, green: 0.30, blue: 0.45),
        Color(red: 0.35, green: 0.50, blue: 0.25)
    ]

    /// 只画到这一周真实排到的最晚一节，别留一排空格子
    private var periods: Int {
        let latest = blocks.map(\.endPeriod).max() ?? 0
        return max(latest, 4)
    }

    private var dayCount: Int { showWeekend ? 7 : 5 }

    var body: some View {
        GeometryReader { proxy in
            let dayWidth = proxy.size.width / CGFloat(dayCount)
            let available = max(proxy.size.height - headerHeight, 0)
            let rowHeight = min(maxRowHeight, max(minRowHeight, available / CGFloat(periods)))

            VStack(spacing: 0) {
                headerRow(dayWidth: dayWidth)

                // 不用 ScrollView：竖把手势让给外层翻周，行高自己缩到能放下
                ZStack(alignment: .topLeading) {
                    gridLines(dayWidth: dayWidth, rowHeight: rowHeight)
                    blockLayer(dayWidth: dayWidth, rowHeight: rowHeight)
                }
                .frame(
                    width: proxy.size.width,
                    height: CGFloat(periods) * rowHeight,
                    alignment: .topLeading
                )
            }
        }
    }

    // MARK: - 表头

    private func headerRow(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<dayCount, id: \.self) { index in
                let day = date(at: index)
                let isToday = day.map { Calendar.current.isDateInToday($0) } ?? false

                VStack(spacing: 1) {
                    Text(dayLabels[index])
                        .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                    if let day {
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.system(size: 15, weight: isToday ? .bold : .regular))
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
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(block.span >= 2 ? 4 : 2)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    if block.span >= 2, !block.room.isEmpty {
                        Text(block.shortRoom)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.vertical, 3)

                Spacer(minLength: 0)
            }
            .padding(.leading, 3)
            .padding(.trailing, 4)
            .foregroundStyle(tint)
            .frame(width: dayWidth - 3, height: height, alignment: .topLeading)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func color(for block: CourseBlock) -> Color {
        if block.isRemote {
            return Color(red: 0.52, green: 0.44, blue: 0.72)
        }
        if block.isPlaceholder {
            return Color(red: 0.50, green: 0.50, blue: 0.54)
        }
        var hash = 5381
        for byte in block.courseKey.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        return palette[abs(hash % palette.count)]
    }
}
