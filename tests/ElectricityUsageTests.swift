import Foundation

@main
struct ElectricityUsageTests {
    static func main() {
        var count = 0
        func check(_ value: Bool, _ name: String) {
            precondition(value, name)
            count += 1
        }
        func record(_ day: Int, _ balance: Double) -> ElectricityRecord {
            .init(day: String(format: "2026-11-%02d", day), balance: balance)
        }
        func points(_ records: [ElectricityRecord]) -> [ElectricityUsagePoint] {
            ElectricityUsagePoint.make(history: records, from: record(2, 0).date, through: record(6, 0).date)
        }
        let history = [record(1, 20), record(2, 16), record(3, 50), record(4, 42)]
        let result = points(history)
        check(result.count == 3, "consecutive days retained")
        check(result.map(\.usage) == [4, 6, 8], "recharge uses mean of measured days")
        check(result.map(\.hasRecharge) == [false, true, false], "recharge identified")
        check(points(history.reversed()).map(\.usage) == result.map(\.usage), "input order independent")
        let onlyRecharge = points([record(1, 10), record(2, 30), record(3, 40)])
        check(onlyRecharge.allSatisfy { $0.usage == nil && $0.hasRecharge }, "no fabricated zero without measured days")
        check(points([record(1, 10), record(2, 10), record(3, 30)]).map(\.usage) == [0, 0], "real zero consumption is a valid average")
        check(points([record(1, 10), record(3, 5)]).map(\.usage) == [2.5, 2.5], "gap consumption averaged across every day")
        check(points([record(1, 100), record(2, 96), record(6, 60), record(7, 20)]).map(\.usage) == [4, 9, 9, 9, 9], "gap averaged and future record excluded")
        check(points([]).isEmpty && points([record(2, 20)]).isEmpty, "insufficient history")
        check(points([record(1, 20), record(2, 16), record(3, 50), record(4, 70), record(5, 62)]).map(\.usage) == [4, 6, 6, 8], "multiple recharges do not dilute mean")
        let gapRecharge = points([record(1, 20), record(2, 16), record(5, 50)])
        check(gapRecharge.map(\.usage) == [4, 4, 4, 4], "recharge interval filled with measured average")
        check(gapRecharge.map(\.hasRecharge) == [false, false, false, true], "recharge marked on query day only")
        let boundary = ElectricityUsagePoint.make(history: [record(1, 20), record(5, 8)],
                                                  from: record(3, 0).date, through: record(6, 0).date)
        check(boundary.map(\.usage) == [3, 3, 3], "interval clipped to visible range after averaging")

        // 16 公寓 (E051) 与普通公寓 (E017) 模型及向后兼容回归检查
        let legacyJSON = #"{"areaID":"1","areaName":"未央校区","buildID":"9","buildName":"9号公寓","roomID":"320","roomName":"320"}"#
        let legacyDorm = try! JSONDecoder().decode(DormSelection.self, from: Data(legacyJSON.utf8))
        check(legacyDorm.projectID == nil && !legacyDorm.usesNestedJsonData, "legacy dorm decodes without project fields")
        check(legacyDorm.balanceUnit == "度" && legacyDorm.balanceLabel == "剩余电量", "legacy dorm defaults to kWh unit")

        let b16Dorm = DormSelection(
            projectID: "68e3d0aff9a04590a1e3e871d9cd9b26",
            projectName: "16公寓电费充值",
            factoryCode: "E051",
            areaID: "1",
            areaName: "西安工业大学",
            buildID: "B1",
            buildName: "B1-16#公寓",
            roomID: "H101",
            roomName: "1-101"
        )
        check(b16Dorm.usesNestedJsonData && b16Dorm.isAmountBalance, "E051 uses nested jsonData and amount balance")
        check(b16Dorm.balanceUnit == "元" && b16Dorm.balanceLabel == "剩余金额", "E051 displays yuan and amount label")
        check(b16Dorm.lowBalanceNotice == "余额偏低，请及时充值", "E051 uses amount low-balance wording")

        let e017Project = PayProject(id: "p1", name: "电费充值", modelURL: "electric", factoryCode: "E017")
        let e051Project = PayProject(id: "p2", name: "16公寓电费充值", modelURL: "electric", factoryCode: "E051")
        check(!e017Project.usesNestedJsonData && e051Project.usesNestedJsonData, "project factoryCode routing")

        var widgetSnap = WidgetSnapshot.empty
        check(widgetSnap.resolvedBalanceUnit == "度" && !widgetSnap.isAmountBalance, "widget snapshot defaults to kWh")
        widgetSnap.balanceUnit = "元"
        check(widgetSnap.resolvedBalanceUnit == "元" && widgetSnap.isAmountBalance, "widget snapshot supports yuan")
        check(widgetSnap.electricityWidgetTitle == "宿舍电费" && widgetSnap.electricityAvailableHint == "剩余可用金额", "widget snapshot uses amount copy")

        var watchSnap = WatchSnapshot.empty
        check(watchSnap.resolvedBalanceUnit == "度" && watchSnap.electricityBalanceLabel == "剩余电量", "watch snapshot defaults to kWh")
        watchSnap.balanceUnit = "元"
        check(watchSnap.resolvedBalanceUnit == "元" && watchSnap.electricityBalanceLabel == "剩余金额", "watch snapshot supports yuan")

        print("Passed \(count) electricity usage checks")
    }
}
