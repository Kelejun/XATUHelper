import SwiftUI

/// 电费页：没选过宿舍就引导去选，选过就直接显示余额。
struct ElectricityView: View {
    @EnvironmentObject var app: AppState
    @State private var editing = false

    var body: some View {
        Form {
            if let dorm = app.dorm {
                Section {
                    balanceCard
                }

                Section("宿舍") {
                    LabeledContent("房间", value: dorm.displayName)
                    if !dorm.areaName.isEmpty, dorm.areaName != dorm.buildName {
                        LabeledContent("校区", value: dorm.areaName)
                    }
                    Button("换一个宿舍") { editing = true }
                }

                if let error = app.electricityError {
                    Section {
                        Text(error)
                            .font(.footnote)
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
        .navigationTitle("电费")
        .sheet(isPresented: $editing) {
            NavigationStack {
                DormPickerView()
            }
        }
        .task {
            await app.refreshElectricityIfNeeded()
        }
    }

    /// 余额卡片：大字余额、右边一个蓝色刷新图标，余额下面灰色小字写上次查询时间
    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                balanceValue
                Spacer(minLength: 12)
                Button {
                    Task { await app.refreshElectricity() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 34, height: 34)
                        if app.electricityLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(app.electricityLoading)
                .accessibilityLabel("刷新电费")
            }

            if let checked = app.electricityCheckedAt {
                Text("上次查询 \(checked.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var balanceValue: some View {
        if let balance = app.electricityBalance {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(balance)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(app.isLowBalance ? .orange : .primary)
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
                    Button("复制电费诊断数据") {
                        UIPasteboard.general.string = [
                            PayService.lastLogin ?? "(没有登录记录)",
                            PayService.lastRaw ?? "(没有接口返回)",
                            PayService.lastError ?? "(没有错误记录)"
                        ].joined(separator: "\n\n")
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
