// QC-0013 一站頁那三筆：建議停留（#96）、照片跟著站走（#96、#100）、在這裡花的（#106）。mobile/ 沒有對應的 TS。
import XCTest

@testable import RadishCore

final class StopQCTests: XCTestCase {
    private func trip() -> Trip {
        let d: TripDraft = TripDraft(city: "seoul", start: "2026-12-01", days: 4, arrive: .pm, leave: .pm, people: 2)
        return generate(d, defaultSettings())
    }

    private func place(_ id: String) throws -> Place {
        return try XCTUnwrap(PLACES.first(where: { (p: Place) -> Bool in p.id == id }), "首爾資料包裡沒有 \(id)")
    }

    /* ---------- 建議停留 ---------- */

    func test建議停留_大站小站_種類_圖示() throws {
        XCTAssertEqual(suggestedStay(try place("p0")), "約 2 到 3 小時")  // 景福宮
        XCTAssertEqual(suggestedStay(try place("p38")), "約 1 小時")  // 漢江遊船
        XCTAssertEqual(suggestedStay(try place("p9")), "約 1 到 2 小時")  // 廣藏市場
        let far: String = suggestedStay(try place("p50"))  // 愛寶樂園
        XCTAssertTrue(far.hasPrefix("約 5 小時以上"), far)
        XCTAssertTrue(far.hasSuffix("來回車程另外算"), far)
    }

    func test建議停留_每個地點都有_都寫約() {
        for p in PLACES {
            XCTAssertTrue(suggestedStay(p).hasPrefix("約 "), "\(p.n)：\(suggestedStay(p))")
        }
    }

    func test建議停留_自己加的站不估_AI加的照樣估() throws {
        var mine: Stop = planToStop(try place("p0"), "")
        mine.mine = true
        XCTAssertNil(suggestedStay(mine))
        var ai: Stop = planToStop(try place("p0"), "")
        ai.ai = true
        XCTAssertEqual(suggestedStay(ai), "約 2 到 3 小時")
    }

    /* ---------- 照片 ---------- */

    func test照片_重排之後同一個地點的照片還在() throws {
        var t: Trip = trip()
        let first: Found = try XCTUnwrap(allItems(t).first)
        t.slots[first.si].items[first.ii].photos = ["pabc.jpg"]
        let again: Trip = replanTrip(t, draftOf(t), defaultSettings())
        if let same = findItem(again, first.it.id) {
            XCTAssertEqual(same.it.photos, ["pabc.jpg"])
        }
        // 別的站不會多出照片
        let others: [Found] = allItems(again).filter { (x: Found) -> Bool in x.it.id != first.it.id }
        for x in others {
            XCTAssertNil(x.it.photos, x.it.n)
        }
    }

    /* ---------- 在這裡花的 ---------- */

    func test花費_舊檔沒有站和幣別也解得開_當成韓元() throws {
        let old: String = #"{"id":"s1","krw":12000,"note":"煎餅","day":2}"#
        let x: Spend = try JSONDecoder().decode(Spend.self, from: Data(old.utf8))
        XCTAssertEqual(x.krw, 12000)
        XCTAssertNil(x.stopId)
        XCTAssertNil(x.stopName)
        XCTAssertNil(x.twd)
        XCTAssertEqual(x.cur, .krw)
        XCTAssertEqual(x.amount, 12000)
        XCTAssertEqual(spendAmountText(x), "₩ 12,000")
    }

    func test花費_台幣那一筆存了再讀回來還是台幣() throws {
        var t: Trip = trip()
        addSpend(&t, 300, "紀念品", 1, cur: .twd, stopId: "p0", stopName: "景福宮")
        let data: Data = try JSONEncoder().encode(t)
        let back: Trip = try JSONDecoder().decode(Trip.self, from: data)
        let x: Spend = try XCTUnwrap(back.spend?.first)
        XCTAssertEqual(x.cur, .twd)
        XCTAssertEqual(x.krw, 0)
        XCTAssertEqual(x.twd, 300)
        XCTAssertEqual(x.stopId, "p0")
        XCTAssertEqual(x.stopName, "景福宮")
        XCTAssertEqual(spendAmountText(x), "NT$ 300")
    }

