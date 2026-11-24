// 照 mobile/tests/trips.test.ts 搬。測 albumHtml、sketchSvg 的那兩條（地圖網頁、路線圖）不在這裡。
import XCTest

@testable import RadishCore

final class TripsTests: XCTestCase {
    private func state() -> AppState {
        var d: AppState = AppState()
        d.settings = defaultSettings()
        let draft: TripDraft = TripDraft(city: "seoul", start: "2026-12-01", days: 5, arrive: .pm, leave: .pm, people: 2)
        d.trip = generate(draft, defaultSettings())
        d.shelf = []
        d.seeds = []
        d.pool = []
        d.checks = ["passport": true, "b_x1": true]
        d.chat = [ChatMsg(r: .me, t: "第 2 天輕鬆一點")]
        d.baskets = []
        d.settingsDirty = false
        d.aiAgreed = []
        d.guideSeen = false
        d.remind = false
        d.debugDay = 2
        return d
    }

    func test開新的一趟_現在這趟原樣放到其他排好的_切回來一樣不少() {
        var d: AppState = state()
        let before: Trip? = d.trip
        XCTAssertNotNil(before)
        shelveCurrent(&d)
        XCTAssertNil(d.trip)
        XCTAssertEqual(d.shelf.count, 1)
        XCTAssertEqual(d.chat, [])
        XCTAssertNil(d.debugDay)
        XCTAssertEqual(d.checks, ["passport": true], "行前檢查表留著，要先訂的勾選跟著那一趟走")

        // 排第二趟，再切回第一趟
        let draft2: TripDraft = TripDraft(city: "seoul", start: "2027-03-10", days: 3, arrive: .am, leave: .eve, people: 1)
        d.trip = generate(draft2, d.settings)
        let second: Trip? = d.trip
        guard let firstId = d.shelf.first?.id else {
            XCTFail("架上應該有一趟")
            return
        }
        openShelved(&d, firstId)
        XCTAssertEqual(d.trip, before)
        XCTAssertEqual(d.chat.count, 1)
        XCTAssertEqual(d.debugDay, 2)
        XCTAssertEqual(d.checks["b_x1"], true)
        XCTAssertEqual(d.shelf.count, 1)
        XCTAssertEqual(d.shelf.first?.trip, second, "第二趟換到架上，沒有不見")
    }

    func test收起來_去過的站帶著位置_第幾天_那一句和照片進去過的旅行() {
        var d: AppState = state()
        guard var trip = d.trip, let first = allItems(trip).first else {
            XCTFail("排不出行程")
            return
        }
        trip.slots[first.si].items[first.ii].status = .pulled
        trip.slots[first.si].items[first.ii].say = "湯很清"
        trip.slots[first.si].items[first.ii].photos = ["p1.jpg"]
        d.trip = trip
        XCTAssertEqual(visitedOf(trip).count, 1)
        archiveTrip(&d)
        XCTAssertNil(d.trip)
        guard let b = d.baskets.first, let item = b.items.first else {
            XCTFail("應該收進去一趟")
            return
        }
        XCTAssertEqual(b.start, "2026-12-01")
        XCTAssertEqual(b.days, 5)
        XCTAssertEqual(item.say, "湯很清")
        XCTAssertEqual(item.photos, ["p1.jpg"])
        XCTAssertEqual(item.day, first.s.day)
        XCTAssertNotNil(item.lat)
    }

    func test收起來之後還可以補一句_加照片_別站不受影響() {
        var d: AppState = state()
        guard var trip = d.trip else {
            XCTFail("排不出行程")
            return
        }
        let stops: [Found] = Array(allItems(trip).prefix(2))
        XCTAssertEqual(stops.count, 2)
        guard stops.count == 2 else { return }
        for x in stops {
            trip.slots[x.si].items[x.ii].status = .pulled
        }
        trip.slots[stops[0].si].items[stops[0].ii].say = "原本那句"
        d.trip = trip
        archiveTrip(&d)
        guard let id = d.baskets.first?.id else {
            XCTFail("應該收進去一趟")
            return
        }
        // TS 是拿到那一站直接改；Swift 的 struct 是複製，改要走 updateBasketItem
        XCTAssertNotNil(basketItem(d, id, 1))
        let changed: BasketItem? = updateBasketItem(&d, id, 1) { (second: inout BasketItem) -> Void in
            second.say = "後來補的"
            second.photos = ["p1.jpg"]
        }
        XCTAssertNotNil(changed)
        XCTAssertEqual(d.baskets[0].items[1].say, "後來補的")
        XCTAssertEqual(d.baskets[0].items[1].photos, ["p1.jpg"])
        XCTAssertEqual(d.baskets[0].items[0].say, "原本那句")
        XCTAssertNil(basketItem(d, id, 99))
        XCTAssertNil(basketItem(d, "沒有這趟", 0))
    }

    func test提醒日_出發前七天_不到七天就明天_明天出發或已經出發就不提醒() {
        XCTAssertEqual(remindOn("2026-12-01", "2026-11-16"), "2026-11-24")
        XCTAssertEqual(remindOn("2026-12-01", "2026-11-27"), "2026-11-28")
        XCTAssertNil(remindOn("2026-12-01", "2026-11-30"))
        XCTAssertNil(remindOn("2026-12-01", "2026-12-02"))
    }

    func test提醒內容_只列還沒打勾的_全部勾完就沒有提醒_其他排好的那幾趟也算() {
        var d: AppState = state()
        guard let trip = d.trip else {
            XCTFail("排不出行程")
            return
        }
        let need: [Stop] = unbookedOf(trip, d.checks)
        XCTAssertTrue(need.count > 0)
        guard let firstNeed = need.first else { return }
        guard let r = remindersOf(d, "2026-11-16").first else {
            XCTFail("應該有一則提醒")
            return
        }
        XCTAssertEqual(r.on, "2026-11-24")
        XCTAssertTrue(r.body.contains("\(need.count) 站"))
        XCTAssertTrue(r.body.contains(firstNeed.n))
        d.checks["b_" + firstNeed.id] = true
        let after: Reminder? = remindersOf(d, "2026-11-16").first
        let stillThere: Bool = after?.body.contains(firstNeed.n) ?? false
        XCTAssertTrue(!stillThere || need.count == 1)
        for x in need {
            d.checks["b_" + x.id] = true
        }
        XCTAssertEqual(remindersOf(d, "2026-11-16").count, 0)
        var e: AppState = state()
        shelveCurrent(&e)
        XCTAssertEqual(remindersOf(e, "2026-11-16").count, 1)
    }

    func test取了名字的一趟_標題用名字_收起來之後名字和封面跟著走() {
        var d: AppState = state()
        guard var trip = d.trip else {
            XCTFail("排不出行程")
            return
        }
        XCTAssertEqual(tripTitle(trip), "首爾 5 天")
        trip.name = "跟媽媽的首爾"
        trip.cover = "c1.jpg"
        XCTAssertEqual(tripTitle(trip), "跟媽媽的首爾")
        guard let first = allItems(trip).first else {
            XCTFail("行程是空的")
            return
        }
        trip.slots[first.si].items[first.ii].status = .pulled
        d.trip = trip
        archiveTrip(&d)
        guard let b = d.baskets.first else {
            XCTFail("應該收進去一趟")
            return
        }
        XCTAssertTrue(b.title.hasPrefix("跟媽媽的首爾"))
        XCTAssertEqual(b.cover, "c1.jpg")
    }
}
