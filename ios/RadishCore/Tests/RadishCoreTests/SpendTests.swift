// 照 mobile/tests/spend.test.ts 搬。
import XCTest

@testable import RadishCore

final class SpendTests: XCTestCase {
    private func trip() -> Trip {
        let d: TripDraft = TripDraft(city: "seoul", start: "2026-12-01", days: 4, arrive: .pm, leave: .pm, people: 2)
        return generate(d, defaultSettings())
    }

    func test花費_打的字換成數字_亂打_空的_0_都不算() {
        XCTAssertEqual(parseKrw("12,000"), 12000)
        XCTAssertEqual(parseKrw(""), 0)
        XCTAssertEqual(parseKrw("abc"), 0)
        XCTAssertEqual(parseRate("23.5"), 23.5)
        XCTAssertNil(parseRate(""))
        XCTAssertNil(parseRate("0"))
        XCTAssertNil(parseRate("9999"))
    }

    func test花費_沒填匯率不換台幣_填了照填的算() {
        var t: Trip = trip()
        addSpend(&t, 12000, " 煎餅 ", 2)
        addSpend(&t, 8000, "")
        XCTAssertNil(addSpend(&t, 0, "沒金額"))
        let total: (count: Int, krw: Double, twd: Double?) = spendTotal(t)
        XCTAssertEqual(total.count, 2)
        XCTAssertEqual(total.krw, 20000)
        XCTAssertNil(total.twd)
        XCTAssertNil(toTwd(12000, nil))
        t.rate = 23
        XCTAssertEqual(spendTotal(t).twd, 460)
        let list: [Spend] = t.spend ?? []
        XCTAssertEqual(list.count, 2)
        guard list.count == 2 else { return }
        XCTAssertEqual(list[1].note, "煎餅")
        XCTAssertEqual(list[1].day, 2)
        XCTAssertNil(list[0].note)
    }

    func test花費_刪一筆只少那一筆_重排行程之後紀錄_匯率_機票都還在() {
        var t: Trip = trip()
        t.flight = 12000
        t.rate = 23
        addSpend(&t, 5000, "A")
        let b: Spend? = addSpend(&t, 7000, "B")
        XCTAssertNotNil(b)
        XCTAssertEqual(removeSpend(&t, b?.id ?? "")?.note, "B")
        XCTAssertNil(removeSpend(&t, "nope"))
        XCTAssertEqual(spendTotal(t).krw, 5000)
        // TS：{ ...generate(draftOf(t), defaultSettings()), ...ownOf(t) }
        var again: Trip = generate(draftOf(t), defaultSettings())
        let own: (flight: Double, spend: [Spend]?, rate: Double?) = ownOf(t)
        again.flight = own.flight
        again.spend = own.spend
        again.rate = own.rate
        XCTAssertEqual(again.flight, 12000)
        XCTAssertEqual(again.rate, 23)
        XCTAssertEqual(again.spend?.count, 1)
    }
}
