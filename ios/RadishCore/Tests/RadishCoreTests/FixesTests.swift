// 2026-11-24 code review 修的幾條：排回這趟不重複、過了的時段不放、調整改了就不算同一版、切趟不帶走別趟的打勾。
// iOS 版才有，mobile/tests/ 沒有對應的。
import XCTest

@testable import RadishCore

private func fixStop(_ id: String, _ name: String, booking: Bool = false) -> Stop {
    var it: Stop = Stop(
        id: id, n: name, kr: "", a: nil, s: .S, c: .sight, lat: nil, lng: nil,
        status: .kept, swaps: 0, why: "測試"
    )
    if booking { it.b = true }
    return it
}

/// 空的五天：第 1 天上午、第 5 天晚上在路上
private func fixTrip() -> Trip {
    var slots: [Slot] = []
    for day in 1...5 {
        for part in PARTS {
            let off: Bool = (day == 1 && part == .am) || (day == 5 && part == .eve)
            slots.append(Slot(day: day, part: part, off: off ? true : nil, items: []))
        }
    }
    return Trip(start: "2026-12-01", days: 5, arrive: .pm, leave: .pm, people: 2, slots: slots)
}

private func fixPut(_ t: inout Trip, _ day: Int, _ part: Part, _ it: Stop) {
    guard let si = slotAt(t, day, part) else {
        XCTFail("第 \(day) 天沒有這個時段")
        return
    }
    t.slots[si].items.append(it)
}

private func fixSeed(_ it: Stop, _ day: Int, _ part: Part) -> Seed {
    return Seed(id: "s-" + it.id, n: it.n, a: "明洞", why: "測試", stop: it, from: SeedFrom(day: day, part: part))
}

private func fixNow(_ day: Int, _ part: Part) -> TripNow {
    return TripNow(day: day, part: part, clock: "14:00")
}

final class FixesTests: XCTestCase {
    /* ---------- 1 排回這趟 ---------- */

    func test排回這趟_這趟已經有同一站就不加_下次再來留著() throws {
        var t: Trip = fixTrip()
        let it: Stop = fixStop("p1", "景福宮")
        fixPut(&t, 2, .am, it)
        var seeds: [Seed] = [fixSeed(it, 3, .pm)]
        let before: Trip = t
        let msg: String = restoreSeed(&t, &seeds, "s-p1")
        XCTAssertEqual(t, before, "行程不動")
        XCTAssertEqual(seeds.count, 1, "下次再來那一筆不會不見")
        XCTAssertTrue(msg.contains("已經排在這趟第 2 天上午"), msg)
    }

    func test排回這趟_沒有重複的照樣放回原本的時段() throws {
        var t: Trip = fixTrip()
        fixPut(&t, 2, .am, fixStop("p1", "景福宮"))
        var seeds: [Seed] = [fixSeed(fixStop("p2", "昌德宮"), 3, .pm)]
        let msg: String = restoreSeed(&t, &seeds, "s-p2")
        let x: Found = try XCTUnwrap(findItem(t, "p2"))
        XCTAssertEqual(x.s.day, 3)
        XCTAssertEqual(x.s.part, .pm)
        XCTAssertEqual(seeds.count, 0)
        XCTAssertTrue(msg.contains("排回第 3 天下午"), msg)
    }

    /* ---------- 2 過了的時段不放 ---------- */

    func test自己加一站_旅途中不排進過了的時段() throws {
        var t: Trip = fixTrip()
        var seeds: [Seed] = []
        let now: TripNow = fixNow(4, .pm)
        let msg: String = addOwn(&t, &seeds, "那家店", nil, now)
        let x: Found = try XCTUnwrap(allItems(t).first)
        XCTAssertFalse(slotPast(now, x.s.day, x.s.part), msg)
        XCTAssertEqual(x.s.day, 4)
        XCTAssertEqual(x.s.part, .pm)
    }

