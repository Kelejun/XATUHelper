import SwiftUI
import UIKit

struct SchoolCalendarView: View {
    @State private var info: CalendarService.Info?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showsOriginal = false
    @State private var cachedImage: UIImage?
    @State private var showsCachedImage = false
    @AppStorage("showDiagnostics") private var diagnosticsEnabled = false

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()

    private let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        List {
            if isLoading && info == nil {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在认校历上的日期…").foregroundStyle(.secondary)
                    }
                }
            } else if let info {
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let semester = highlightedSemester(info) {
                    semesterSummary(semester)
                }
                semestersSection(info)
                if !breakRows(info).isEmpty {
                    breaksSection(info)
                }
                if !info.notes.isEmpty {
                    notesSection(info)
                }
                Section {
                    Button {
                        if let data = CalendarCache.loadImage(for: info.imageURL) {
                            cachedImage = UIImage(data: data)
                            showsCachedImage = true
                        } else {
                            showsOriginal = true
                        }
                    } label: {
                        Label("查看校历原图", systemImage: "photo")
                            .font(.body.weight(.medium))
                    }
                    if diagnosticsEnabled {
                        Button {
                            UIPasteboard.general.string = info.rawText
                        } label: {
                            Label("复制识别到的文字", systemImage: "doc.on.doc")
                        }
                    }
                } footer: {
                    Text("图片 \(info.title) · 识别于 \(info.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("暂时无法加载校历", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text(errorText ?? "没拿到校历，过会儿再试。")
                        Text("校历放在教务处的网站上，只有连校内网才打得开。")
                    } actions: {
                        Button("重新加载") { Task { await load(force: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("校历")
        .navigationBarTitleDisplayMode(.large)
        .task { await load(force: false) }
        .refreshable { await load(force: true) }
        .sheet(isPresented: $showsCachedImage) {
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    if let cachedImage {
                        Image(uiImage: cachedImage)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .navigationTitle("校历原图")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsCachedImage = false } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("关闭")
                    }
                }
            }
        }
        .sheet(isPresented: $showsOriginal) {
            if let url = info?.imageURL {
                WebSheet(title: "校历", urlString: url)
            }
        }
    }

    // MARK: - 分区

    private func highlightedSemester(_ info: CalendarService.Info) -> CalendarService.SemesterSpan? {
        let today = Calendar.current.startOfDay(for: Date())
        let semesters = info.semesters.sorted { $0.start < $1.start }
        return semesters.first {
            guard let end = AppState.parseDate($0.end) else { return false }
            return end >= today
        } ?? semesters.last
    }

    private func semesterProgress(_ span: CalendarService.SemesterSpan) -> Double? {
        guard let start = AppState.parseDate(span.start),
              let end = AppState.parseDate(span.end), end > start else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        return min(max(today.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
    }

    private func semesterSummary(_ span: CalendarService.SemesterSpan) -> some View {
        let untilStart = remainingDays(span.start)
        let untilEnd = remainingDays(span.end)
        let upcoming = (untilStart ?? 0) > 0
        let active = !upcoming && (untilEnd ?? -1) >= 0
        let tint: Color = active ? .blue : .indigo

        return Section {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(active ? "当前学期" : upcoming ? "即将开学" : "学期回顾")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(tint)
                        Text(span.label)
                            .font(.title2.bold())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "calendar")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 48, height: 48)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                }

                if let days = upcoming ? untilStart : active ? untilEnd : nil {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(upcoming ? "距开学" : "距结课")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(days)")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                        Text("天")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                VStack(spacing: 10) {
                    if let progress = semesterProgress(span) {
                        ProgressView(value: progress)
                            .tint(tint)
                            .accessibilityLabel("学期进度")
                    }
                    HStack(alignment: .top) {
                        summaryDate("开学", date: span.start, alignment: .leading)
                        Spacer(minLength: 16)
                        summaryDate("结课", date: span.end, alignment: .trailing)
                    }
                }
            }
            .padding(.vertical, 8)
            .listRowBackground(
                LinearGradient(colors: [tint.opacity(0.09), Color(uiColor: .secondarySystemGroupedBackground)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
    }

    private func summaryDate(_ title: String, date: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(dayText(date)).font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private func statusBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }

    private func calendarIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func semestersSection(_ info: CalendarService.Info) -> some View {
        Section("学期安排") {
            ForEach(info.semesters, id: \.self) { span in
                let tint: Color = span == info.semesters.first ? .blue : .indigo
                HStack(alignment: .top, spacing: 12) {
                    calendarIcon("book.closed.fill", tint: tint)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(span.label).font(.headline)
                        Text("\(dayText(span.start)) — \(dayText(span.end))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let status = semesterStatus(span) {
                            statusBadge(status.text, tint: status.finished ? .secondary : tint)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// 学期状态：还没开学 / 已经开学 N 天 / 学期已结束 N 天
    private func semesterStatus(_ span: CalendarService.SemesterSpan) -> (text: String, finished: Bool)? {
        guard let start = AppState.parseDate(span.start), let end = AppState.parseDate(span.end) else {
            return nil
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if today < start {
            let days = calendar.dateComponents([.day], from: today, to: start).day ?? 0
            return ("还有 \(days) 天开学", false)
        }
        if today <= end {
            let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
            return ("已经开学 \(days) 天", false)
        }
        let days = calendar.dateComponents([.day], from: end, to: today).day ?? 0
        return ("学期已结束 \(days) 天", true)
    }

    @ViewBuilder
    private func breaksSection(_ info: CalendarService.Info) -> some View {
        Section("假期安排") {
            ForEach(breakRows(info), id: \.title) { row in
                let winter = row.title == "寒假"
                let tint: Color = winter ? .teal : .orange
                HStack(alignment: .top, spacing: 12) {
                    calendarIcon(winter ? "snowflake" : "sun.max.fill", tint: tint)
                    VStack(alignment: .leading, spacing: 8) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.title).font(.headline)
                                Spacer(minLength: 12)
                                breakStatus(row, tint: tint)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(row.title).font(.headline)
                                breakStatus(row, tint: tint)
                            }
                        }
                        Text("\(dayText(row.start)) — \(dayText(row.end))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func breakStatus(_ row: BreakRow, tint: Color) -> some View {
        if let days = remainingDays(row.start), days > 0 {
            statusBadge("还有 \(days) 天", tint: tint)
        } else if let days = remainingDays(row.start), days <= 0,
                  remainingDays(row.end).map({ $0 >= 0 }) == true {
            statusBadge("放假中", tint: tint)
        }
    }

    @ViewBuilder
    private func notesSection(_ info: CalendarService.Info) -> some View {
        Section {
            ForEach(info.notes, id: \.self) { note in
                Label {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "text.alignleft")
                        .font(.subheadline)
                        .foregroundStyle(.indigo)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("校历备注")
        } footer: {
            Text("这一节是从校历图上自动识别出来的文字，可能有识别错误，仅供参考。")
        }
    }

    // MARK: - 计算

    private struct BreakRow {
        let title: String
        let start: String
        let end: String
    }

    private func breakRows(_ info: CalendarService.Info) -> [BreakRow] {
        guard info.semesters.count >= 2 else { return [] }
        var rows: [BreakRow] = []
        let first = info.semesters[0]
        let second = info.semesters[1]
        if let start = shifted(first.end, by: 1), let end = shifted(second.start, by: -1), start <= end {
            rows.append(BreakRow(title: "寒假", start: start, end: end))
        }
        if info.semesters.count >= 3 {
            if let start = shifted(second.end, by: 1), let end = shifted(info.semesters[2].start, by: -1), start <= end {
                rows.append(BreakRow(title: "暑假", start: start, end: end))
            }
        } else if let start = shifted(info.semesters.last!.end, by: 1) {
            // 校历按一整学年 52 周排（两学期各 26 周），最后一天就是暑假的最后一天
            let yearEnd = academicYearEnd(startOf: first.start) ?? "开学另行通知"
            rows.append(BreakRow(title: "暑假", start: start, end: yearEnd))
        }
        return rows
    }

    /// 校历图上那一格：学年第一天 + 363 天（52 周整），比如 2026-08-31 → 2027-08-29
    private func academicYearEnd(startOf key: String) -> String? {
        guard let start = keyFormatter.date(from: key),
              let end = Calendar.current.date(byAdding: .day, value: 363, to: start) else { return nil }
        return keyFormatter.string(from: end)
    }

    private func shifted(_ key: String, by days: Int) -> String? {
        guard let date = keyFormatter.date(from: key),
              let moved = Calendar.current.date(byAdding: .day, value: days, to: date) else { return nil }
        return keyFormatter.string(from: moved)
    }

    private func remainingDays(_ key: String) -> Int? {
        guard let date = keyFormatter.date(from: key) else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: today, to: date).day
    }

    private func dayText(_ key: String) -> String {
        if let date = keyFormatter.date(from: key) {
            return dayFormatter.string(from: date)
        }
        return key
    }

    // MARK: - 加载

    /// 校内网才通教务处，断网/外网时给一句人话
    private func friendly(_ reason: String) -> String {
        let offline = ["-1009", "-1001", "-1004", "-1005", "timed out", "TimedOut", "找不到", "已断开"]
        if offline.contains(where: { reason.contains($0) }) {
            return "教务处的校历页只能在校内网络打开，现在连不上"
        }
        return reason
    }

    private func fallbackToCache(_ reason: String) {
        if let cached = CalendarCache.load() {
            info = cached
            errorText = reason + "。下面显示的是上次的结果。"
        } else {
            errorText = reason
        }
    }

    private func load(force: Bool) async {
        if !force, let cached = CalendarCache.load() {
            info = cached
            // 后台顺手看看有没有新校历，图片没变就直接用缓存
            Task { await refreshIfNeeded() }
            return
        }
        await refreshIfNeeded(force: force)
    }

    private func refreshIfNeeded(force: Bool = false) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let page: CalendarService.CalendarPage
        switch await CalendarService.loadPage() {
        case .success(let value):
            page = value
        case .failure(let error):
            fallbackToCache(friendly(error.localizedDescription))
            return
        }
        if !force, let cached = CalendarCache.load(imageURL: page.imageURL.absoluteString) {
            info = cached
            return
        }
        let data: Data
        switch await CalendarService.downloadImage(page.imageURL) {
        case .success(let value):
            data = value
            CalendarCache.saveImage(value, for: page.imageURL.absoluteString)
        case .failure(let error):
            fallbackToCache(friendly(error.localizedDescription))
            return
        }
        let text = await Task.detached(priority: .userInitiated) {
            CalendarService.recognizeText(from: data)
        }.value

        let parsed = CalendarService.parse(text, title: page.title, pageURL: page.pageURL, imageURL: page.imageURL)
        guard !parsed.semesters.isEmpty else {
            errorText = "校历上的日期没认出来，可以先看原图。"
            info = parsed
            return
        }
        info = parsed
        CalendarCache.save(parsed)
        PhoneWatchBridge.shared.publish()
    }
}
