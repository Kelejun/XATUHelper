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
    @GestureState private var inspectingUsage = false
    @State private var selectedUsageDate: Date?

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
                    Text("近30天余额")
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

    private var refreshButton: some View {
        Button {
            Task { await app.refreshElectricity() }
        } label: {
            ZStack {
                Circle().fill(Color.orange.opacity(0.12))
                if app.electricityLoading {
                    ProgressView().tint(.orange)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .disabled(app.electricityLoading)
        .accessibilityLabel("刷新电费")
    }

    private var balanceActions: some View {
        HStack(spacing: 10) {
            chargeButton
            refreshButton
        }
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
                    balanceActions
                }
                VStack(alignment: .leading, spacing: 12) {
                    lastChecked
                    balanceActions
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
        let selected = inspectingUsage ? points.first { $0.date == selectedUsageDate } : nil

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
            VStack(alignment: .leading, spacing: 12) {
                Chart {
                    ForEach(points) { point in
                        if let usage = point.usage {
                            AreaMark(
                                x: .value("日期", point.date, unit: .day),
                                y: .value("用量", usage)
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
                                y: .value("用量", usage)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            PointMark(
                                x: .value("日期", point.date, unit: .day),
                                y: .value("用量", usage)
                            )
                            .foregroundStyle(.orange)
                            .symbolSize(point.hasRecharge ? 40 : 14)
                            .accessibilityLabel(point.date.formatted(.dateTime.month().day()))
                            .accessibilityValue(String(format: "%.2f 度", usage) + (point.hasRecharge ? "，充值日估算" : ""))
                        }
                        if point.hasRecharge {
                            RuleMark(x: .value("充值日期", point.date, unit: .day))
                                .foregroundStyle(.orange.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .annotation(position: .top) {
                                    Text(point.usage == nil ? "充值" : "充值·估算")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("日期", selected.date, unit: .day))
                            .foregroundStyle(.orange.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .accessibilityHidden(true)
                        if let usage = selected.usage {
                            PointMark(x: .value("日期", selected.date, unit: .day),
                                      y: .value("用量", usage))
                                .foregroundStyle(.orange)
                                .symbolSize(65)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .chartXScale(domain: trendStart...trendPlotEnd)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) {
                        AxisValueLabel(format: .dateTime.month().day())
                    }
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
                .frame(height: 180)
                .overlay(alignment: .topTrailing) {
                    if let selected {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(selected.date.formatted(.dateTime.month().day()))
                                .foregroundStyle(.secondary)
                            Text(selected.usage.map { String(format: "%.2f 度", $0) } ?? "暂无用量估算")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                            if selected.hasRecharge {
                                Text(selected.usage == nil ? "有电费充值" : "充值日·平均用量估算")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                        }
                        .font(.subheadline)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .combine)
                        .allowsHitTesting(false)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.25)
                                    .sequenced(before: DragGesture(minimumDistance: 0))
                                    .updating($inspectingUsage) { value, state, _ in
                                        if case .second(true, _) = value { state = true }
                                    }
                                    .onChanged { value in
                                        guard case let .second(true, drag?) = value,
                                              let plotFrame = proxy.plotFrame else { return }
                                        let frame = geometry[plotFrame]
                                        let x = min(max(drag.location.x - frame.minX, 0), frame.width)
                                        guard let date = proxy.value(atX: x, as: Date.self) else { return }
                                        let day = Calendar.current.startOfDay(for: date)
                                        selectedUsageDate = points.min {
                                            abs($0.date.timeIntervalSince(day)) < abs($1.date.timeIntervalSince(day))
                                        }?.date
                                    }
                                    .onEnded { _ in selectedUsageDate = nil }
                            )
                            .accessibilityHidden(true)
                    }
                }

                if let average = averageUsageText {
                    Text(average)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var trendEnd: Date { Calendar.current.startOfDay(for: Date()) }

    private var trendPlotEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: trendEnd) ?? trendEnd
    }

    private var trendStart: Date {
        Calendar.current.date(byAdding: .day, value: -29, to: trendEnd) ?? trendEnd
    }

    private var usagePoints: [ElectricityUsagePoint] {
        ElectricityUsagePoint.make(history: app.electricityHistory, from: trendStart, through: trendEnd)
    }

    private var averageUsageText: String? {
        let values = usagePoints.compactMap(\.usage)
        guard !values.isEmpty else { return nil }
        return String(format: "有记录的 %d 天，平均每天用 %.2f 度", values.count,
                      values.reduce(0, +) / Double(values.count))
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
