import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 缴费平台上的一个选项（校区 / 楼栋 / 房间）
struct DormOption: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

/// 用户选好的宿舍，存下来下次直接用
struct DormSelection: Codable, Hashable {
    var areaID: String
    var areaName: String
    var buildID: String
    var buildName: String
    var roomID: String
    var roomName: String

    var displayName: String {
        buildName.isEmpty ? roomName : "\(buildName) \(roomName)"
    }
}

/// 缴费平台上的收费项目
struct PayProject {
    let id: String
    let name: String
    let modelURL: String
    let factoryCode: String
}
