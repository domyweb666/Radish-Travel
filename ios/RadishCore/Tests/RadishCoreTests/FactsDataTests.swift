// 真的那份核對資料（seoul-checked.json）有沒有填錯格式。內容對不對要靠人和 AI 讀官方頁，這裡驗不到。
import XCTest

@testable import RadishCore

final class FactsDataTests: XCTestCase {
    private let file: SeoulChecked = SeoulChecked.shared

    private func isDate(_ s: String) -> Bool {
        return s.count == 10 && addDays(s, 0) == s
    }

    func test地點不重複_都有韓文名_座標在首爾一帶_都有一筆核對結果() {
        var seen: Set<String> = []
        for p in PLACES {
            XCTAssertTrue(seen.insert(p.id).inserted, "重複：\(p.id)")
            XCTAssertFalse(p.kr.isEmpty, "\(p.id) 沒有韓文名")
            XCTAssertTrue(p.lat > 37.1 && p.lat < 38.0, "\(p.id) 緯度 \(p.lat)")
            XCTAssertTrue(p.lng > 126.6 && p.lng < 127.8, "\(p.id) 經度 \(p.lng)")
            XCTAssertNotNil(factOf(p.id), "\(p.id) 沒有核對結果")
            XCTAssertFalse(p.n.contains("挑一間"), p.n)
        }
        for id in file.facts.keys {
            XCTAssertTrue(seen.contains(id), "核對結果對不到地點：\(id)")
        }
    }

    func test每一筆的格式() {
        for (id, f) in file.facts {
            XCTAssertTrue(isDate(f.checked), "\(id) 核對日期 \(f.checked)")
            if f.status != FactStatus.none { XCTAssertFalse(f.src.isEmpty, "\(id) 沒有來源") }
            for s in f.src { XCTAssertTrue(s.url.hasPrefix("http"), "\(id) \(s.url)") }
            for d in f.closed ?? [] { XCTAssertTrue(d >= 0 && d <= 6, "\(id) 星期 \(d)") }
            for key in f.closedOn ?? [] {
                let known: Bool = file.lunar[key] != nil || isDate(key) || isDate("2027-" + key)
                XCTAssertTrue(known, "\(id) closedOn \(key)")
            }
            for o in f.off ?? [] {
                XCTAssertTrue(isDate(o.from), "\(id) off \(o.from)")
                if let to = o.to { XCTAssertTrue(isDate(to) && to >= o.from, "\(id) off \(to)") }
                XCTAssertFalse(o.why.hasSuffix("。"), "\(id) \(o.why)")
            }
            if let b = f.book {
                XCTAssertFalse(b.how.isEmpty, id)
                if let u = b.url { XCTAssertTrue(u.hasPrefix("http"), "\(id) \(u)") }
                if let at = b.opensAt { XCTAssertNotNil(bookMinutes(at), "\(id) \(at)") }
            }
        }
        for d in file.holidays { XCTAssertTrue(isDate(d), d) }
    }

    func test景福宮週二休_昌德宮週一休_國定假日換到隔天() {
        XCTAssertEqual(closedWhy("p0", "2026-12-01"), "每週二休")
        XCTAssertNil(closedWhy("p0", "2026-12-02"))
        XCTAssertEqual(closedWhy("p6", "2026-12-07"), "每週一休")
        // 2027-03-01 是週一也是三一節：照開，改休 3/2
        XCTAssertNil(closedWhy("p6", "2027-03-01"))
        XCTAssertNotNil(closedWhy("p6", "2027-03-02"))
    }

    func test後苑_台灣時間九點開賣() throws {
        let b: BookInfo = try XCTUnwrap(factOf("p6")?.book)
        let open: (on: String, at: String?) = try XCTUnwrap(bookOpen(b, "2026-12-08"))
        XCTAssertEqual(open.on, "2026-12-02")
        XCTAssertEqual(open.at, "10:00")
    }

    func test真的資料排出來_沒有一站排在休館日() {
        for offset in 0..<21 {
            var d: TripDraft = TripDraft(start: addDays("2026-11-26", offset * 5), days: 6, arrive: .am, leave: .eve, people: 2)
            d.city = "seoul"
            let t: Trip = generate(d, defaultSettings())
            // 只提醒不擋的（N 首爾塔 2027 年 1 到 3 月）不算
            XCTAssertEqual(closedNotes(t, caution: { (_: String, _: String) -> String? in nil }), [], d.start)
            XCTAssertFalse(allItems(t).isEmpty, d.start)
        }
    }

    func testKETA跟著出發日() {
        XCTAssertTrue(datedText("c2", "x", "2026-12-31").contains("不用辦"))
        XCTAssertTrue(datedText("c2", "x", "2027-01-01").contains("再查一次"))
    }
}
