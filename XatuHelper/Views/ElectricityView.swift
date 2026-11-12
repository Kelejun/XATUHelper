import Charts
import SwiftUI
import UIKit

/// 电费页：没选过宿舍就引导去选，选过就直接显示余额。
struct ElectricityView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var app: AppState
    @State private var editing = false
    @State private var showingCharge = false
    @State private var chargeURL: String?
    @State private var chargeTarget: String?
    @State private var preparingCharge = false

    var body: some View {
        List {
            if let dorm = app.dorm {
                Section {
                    balanceCard
                        .listRowBackground(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.09), Color(uiColor: .secondarySystemGroupedBackground)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }

                Section {
                    trendChart
                    NavigationLink {
                        ElectricityHistoryView()
                    } label: {
                        Label("历史余额", systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text("近 7 天用量")
                } footer: {
                    Text("每天第一次查到余额时记一条，同一天刷新多次只留一条。")
                }

                Section("宿舍") {
                    LabeledContent("房间", value: dorm.displayName)
                    if !dorm.areaName.isEmpty, dorm.areaName != dorm.buildName {
                        LabeledContent("校区", value: dorm.areaName)
                    }
                    Button { editing = true } label: {
                        Label("换一个宿舍", systemImage: "arrow.left.arrow.right")
                    }
                }

                if let error = app.electricityError {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("选择宿舍", systemImage: "building.2")
                    } description: {
                        Text("选择楼栋和房间后，即可查看剩余电量。")
                    } actions: {
                        Button("选择宿舍") { editing = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("电费")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if app.dorm != nil {
                    Button {
                        Task { await app.refreshElectricity() }
                    } label: {
                        if app.electricityLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(app.electricityLoading)
                    .accessibilityLabel("刷新电费")
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                DormPickerView()
            }
        }
        .sheet(isPresented: $showingCharge) {
            if let chargeURL {
                WebSheet(title: "充值", urlString: chargeURL, followUpURL: chargeTarget)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await app.refreshElectricityIfNeeded()
        }
    }

    private var chargeButton: some View {
        Button {
            Task {
                preparingCharge = true
                if let page = await app.chargePage() {
                    chargeURL = page.url
                    chargeTarget = page.hash
                    showingCharge = true
                } else {
                    app.electricityError = "没拿到充值页地址，先换一个宿舍再试"
                }
                preparingCharge = false
            }
        } label: {
            HStack(spacing: 8) {
                if preparingCharge {
                    ProgressView().tint(.orange)
                } else {
                    Image(systemName: "yensign.circle.fill")
                }
                Text(preparingCharge ? "正在打开充值…" : "电费充值")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(preparingCharge)
        .accessibilityLabel("充值")
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Text(app.dorm?.displayName ?? "宿舍电费")
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 48, height: 48)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("剩余电量")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                balanceValue
                    .accessibilityElement(children: .combine)
                if app.isLowBalance {
                    Label("电量偏低，请及时充值", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    lastChecked
                    Spacer(minLength: 0)
                    chargeButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    lastChecked
                    chargeButton
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var lastChecked: some View {
        if let checked = app.electricityCheckedAt {
            VStack(alignment: .leading, spacing: 4) {
                Text("上次查询").font(.caption)
                Text(checked.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var trendChart: some View {
        let points = usagePoints

        if points.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("再攒几天就能看到每天用多少了")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Chart(points) { point in
                    AreaMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("用量", point.usage)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.orange.opacity(0.30), .orange.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("用量", point.usage)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("用量", point.usage)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(26)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(String(format: amount < 10 ? "%.1f 度" : "%.0f 度", amount))
                            }
                        }
                    }
                }
                .frame(height: 150)

                if let average = averageUsageText(app.electricityTrend()) {
                    Text(average)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private struct UsagePoint: Identifiable {
        let date: Date
        let usage: Double
        var id: Date { date }
    }

    /// 每天用量 = 前一天余额 - 当天余额；余额涨了（充值）就记 0
    private var usagePoints: [UsagePoint] {
        let trend = app.electricityTrend()
        guard trend.count >= 2 else { return [] }
        var points: [UsagePoint] = []
        for index in 1..<trend.count {
            let previous = trend[index - 1]
            let current = trend[index]
            guard previous.day != current.day else { continue }
            points.append(UsagePoint(date: current.date, usage: max(0, previous.balance - current.balance)))
        }
        return points
    }

    private func averageUsageText(_ trend: [ElectricityRecord]) -> String? {
        guard let first = trend.first, let last = trend.last, trend.count >= 2 else { return nil }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: first.date),
            to: Calendar.current.startOfDay(for: last.date)
        ).day ?? 0
        guard days > 0 else { return nil }
        let used = usagePoints.reduce(0) { $0 + $1.usage }
        return String(format: "平均每天用 %.2f 度", used / Double(days))
    }

    @ViewBuilder
    private var balanceValue: some View {
        if let balance = app.electricityBalance {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(balance)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                Text("度")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        } else if app.electricityLoading {
            Text("查询中…")
                .font(.title3)
                .foregroundStyle(.secondary)
        } else {
            Text("还没查到余额")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

/// 选宿舍：校区只有一个就自动选掉，楼栋和房间各自一页
struct DormPickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showDiagnostics") private var showDiagnostics = false

    @State private var schools: [DormOption] = []
    @State private var buildings: [DormOption] = []
    @State private var area: DormOption?

    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("重试") { Task { await loadSchools() } }
                    if showDiagnostics {
                        DiagnosticExportButton(filenamePrefix: "XATune-electricity-diagnostics") {
                            [
                                PayService.lastLogin ?? "(没有登录记录)",
                                PayService.lastRaw ?? "(没有接口返回)",
                                PayService.lastError ?? "(没有错误记录)"
                            ].joined(separator: "\n\n")
                        }
                    }
                }
            }

            if area == nil {
                Section("校区") {
                    if loading && schools.isEmpty { ProgressView() }
                    ForEach(schools) { option in
                        Button(option.name) {
                            area = option
                            buildings = []
                            Task { await loadBuildings(area: option) }
                        }
                    }
                }
            } else {
                Section("楼栋") {
                    if loading && buildings.isEmpty {
                        ProgressView()
                    }
                    ForEach(buildings) { option in
                        NavigationLink(option.name) {
                            RoomPickerPage(area: area!, build: option) { room in
                                save(area: area!, build: option, room: room)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("选择宿舍")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task { await loadSchools() }
    }

    private func loadSchools() async {
        loading = true
        error = nil
        do {
            schools = try await app.loadSchools()
            // 只有一个校区就直接选掉，别让用户多点一步
            if schools.count == 1, let only = schools.first {
                area = only
                await loadBuildings(area: only)
            }
        } catch {
            self.error = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func loadBuildings(area: DormOption) async {
        loading = true
        do {
            buildings = try await app.loadBuildings(areaID: area.id)
        } catch {
            self.error = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func save(area: DormOption, build: DormOption, room: DormOption) {
        let selection = DormSelection(
            areaID: area.id,
            areaName: area.name,
            buildID: build.id,
            buildName: build.name,
            roomID: room.id,
            roomName: room.name
        )
        dismiss()
        Task { await app.saveDorm(selection) }
    }
}

/// 房间列表，选中就直接存
private struct RoomPickerPage: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let area: DormOption
    let build: DormOption
    let onPick: (DormOption) -> Void

    @State private var rooms: [DormOption] = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""

    private var filtered: [DormOption] {
        let keyword = search.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return rooms }
        return rooms.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("重试") { Task { await load() } }
                }
            }
            if loading && rooms.isEmpty {
                Section { ProgressView() }
            }
            ForEach(filtered) { option in
                Button {
                    onPick(option)
                    dismiss()
                } label: {
                    Text(option.name).foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(build.name)
        .searchable(text: $search, prompt: "搜房间号")
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            rooms = try await app.loadRooms(areaID: area.id, buildID: build.id)
        } catch {
            self.error = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}
