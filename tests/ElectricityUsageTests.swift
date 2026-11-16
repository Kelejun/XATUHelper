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
        print("Passed \(count) electricity usage checks")
    }
}