    func test自己加一站_有講第幾天就排那一天最空的白天() throws {
        var t: Trip = fixTrip()
        fixPut(&t, 3, .am, fixStop("p1", "景福宮"))
        var seeds: [Seed] = []
        let msg: String = addOwn(&t, &seeds, "那家店", 3, nil)
        XCTAssertEqual(msg, "「那家店」排在第 3 天下午")
        // 最後一天平常會跳過，講了就排那天
        let last: String = addOwn(&t, &seeds, "另一家店", 5, nil)
        XCTAssertEqual(last, "「另一家店」排在第 5 天上午")
    }

    func test自己加一站_那天白天過了就晚上_整天過了就排別天並講清楚() throws {
        var t: Trip = fixTrip()
        var seeds: [Seed] = []
        let night: String = addOwn(&t, &seeds, "宵夜", 4, fixNow(4, .eve))
        XCTAssertEqual(night, "「宵夜」排在第 4 天晚上")
        let other: String = addOwn(&t, &seeds, "那家店", 2, fixNow(4, .am))
        XCTAssertTrue(other.hasPrefix("第 2 天沒有能排的時段了"), other)
        let x: Found = try XCTUnwrap(allItems(t).first { (f: Found) -> Bool in f.it.n == "那家店" })
        XCTAssertFalse(slotPast(fixNow(4, .am), x.s.day, x.s.part))
        XCTAssertEqual(seeds.count, 0)
    }

    func test自己加一站_能排的都過了就放下次再來_不硬塞() throws {
        var t: Trip = fixTrip()
        var seeds: [Seed] = []
        let msg: String = addOwn(&t, &seeds, "那家店", 5, fixNow(5, .eve))
        XCTAssertEqual(allItems(t).count, 0)
        XCTAssertEqual(seeds.count, 1)
        XCTAssertTrue(msg.contains("都過了"), msg)
    }

    func test排回這趟_原本的時段過了就改排_現在的時段不算過() throws {
        var t: Trip = fixTrip()
        var seeds: [Seed] = [fixSeed(fixStop("p1", "景福宮"), 2, .am), fixSeed(fixStop("p2", "昌德宮"), 4, .pm)]
        let now: TripNow = fixNow(4, .pm)
        let moved: String = restoreSeed(&t, &seeds, "s-p1", now)
        XCTAssertTrue(moved.hasPrefix("第 2 天上午已經過了"), moved)
        let a: Found = try XCTUnwrap(findItem(t, "p1"))
        XCTAssertFalse(slotPast(now, a.s.day, a.s.part))
        let kept: String = restoreSeed(&t, &seeds, "s-p2", now)
        XCTAssertTrue(kept.contains("排回第 4 天下午"), kept)
        XCTAssertEqual(seeds.count, 0)
    }

    func test排回這趟_能排的都過了就留在下次再來() throws {
        var t: Trip = fixTrip()
        var seeds: [Seed] = [fixSeed(fixStop("p1", "景福宮"), 2, .am)]
        let msg: String = restoreSeed(&t, &seeds, "s-p1", fixNow(5, .eve))
        XCTAssertEqual(allItems(t).count, 0)
        XCTAssertEqual(seeds.count, 1)
        XCTAssertTrue(msg.contains("都過了"), msg)
    }

    /* ---------- 3 這一版的樣子要算調整 ---------- */

    func test排好之後才加調整_就不是同一版_拿掉又對得上() throws {
        var t: Trip = generate(
            TripDraft(city: "seoul", start: "2026-12-01", days: 5, arrive: .pm, leave: .pm, people: 2),
            defaultSettings())
        let mark: String = planMarkOf(t)
        XCTAssertNil(setTweak(&t, "easy", true))
        XCTAssertNotEqual(planMarkOf(t), mark)
        XCTAssertNil(setTweak(&t, "easy", false))
        XCTAssertEqual(planMarkOf(t), mark)
        t.tweaks = []
        XCTAssertEqual(planMarkOf(t), mark, "空的跟沒有一樣")
    }

