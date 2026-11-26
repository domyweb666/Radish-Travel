// 月曆選區間（QC-0013 #104）：第一下出發日、第二下回來那天，存的還是出發日＋天數。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class DateRangeTests: XCTestCase {
    func test第一下是出發日_第二下是回來那天_天數含頭尾() {
        let one: RangePick = pickRange(nil, nil, tapped: "2026-12-01")
        XCTAssertEqual(one, RangePick(start: "2026-12-01", days: nil, note: nil))
        XCTAssertEqual(rangeStep(one.start, one.days), .end)
        let two: RangePick = pickRange(one.start, one.days, tapped: "2026-12-08")
        XCTAssertEqual(two, RangePick(start: "2026-12-01", days: 8, note: nil))
        XCTAssertEqual(rangeStep(two.start, two.days), .start)
        XCTAssertEqual(rangeEnd(two.start, two.days), "2026-12-08")
    }

    func test兩端都選好了再點一下_從出發日重選() {
        let again: RangePick = pickRange("2026-12-01", 8, tapped: "2026-12-05")
        XCTAssertEqual(again, RangePick(start: "2026-12-05", days: nil, note: nil))
        // 點比原本出發日早的也一樣是新的出發日
        let earlier: RangePick = pickRange("2026-12-01", 8, tapped: "2026-11-28")
        XCTAssertEqual(earlier, RangePick(start: "2026-11-28", days: nil, note: nil))
    }

    func test等回來那天時點到比出發日早的_當新的出發日() {
        let r: RangePick = pickRange("2026-12-10", nil, tapped: "2026-12-03")
        XCTAssertEqual(r, RangePick(start: "2026-12-03", days: nil, note: nil))
    }

    func test太近的不收_講最早哪天回來() {
        for tapped in ["2026-12-01", "2026-12-02"] {
            let r: RangePick = pickRange("2026-12-01", nil, tapped: tapped)
            XCTAssertEqual(r.start, "2026-12-01")
            XCTAssertNil(r.days)
            XCTAssertEqual(r.note, "最少去 3 天，回來那天最早是 12/3（四）。")
        }
        XCTAssertEqual(pickRange("2026-12-01", nil, tapped: "2026-12-03").days, 3)
    }

    func test太遠的不收_講最晚哪天回來() {
        XCTAssertEqual(pickRange("2026-12-01", nil, tapped: "2026-12-14").days, 14)
        let r: RangePick = pickRange("2026-12-01", nil, tapped: "2026-12-15")
        XCTAssertEqual(r.start, "2026-12-01")
        XCTAssertNil(r.days)
        XCTAssertEqual(r.note, "最多去 14 天，回來那天最晚是 12/14（一）。")
    }

    func test跨月跨年_天數照日子算() {
        XCTAssertEqual(pickRange("2026-11-28", nil, tapped: "2026-12-04").days, 7)
        XCTAssertEqual(pickRange("2026-12-29", nil, tapped: "2027-01-05").days, 8)
        XCTAssertEqual(rangeEnd("2026-12-29", 8), "2027-01-05")
        XCTAssertEqual(rangeReach("2026-12-29"), "2026-12-31"..."2027-01-11")
    }

    func test上面那一行() {
        XCTAssertEqual(rangeLine(nil, nil), "點出發那天")
        XCTAssertEqual(rangeLine("2026-12-01", nil), "12/1（二）出發・再點回來那天")
        XCTAssertEqual(rangeLine("2026-12-01", 8), "12/1（二）出發・12/8（二）回來・共 8 天")
    }
}