    func test花費_一站記好幾筆_只算這一站的_金額0不記() {
        var t: Trip = trip()
        addSpend(&t, 12000, "門票", 2, stopId: "p0", stopName: "景福宮")
        addSpend(&t, 300, "", 2, cur: .twd, stopId: "p0", stopName: "景福宮")
        addSpend(&t, 8000, "別的地方", 2, stopId: "p9", stopName: "廣藏市場")
        addSpend(&t, 5000, "花費頁記的")
        XCTAssertNil(addSpend(&t, 0, "沒金額", 2, stopId: "p0"))
        let here: [Spend] = stopSpends(t, "p0")
        XCTAssertEqual(here.count, 2)
        // 新的在上面
        XCTAssertEqual(here.first?.cur, .twd)
        XCTAssertNil(here.first?.note)
        XCTAssertEqual(stopSpends(t, "p9").count, 1)
        XCTAssertEqual(stopSpends(t, "nope").count, 0)
        XCTAssertEqual(t.spend?.count, 4)
    }

    func test花費_混幣別合計_台幣不當韓元加_沒匯率不合起來() {
        var t: Trip = trip()
        addSpend(&t, 12000, "門票", 2, stopId: "p0")
        addSpend(&t, 300, "紀念品", 2, cur: .twd, stopId: "p0")
        addSpend(&t, 8000, "花費頁記的")
        // 整趟（花費頁）連一站頁記的一起算；krw 只有韓元那兩筆
        let total: (count: Int, krw: Double, twd: Double?) = spendTotal(t)
        XCTAssertEqual(total.count, 3)
        XCTAssertEqual(total.krw, 20000)
        XCTAssertNil(total.twd)
        let sum: SpendSum = spendSum(t.spend ?? [], t.rate)
        XCTAssertEqual(sum.ntd, 300)
        XCTAssertTrue(spendNeedsRate(sum))
        XCTAssertEqual(spendSumText(sum), "3 筆，₩ 20,000 和 NT$ 300")
        // 填了匯率：韓元換成台幣，再加台幣那一筆
        t.rate = 23
        let withRate: SpendSum = spendSum(t.spend ?? [], t.rate)
        XCTAssertEqual(withRate.twd, 760)
        XCTAssertFalse(spendNeedsRate(withRate))
        XCTAssertEqual(spendTotal(t).twd, 760)
        XCTAssertEqual(spendSumText(withRate), "3 筆，₩ 20,000 和 NT$ 300，合起來約 NT$ 760（照你填的匯率算）")
    }

    func test花費_只有台幣不用匯率_只有韓元照舊() {
        var t: Trip = trip()
        addSpend(&t, 300, "紀念品", 1, cur: .twd, stopId: "p0")
        let onlyTwd: SpendSum = spendSum(t.spend ?? [], nil)
        XCTAssertEqual(onlyTwd.twd, 300)
        XCTAssertFalse(spendNeedsRate(onlyTwd))
        XCTAssertEqual(spendSumText(onlyTwd), "1 筆，一共 NT$ 300")

        var k: Trip = trip()
        addSpend(&k, 12000, "門票", 1, stopId: "p0")
        XCTAssertEqual(spendSumText(spendSum(k.spend ?? [], nil)), "1 筆，一共 ₩ 12,000")
        XCTAssertEqual(spendSumText(spendSum(k.spend ?? [], 23)), "1 筆，一共 ₩ 12,000，約 NT$ 276（照你填的匯率算）")
        // 一筆都沒有：跟原本一樣，有匯率是 0、沒有是 nil
        XCTAssertNil(spendSum([], nil).twd)
        XCTAssertEqual(spendSum([], 23).twd, 0)
    }

    func test花費_一筆換算_台幣那筆不換_沒匯率不猜() {
        var t: Trip = trip()
        let krw: Spend? = addSpend(&t, 12000, "門票", 1, stopId: "p0")
        let twd: Spend? = addSpend(&t, 300, "紀念品", 1, cur: .twd, stopId: "p0")
        guard let krw, let twd else { return XCTFail("沒記進去") }
        XCTAssertEqual(spendTwdText(krw, 23), "約 NT$ 276")
        XCTAssertNil(spendTwdText(krw, nil))
        XCTAssertNil(spendTwdText(twd, 23))
    }

    func test花費_刪一筆_站名找不到就用記的時候的() throws {
        var t: Trip = trip()
        let first: Found = try XCTUnwrap(allItems(t).first)
        let x: Spend? = addSpend(&t, 12000, "門票", 1, stopId: first.it.id, stopName: "舊名字")
        let y: Spend = try XCTUnwrap(x)
        XCTAssertEqual(spendPlaceName(t, y), first.it.n)
        let gone: Spend = Spend(id: "s9", krw: 100, stopId: "nope", stopName: "拿掉的那站")
        XCTAssertEqual(spendPlaceName(t, gone), "拿掉的那站")
        XCTAssertNil(spendPlaceName(t, Spend(id: "s8", krw: 100)))
        XCTAssertEqual(removeSpend(&t, y.id)?.note, "門票")
        XCTAssertEqual(stopSpends(t, first.it.id).count, 0)
    }
}