    func test調整的順序不同_算同一版() throws {
        var a: Trip = fixTrip()
        var b: Trip = fixTrip()
        a.tweaks = [.easy, .elder]
        b.tweaks = [.elder, .easy]
        XCTAssertEqual(planMarkOf(a), planMarkOf(b))
    }

    func test沒有調整時跟舊的算法一樣_舊存檔對得上() throws {
        var t: Trip = Trip(
            start: "2026-12-01", days: 1, arrive: .am, leave: .eve, people: 1,
            slots: [Slot(day: 1, part: .am, items: [fixStop("p1", "景福宮")])])
        // 照舊的算法（沒有調整那一段）在別處算好的
        XCTAssertEqual(planMarkOf(t), "w39stc7s9lha")
        t.tweaks = [.easy]
        XCTAssertEqual(planMarkOf(t), "2zd3e7ekyac35")
    }

    /* ---------- 5 要先訂的打勾跟著自己那一趟 ---------- */

    /// 現在這趟 A，架上一趟 B；兩趟都有同一站 p1（要先訂），A 訂了、B 還沒
    private func twoTrips() -> AppState {
        var a: Trip = fixTrip()
        fixPut(&a, 2, .am, fixStop("p1", "景福宮", booking: true))
        a.name = "A"
        var b: Trip = fixTrip()
        fixPut(&b, 3, .am, fixStop("p1", "景福宮", booking: true))
        fixPut(&b, 3, .pm, fixStop("p2", "昌德宮", booking: true))
        b.name = "B"
        var d: AppState = AppState()
        d.trip = b
        d.checks = ["passport": true, "b_p2": true]
        shelveCurrent(&d)
        d.trip = a
        d.checks["b_p1"] = true
        return d
    }

    private func shelfId(_ d: AppState, _ name: String) throws -> String {
        let hit: Shelved? = d.shelf.first { (x: Shelved) -> Bool in x.trip.name == name }
        return try XCTUnwrap(hit, "架上沒有 \(name)").id
    }

    func test收起來再切到別趟_不會把打勾帶過去() throws {
        var d: AppState = twoTrips()
        archiveTrip(&d)
        XCTAssertNil(d.checks["b_p1"])
        let shut: Shelved? = d.shelf.first { (x: Shelved) -> Bool in x.trip.name == "A" }
        XCTAssertEqual(shut?.checks["b_p1"], true, "一站都沒去過，整趟放一邊，打勾跟著它")
        let bId: String = try shelfId(d, "B")
        openShelved(&d, bId)
        XCTAssertEqual(d.checks, ["passport": true, "b_p2": true])
        let trip: Trip = try XCTUnwrap(d.trip)
        let left: [String] = unbookedOf(trip, d.checks).map { (x: Stop) -> String in x.id }
        XCTAssertEqual(left, ["p1"], "B 的 p1 還沒訂，要提醒")
    }

    func test不要這一版再切到別趟_不會把打勾帶過去() throws {
        var d: AppState = twoTrips()
        dropPlan(&d)
        XCTAssertEqual(d.checks["b_p1"], true, "不要這一版可以復原，打勾先留著")
        let bId: String = try shelfId(d, "B")
        openShelved(&d, bId)
        XCTAssertEqual(d.checks, ["passport": true, "b_p2": true])
    }

    func test放一邊再切回來_兩趟的打勾都還在() throws {
        var d: AppState = twoTrips()
        let bId: String = try shelfId(d, "B")
        openShelved(&d, bId)
        XCTAssertEqual(d.checks, ["passport": true, "b_p2": true])
        let aId: String = try shelfId(d, "A")
        openShelved(&d, aId)
        XCTAssertEqual(d.checks, ["passport": true, "b_p1": true])
        let bAgain: String = try shelfId(d, "B")
        openShelved(&d, bAgain)
        XCTAssertEqual(d.checks, ["passport": true, "b_p2": true])
        // 找不到那一趟就什麼都不動
        let before: AppState = d
        XCTAssertNil(openShelved(&d, "沒有這趟"))
        XCTAssertEqual(d, before)
    }
}
