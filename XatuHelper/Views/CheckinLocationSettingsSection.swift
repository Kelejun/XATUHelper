import MapKit
import SwiftUI

struct CheckinLocationSettingsSection: View {
    @AppStorage(CheckinLocationSettings.enabledKey) private var enabled = false
    @AppStorage(CheckinLocationSettings.coordinateKey) private var coordinateData = Data()

    private var coordinate: CheckinLocationSettings.Coordinate? {
        CheckinLocationSettings.Coordinate.decode(coordinateData)
    }

    var body: some View {
        Section {
            Toggle("传入定位", isOn: $enabled)
                .disabled(coordinate == nil)
            NavigationLink {
                CheckinLocationPicker(coordinate: coordinate) { selection in
                    guard let data = try? JSONEncoder().encode(selection) else { return }
                    coordinateData = data
                }
            } label: {
                LabeledContent("选择位置", value: coordinate.map {
                    String(format: "%.6f, %.6f", $0.latitude, $0.longitude)
                } ?? "未选择")
            }
        } header: {
            Text("签到测试")
        } footer: {
            Text("先选择位置，再开启传入定位。开启后，签到网页使用所选坐标；关闭后恢复实际定位。所选坐标会保存在本机。")
        }
    }
}

private struct CheckinLocationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition
    @State private var latitude: String
    @State private var longitude: String
    @State private var system: CheckinLocationSettings.Coordinate.System
    @State private var hasMapInteraction = false
    let onSave: (CheckinLocationSettings.Coordinate) -> Void

    init(coordinate: CheckinLocationSettings.Coordinate?, onSave: @escaping (CheckinLocationSettings.Coordinate) -> Void) {
        let initial = coordinate ?? .init(latitude: 34.383, longitude: 108.981)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: initial.mapCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
        _latitude = State(initialValue: String(format: "%.6f", initial.latitude))
        _longitude = State(initialValue: String(format: "%.6f", initial.longitude))
        _system = State(initialValue: initial.system)
        self.onSave = onSave
    }

    private var selection: CheckinLocationSettings.Coordinate? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lng = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let value = CheckinLocationSettings.Coordinate(latitude: lat, longitude: lng, system: system)
        return value.isValid ? value : nil
    }

    var body: some View {
        Form {
            Section {
                Map(position: $camera)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.red)
                            .allowsHitTesting(false)
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        guard hasMapInteraction else { return }
                        latitude = String(format: "%.6f", context.region.center.latitude)
                        longitude = String(format: "%.6f", context.region.center.longitude)
                        system = .gcj02
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in hasMapInteraction = true })
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("移动地图，将十字中心对准要传入的位置；也可以直接输入经纬度。")
            }
            Section {
                Picker("坐标系", selection: $system) {
                    ForEach(CheckinLocationSettings.Coordinate.System.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                TextField("纬度（-90～90）", text: $latitude)
                TextField("经度（-180～180）", text: $longitude)
                if selection == nil {
                    Text("请输入有效的经纬度。")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("坐标")
            } footer: {
                Text("地图选点使用 GCJ02；若手动输入 GPS 坐标，请选择 WGS84。传给网页前会统一为 GPS 坐标，由网页地图转换为显示坐标。")
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .navigationTitle("选择签到位置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard let selection else { return }
                    onSave(selection)
                    dismiss()
                }
                .disabled(selection == nil)
            }
        }
    }
}
