import XCTest

final class TimetableIndexTests: XCTestCase {
    func testIndexedWeeksMatchOriginalFilteringAndBlockMerging() {
        let html = #"new TaskActivity("t","t","1","测试课","r","教3-201","011010"); index = 0*unitCount+2; index = 0*unitCount+3;"#
        let source = TimetableParser.parse(html).occurrences
        let index = TimetableIndex(source)
        for week in 1...30 {
            let expected = source.filter { $0.weeks.contains(week) }
            XCTAssertEqual(index.occurrences[week] ?? [], expected)
            XCTAssertEqual(index.blocks[week] ?? [], expected.courseBlocks())
        }
    }
    func testReplacingSourceDropsOldSemesterAndEmptyWeeks() {
        let html = #"new TaskActivity("t","t","1","测试课","r","教3-201","0100"); index = 0*unitCount+2;"#
        let source = TimetableParser.parse(html).occurrences
        XCTAssertFalse(TimetableIndex(source).blocks.isEmpty)
        XCTAssertTrue(TimetableIndex([]).blocks.isEmpty)
    }
}
