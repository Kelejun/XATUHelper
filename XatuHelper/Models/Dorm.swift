import Foundation

/// 缴费平台上的一个选项（校区 / 楼栋 / 房间）
struct DormOption: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

/// 用户选好的宿舍，存下来下次直接用
struct DormSelection: Codable, Hashable {
    var projectID: String? = nil
    var projectName: String? = nil
    var factoryCode: String? = nil
    var areaID: String
    var areaName: String
    var buildID: String
    var buildName: String
    var roomID: String
    var roomName: String

    var usesNestedJsonData: Bool {
        Self.usesNestedJsonData(factoryCode: factoryCode)
    }

    var isAmountBalance: Bool {
        usesNestedJsonData
    }

    var balanceUnit: String {
        isAmountBalance ? "元" : "度"
    }

    var balanceLabel: String {
        isAmountBalance ? "剩余金额" : "剩余电量"
    }

    var lowBalanceNotice: String {
        isAmountBalance ? "余额偏低，请及时充值" : "电量偏低，请及时充值"
    }

    var displayName: String {
        buildName.isEmpty ? roomName : "\(buildName) \(roomName)"
    }

    static func usesNestedJsonData(factoryCode: String?) -> Bool {
        factoryCode?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("E051") == .orderedSame
    }
}

/// 缴费平台上的收费项目
struct PayProject: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let modelURL: String
    let factoryCode: String

    var usesNestedJsonData: Bool {
        DormSelection.usesNestedJsonData(factoryCode: factoryCode)
    }
}

/// 选宿舍页按电费入口/校区分组的楼栋列表
struct DormBuildingSection: Identifiable, Hashable {
    let project: PayProject
    let area: DormOption
    let buildings: [DormOption]

    var id: String { "\(project.id)|\(area.id)" }
}
