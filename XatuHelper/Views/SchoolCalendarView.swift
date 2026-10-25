import SwiftUI

struct SchoolCalendarView: View {
    @State private var info: CalendarService.Info?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showsOriginal = false
    @State private var showsDiagnostics = false
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
                        showsOriginal = true
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
            rows.append(BreakRow(title: "暑假", start: start, end: "开学另行通知"))
        }
        return rows
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
            fallbackToCache(error.localizedDescription)
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
        case .failure(let error):
            fallbackToCache(error.localizedDescription)
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
