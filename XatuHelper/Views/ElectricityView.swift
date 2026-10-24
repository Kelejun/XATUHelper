import SwiftUI

/// 电费页：没选过宿舍就引导去选，选过就直接显示余额。
struct ElectricityView: View {
    @EnvironmentObject var app: AppState
    @State private var editing = false

    var body: some View {
        Form {
            if let dorm = app.dorm {
                Section("宿舍") {
                    LabeledContent("房间", value: dorm.displayName)
                    if !dorm.areaName.isEmpty, dorm.areaName != dorm.buildName {
                        LabeledContent("校区", value: dorm.areaName)
                    }
                    Button("换一个宿舍") { editing = true }
                }

                Section("剩余电费") {
                    balanceRow
                }

                Section {
                    Button {
                        Task { await app.refreshElectricity() }
                    } label: {
                        HStack {
                            Text("刷新")
                            if app.electricityLoading {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(app.electricityLoading)

                    if let checked = app.electricityCheckedAt {
                        LabeledContent("上次查询", value: checked.formatted(date: .abbreviated, time: .shortened))
                    }
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

    @ViewBuilder
    private var balanceRow: some View {
        if let balance = app.electricityBalance {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(balance)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(app.isLowBalance ? .orange : .primary)
                Spacer()
            }
            .padding(.vertical, 4)
        } else if app.electricityLoading {
            HStack {
                Text("查询中…").foregroundStyle(.secondary)
                Spacer()
                ProgressView()
            }
        } else {
            Button("查询余额") {
                Task { await app.refreshElectricity() }
            }
        }
    }
}

/// 三级选择：校区 → 楼栋 → 房间
struct DormPickerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var schools: [DormOption] = []
    @State private var buildings: [DormOption] = []
    @State private var rooms: [DormOption] = []

    @State private var area: DormOption?
    @State private var build: DormOption?
    @State private var room: DormOption?

    @State private var loading = false
    @State private var error: String?
    @State private var search = ""

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

            Section("校区") {
                if loading && schools.isEmpty {
                    ProgressView()
                }
                ForEach(schools) { option in
                    row(option, selected: area == option) {
                        area = option
                        build = nil
                        room = nil
                        buildings = []
                        rooms = []
                        Task { await loadBuildings(area: option) }
                    }
                }
            }

            if let area {
                Section("楼栋") {
                    if loading && buildings.isEmpty { ProgressView() }
                    ForEach(buildings) { option in
                        row(option, selected: build == option) {
                            build = option
                            room = nil
                            rooms = []
                            Task { await loadRooms(area: area, build: option) }
                        }
                    }
                }
            }

            if let area, let build {
                Section("房间") {
                    if loading && rooms.isEmpty { ProgressView() }
                    ForEach(filteredRooms) { option in
                        row(option, selected: room == option) {
                            room = option
                        }
                    }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜房间号")
        .navigationTitle("选择宿舍")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(room == nil)
            }
        }
        .task { await loadSchools() }
    }

    private var filteredRooms: [DormOption] {
        let keyword = search.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return rooms }
        return rooms.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    private func row(_ option: DormOption, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(option.name).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }

    private func loadSchools() async {
        loading = true
        error = nil
        do {
            schools = try await app.loadSchools()
            if let first = schools.first, area == nil {
                area = first
                await loadBuildings(area: first)
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

    private func loadRooms(area: DormOption, build: DormOption) async {
        loading = true
        do {
            rooms = try await app.loadRooms(areaID: area.id, buildID: build.id)
        } catch {
            self.error = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func save() {
        guard let area, let build, let room else { return }
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

#Preview {
    NavigationStack {
        ElectricityView().environmentObject(AppState())
    }
}
