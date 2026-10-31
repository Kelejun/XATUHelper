#if canImport(Charts)
import Charts
#endif
import SwiftUI

/// 电费页：没选过宿舍就引导去选，选过就直接显示余额。
struct ElectricityView: View {
    @Environment(AppState.self) var app
    @Environment(\.colorScheme) var colorScheme
    @State var editing = false
    @State var showingCharge = false
    @State var chargeURL: String?
    @State var chargeTarget: String?
    @State var preparingCharge = false

    var body: some View {
        Form {
            if let dorm = app.dorm {
                Section {
                    balanceCard.md3Card(prominent: true)
                }

                Section {
                    trendChart
                    NavigationLink("历史余额") {
                        ElectricityHistoryView()
                    }.frame(minHeight: 40)
                } header: {
                    Text("近 7 天用量")
                } footer: {
                    Text("每天第一次查到余额时记一条，同一天刷新多次只留一条。")
                }

                Section("宿舍") {
                    LabeledContent("房间", value: dorm.displayName).frame(minHeight: 40)
                    if !dorm.areaName.isEmpty, dorm.areaName != dorm.buildName {
                        LabeledContent("校区", value: dorm.areaName).frame(minHeight: 40)
                    }
                    Button("换一个宿舍") { editing = true }
                }

                if let error = app.electricityError {
                    Section {
                        Text(error)
                            .font(MD3Type.bodyMedium)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Section {
                    Button("选择宿舍") { editing = true }
                } footer: {
                    Text("先告诉我在哪栋楼哪个房间，以后打开 app 自动查。")
                }
            }
        }
        .md3List()
        .navigationTitle("电费")
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
        .task {
            await app.refreshElectricityIfNeeded()
        }
    }

    /// 余额卡片右边那个绿色充值按钮，点了用内置网页打开缴费平台的充值页
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
                if preparingCharge { ProgressView() }
                else { AppIcon("yensign", size: 18) }
                Text("充值").font(MD3Type.label)
            }.frame(minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .disabled(preparingCharge)
        .accessibilityLabel("充值")
    }

    /// 余额卡片：大字余额、右边一个蓝色刷新图标，余额下面灰色小字写上次查询时间
    private var balanceCard: some View {        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                balanceValue
                Spacer(minLength: 12)
                chargeButton
                Button {
                    Task { await app.refreshElectricity() }
                } label: {
                    if app.electricityLoading { ProgressView().frame(width: 48, height: 48) }
                    else { ToolbarIcon("arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .disabled(app.electricityLoading)
                .accessibilityLabel("刷新电费")
            }

            if let checked = app.electricityCheckedAt {
                Text("上次查询 \(checked.formatted(date: .abbreviated, time: .shortened))")
                    .font(MD3Type.bodyMedium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// 近几天的每日用量柱状图：余额曲线太平，看不出每天花了多少
    @ViewBuilder
    private var trendChart: some View {
        let points = usagePoints

        if points.isEmpty {
            Text("再攒几天就能看到每天用多少了")
                .font(MD3Type.bodyMedium)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                #if canImport(Charts)
                Chart(points) { point in
                    AreaMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("用量", point.usage)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue.opacity(0.30), .blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("用量", point.usage)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("用量", point.usage)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(26)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text("¥" + String(format: amount < 10 ? "%.1f" : "%.0f", amount))
                            }
                        }
                    }
                }
                .frame(height: 150)

                #else
                ForEach(points) { point in
                    HStack {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(String(format: "¥%.2f", point.usage))
                    }
                }
                #endif

                if let average = averageUsageText(app.electricityTrend()) {
                    Text(average)
                        .font(MD3Type.bodyMedium)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    struct UsagePoint: Identifiable {
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
        return String(format: "平均每天用 ¥%.2f", used / Double(days))
    }

    @ViewBuilder
    private var balanceValue: some View {
        if let balance = app.electricityBalance {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(MD3Type.title)
                    .foregroundStyle(.secondary)
                Text(balance)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(app.isLowBalance ? .orange : .primary)
            }
        } else if app.electricityLoading {
            Text("查询中…")
                .font(MD3Type.title)
                .foregroundStyle(.secondary)
        } else {
            Text("还没查到余额")
                .font(MD3Type.title)
                .foregroundStyle(.secondary)
        }
    }
}

/// 选宿舍：校区只有一个就自动选掉，楼栋和房间各自一页
struct DormPickerView: View {
    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss
    @AppStorage("showDiagnostics") var showDiagnostics = false

    @State var schools: [DormOption] = []
    @State var buildings: [DormOption] = []
    @State var area: DormOption?

    @State var loading = false
    @State var error: String?

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).font(MD3Type.bodyMedium).foregroundStyle(.red)
                    Button("重试") { Task { await loadSchools() } }
                    if showDiagnostics {
                        Button("复制电费诊断数据") {
                            UIPasteboard.general.string = [
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
        .md3List()
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
struct RoomPickerPage: View {
    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss

    let area: DormOption
    let build: DormOption
    let onPick: (DormOption) -> Void

    @State var rooms: [DormOption] = []
    @State var loading = false
    @State var error: String?
    @State var search = ""

    private var filtered: [DormOption] {
        let keyword = search.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return rooms }
        return rooms.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).font(MD3Type.bodyMedium).foregroundStyle(.red)
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
        .md3List()
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
