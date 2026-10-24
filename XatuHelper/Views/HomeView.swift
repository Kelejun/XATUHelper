import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var now = Date()

    // MARK: - 问候语

    /// 按时间段换问候语。分界点：5:00 早起、11:30 午饭、13:30 下午、18:00 晚上、22:30 晚安。
    private var greeting: String {
        switch nowMinutes {
        case 300..<690: return "早，"
        case 690..<810: return "吃饭没？"
        case 810..<1080: return "下午好，"
        case 1080..<1350: return "晚上好，"
        default: return "晚安。"
        }
    }

    private var nowMinutes: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - 今天的课

    /// 周一 = 1 … 周日 = 7
    private var todayWeekday: Int { isoWeekday(of: now) }

    private var todayBlocks: [CourseBlock] {
        guard app.isCurrentSemester else { return [] }
        return app.occurrences(in: app.currentWeek)
            .filter { $0.day == todayWeekday }
            .courseBlocks()
            .sorted { $0.startPeriod < $1.startPeriod }
    }

    /// 这会儿正在上的课
    private var currentBlock: CourseBlock? {
        todayBlocks.first {
            PeriodSchedule.startMinutes($0.startPeriod) <= nowMinutes
                && nowMinutes < PeriodSchedule.endMinutes($0.endPeriod)
        }
    }

    /// 还没开始的课
    private var remainingToday: [CourseBlock] {
        todayBlocks.filter { PeriodSchedule.startMinutes($0.startPeriod) > nowMinutes }
    }

    /// 今天没有正在上的、也没有剩下的，就翻到明天
    private var showingTomorrow: Bool {
        currentBlock == nil && remainingToday.isEmpty
    }

    private var tomorrowBlocks: [CourseBlock] {
        guard app.isCurrentSemester,
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return [] }
        let weekday = isoWeekday(of: tomorrow)
        let week = app.week(of: tomorrow)
        return app.occurrences(in: week)
            .filter { $0.day == weekday }
            .courseBlocks()
            .sorted { $0.startPeriod < $1.startPeriod }
    }

    private var tomorrowWeekdayLabel: String {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return "" }
        return "周" + weekdayNames[isoWeekday(of: tomorrow) - 1]
    }

    private var todayWeekdayLabel: String { "周" + weekdayNames[todayWeekday - 1] }

    private let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    /// 标题和卡片之间留两个标题那么高（会跟着动态字体缩放）
    private var titleGap: CGFloat {
        UIFont.preferredFont(forTextStyle: .largeTitle).lineHeight * 2
    }

    private func isoWeekday(of date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    // MARK: - 视图

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    scheduleCard
                }
                .padding(.horizontal, 16)
                .padding(.top, titleGap)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    /// 卡片标题：还没开课 / 上到一半 / 没课了翻明天 / 明天也没课
    private var cardTitle: String {
        if showingTomorrow {
            return tomorrowBlocks.isEmpty ? "明天没有课，好好休息下吧" : "今天没课了，明天要上这些课："
        }
        if currentBlock != nil { return "今天还有这些课：" }
        return remainingToday.count == todayBlocks.count ? "今天要上这些课：" : "今天还有这些课："
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cardTitle)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(showingTomorrow ? tomorrowWeekdayLabel : todayWeekdayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if showingTomorrow {
                if !tomorrowBlocks.isEmpty {
                    ForEach(tomorrowBlocks) { row($0) }
                }
            } else {
                if let currentBlock {
                    currentRow(currentBlock)
                }
                ForEach(remainingToday) { row($0) }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func row(_ block: CourseBlock) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeText(block))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.name)
                    .font(.subheadline)
                if !block.shortRoom.isEmpty {
                    Text(block.shortRoom)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func currentRow(_ block: CourseBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("正在上")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                Text(block.name)
                    .font(.subheadline.weight(.medium))
            }
            HStack(spacing: 8) {
                Text(timeText(block))
                if !block.shortRoom.isEmpty { Text(block.shortRoom) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private func timeText(_ block: CourseBlock) -> String {
        "\(PeriodSchedule.startTime(block.startPeriod))-\(PeriodSchedule.endTime(block.endPeriod))"
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
