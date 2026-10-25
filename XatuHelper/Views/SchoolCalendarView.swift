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
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在认校历上的日期…").foregroundStyle(.secondary)
                    }
                }
            } else if let info {
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
                    Text(errorText ?? "没拿到校历，过会儿再试。")
                        .foregroundStyle(.secondary)
                    Text("校历放在教务处的网站上，只有连校内网才打得开。")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Button("重新加载") { Task { await load(force: true) } }
                    if let info {
                        Text(info.rawText).font(.caption2)
                    }
                }
            }
        }
        .navigationTitle("校历")
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private func semestersSection(_ info: CalendarService.Info) -> some View {
        Section("学期") {
            ForEach(info.semesters, id: \.self) { span in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(span.label).font(.headline)
                        Spacer()
                        if let days = remainingDays(span.end) {
                            Text(days >= 0 ? "还有 \(days) 天结课" : "已结课")
                                .font(.caption)
                                .foregroundStyle(days >= 0 ? Color.secondary : Color.orange)
                        }
                    }
                    Text("开学 \(dayText(span.start)) · 结课 \(dayText(span.end))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func breaksSection(_ info: CalendarService.Info) -> some View {
        Section("假期") {
            ForEach(breakRows(info), id: \.title) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.title).font(.headline)
                        Spacer()
                        if let days = remainingDays(row.start), days > 0 {
                            Text("还有 \(days) 天").font(.caption).foregroundStyle(.secondary)
                        } else if let days = remainingDays(row.start), days <= 0, remainingDays(row.end).map({ $0 >= 0 }) == true {
                            Text("放假中").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text("\(dayText(row.start)) – \(dayText(row.end))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ info: CalendarService.Info) -> some View {
        Section("其他") {
            ForEach(info.notes, id: \.self) { note in
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
    }
}
