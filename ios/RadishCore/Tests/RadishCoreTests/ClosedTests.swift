// 休館日的測試：哪天不開、排行程避開、換一個和附近避開、排回這趟避開、自己要排的不擋但要講。
// 休館資料全部是這裡手刻的，跟 seoul-checked.json 裡有沒有東西無關。iOS 版才有，mobile/tests/ 沒有對應的。
import XCTest

@testable import RadishCore

/* ---------- 手刻的核對資料 ---------- */

private func closedChecked(holidays: [String] = [], lunar: [String: [String]] = [:]) -> SeoulChecked {
    return SeoulChecked(
        checked: "2026-11-25", facts: [:], drop: [], add: [], lunar: lunar, holidays: holidays, dated: [])
}

private func closedFact(
    closed: [Int]? = nil, nth: [NthDay]? = nil, on: [String]? = nil, shift: HolidayShift? = nil,
    off: [OffSpan]? = nil, gone: String? = nil
) -> PlaceFact {
    return PlaceFact(
        status: .official, checked: "2026-11-25", src: [],
        closed: closed, closedNth: nth, closedOn: on, shift: shift, off: off, gone: gone)
}

/* ---------- 假的休館判斷 ---------- */

private func neverClosed(_ id: String, _ iso: String) -> String? {
    return nil
}

private func alwaysClosed(_ id: String, _ iso: String) -> String? {
    return "天天休"
}

/// 每個地方照代號固定休某一天，七天都有人休
private func spreadClosed(_ id: String, _ iso: String) -> String? {
    var h: Int = 0
    for u in id.unicodeScalars {
        h = (h * 31 + Int(u.value)) % 1000
    }
    return h % 7 == dowOf(iso) ? "每週\(weekday(iso))休" : nil
}

/// 這幾個地方在這一天休，其他都開
private func closedOnly(_ ids: Set<String>, _ date: String, _ why: String) -> ClosedCheck {
    return { (id: String, iso: String) -> String? in
        return ids.contains(id) && iso == date ? why : nil
    }
}

/* ---------- 手刻的行程 ---------- */

private func closedStop(_ id: String, _ name: String) -> Stop {
    return Stop(
        id: id, n: name, kr: "", a: nil, s: .S, c: .sight, lat: nil, lng: nil,
        status: .kept, swaps: 0, why: "測試"
    )
}

/// 空的五天，12/1（二）到 12/5（六）。第 1 天上午、第 5 天晚上在路上
private func closedTrip() -> Trip {
    var slots: [Slot] = []
    for day in 1...5 {
        for part in PARTS {
            let off: Bool = (day == 1 && part == .am) || (day == 5 && part == .eve)
            slots.append(Slot(day: day, part: part, off: off ? true : nil, items: []))
        }
    }
    return Trip(start: "2026-12-01", days: 5, arrive: .pm, leave: .pm, people: 2, slots: slots)
}

private func closedPut(_ t: inout Trip, _ day: Int, _ part: Part, _ it: Stop) {
    guard let si = slotAt(t, day, part) else {
        XCTFail("第 \(day) 天沒有這個時段")
        return
    }
    t.slots[si].items.append(it)
}

private func closedSeed(_ it: Stop, _ from: SeedFrom?) -> Seed {
    return Seed(id: "s-" + it.id, n: it.n, a: "明洞", why: "測試", stop: it, from: from)
}

private func closedDraft(days: Int, start: String = "2026-12-01") -> TripDraft {
    return TripDraft(city: "seoul", start: start, days: days, arrive: .am, leave: .eve, people: 2)
}

private func closedRandom(_ seed: Int) -> () -> Double {
    var x: UInt64 = UInt64(seed)
    return { () -> Double in
        x = (x &* 6_364_136_223_846_793_005) &+ 1_442_695_040_888_963_407
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }
}

final class ClosedTests: XCTestCase {
    /* ---------- 1 這一天開不開 ---------- */

    func test每週固定休() {
        let f: PlaceFact = closedFact(closed: [2])
        let c: SeoulChecked = closedChecked()
        XCTAssertEqual(closedWhy(f, "2026-12-01", c), "每週二休")
        XCTAssertEqual(closedWhy(f, "2026-12-08", c), "每週二休")
        XCTAssertNil(closedWhy(f, "2026-11-30", c))
        XCTAssertNil(closedWhy(f, "2026-12-02", c))
        let two: PlaceFact = closedFact(closed: [0, 1])
        XCTAssertEqual(closedWhy(two, "2026-12-06", c), "每週日休")
        XCTAssertEqual(closedWhy(two, "2026-12-07", c), "每週一休")
        XCTAssertNil(closedWhy(two, "2026-12-08", c))
    }

    func test沒有資料_查過沒有固定休_都算開() {
        let c: SeoulChecked = closedChecked(holidays: ["2026-12-01"], lunar: ["seollal": ["2026-12-01"]])
        for i in 0..<14 {
            let iso: String = addDays("2026-12-01", i)
            XCTAssertNil(closedWhy(closedFact(), iso, c), iso)
            XCTAssertNil(closedWhy(closedFact(closed: []), iso, c), iso)
            XCTAssertNil(closedWhy(closedFact(closed: [], shift: .next), iso, c), iso)
            XCTAssertNil(closedWhy("沒有這個代號", iso), iso)
        }
    }

    func test固定休碰到連假_照開_改休假後第一個平日() {
        // 12/1（二）、12/2（三）連假
        let c: SeoulChecked = closedChecked(holidays: ["2026-12-01", "2026-12-02"])
        let f: PlaceFact = closedFact(closed: [2], shift: .next)
        XCTAssertNil(closedWhy(f, "2026-12-01", c), "假日照開")
        XCTAssertNil(closedWhy(f, "2026-12-02", c), "假日照開")
        XCTAssertNotNil(closedWhy(f, "2026-12-03", c), "改休這天")
        XCTAssertNil(closedWhy(f, "2026-12-04", c), "只補休一天")
        XCTAssertEqual(closedWhy(f, "2026-12-08", c), "每週二休", "下個禮拜照舊")
        // 沒寫碰到假日怎麼辦的：照星期幾
        let plain: PlaceFact = closedFact(closed: [2])
        XCTAssertEqual(closedWhy(plain, "2026-12-01", c), "每週二休")
        XCTAssertNil(closedWhy(plain, "2026-12-03", c))
    }

    func test假日不是固定休的那天_不補休() {
        // 只有 12/2（三）放假
        let c: SeoulChecked = closedChecked(holidays: ["2026-12-02"])
        let f: PlaceFact = closedFact(closed: [2], shift: .next)
        XCTAssertEqual(closedWhy(f, "2026-12-01", c), "每週二休")
        XCTAssertNil(closedWhy(f, "2026-12-02", c))
        XCTAssertNil(closedWhy(f, "2026-12-03", c), "前面那個假日不是它的固定休")
    }

    func test固定休碰到假日照開不補休() {
        let c: SeoulChecked = closedChecked(holidays: ["2026-12-01", "2026-12-02"])
        let f: PlaceFact = closedFact(closed: [2], shift: .open)
        XCTAssertNil(closedWhy(f, "2026-12-01", c))
        XCTAssertNil(closedWhy(f, "2026-12-03", c))
        XCTAssertEqual(closedWhy(f, "2026-12-08", c), "每週二休")
    }

    func test節日休_農曆照表_國曆每年_寫了年份的只有那天() {
        let c: SeoulChecked = closedChecked(lunar: ["seollal": ["2027-02-06", "2027-02-07", "2027-02-08"]])
        let f: PlaceFact = closedFact(on: ["seollal", "01-01", "2026-12-24"])
        XCTAssertNil(closedWhy(f, "2027-02-05", c))
        XCTAssertEqual(closedWhy(f, "2027-02-06", c), "節日休")
        XCTAssertEqual(closedWhy(f, "2027-02-08", c), "節日休")
        XCTAssertNil(closedWhy(f, "2027-02-09", c))
        XCTAssertEqual(closedWhy(f, "2027-01-01", c), "節日休")
        XCTAssertEqual(closedWhy(f, "2028-01-01", c), "節日休")
        XCTAssertNil(closedWhy(f, "2026-11-01", c), "11/1 不是 1/1")
        XCTAssertEqual(closedWhy(f, "2026-12-24", c), "節日休")
        XCTAssertNil(closedWhy(f, "2027-12-24", c))
        // 表裡沒有的節日不猜
        XCTAssertNil(closedWhy(closedFact(on: ["chuseok"]), "2027-02-06", c))
    }

    func test每月第幾個星期幾休() {
        let c: SeoulChecked = closedChecked()
        let f: PlaceFact = closedFact(nth: [NthDay(week: 2, dow: 0), NthDay(week: 4, dow: 0)])
        XCTAssertNil(closedWhy(f, "2026-12-06", c))
        XCTAssertEqual(closedWhy(f, "2026-12-13", c), "每月第 2 個週日休")
        XCTAssertNil(closedWhy(f, "2026-12-14", c))
        XCTAssertNil(closedWhy(f, "2026-12-20", c))
        XCTAssertEqual(closedWhy(f, "2026-12-27", c), "每月第 4 個週日休")
    }

    func test有一段時間不開() {
        let c: SeoulChecked = closedChecked()
        let f: PlaceFact = closedFact(off: [OffSpan(from: "2026-12-01", to: "2026-12-10", why: "整修")])
        XCTAssertNil(closedWhy(f, "2026-11-30", c))
        XCTAssertEqual(closedWhy(f, "2026-12-01", c), "整修")
        XCTAssertEqual(closedWhy(f, "2026-12-10", c), "整修")
        XCTAssertNil(closedWhy(f, "2026-12-11", c))
        let open: PlaceFact = closedFact(off: [OffSpan(from: "2026-12-01", to: nil, why: "整修")])
        XCTAssertNil(closedWhy(open, "2026-11-30", c))
        XCTAssertEqual(closedWhy(open, "2031-01-01", c), "整修", "不知道到什麼時候就一直算不開")
    }

    func test歇業了哪天都不開() {
        let f: PlaceFact = closedFact(closed: [], gone: "2025 年歇業")
        let c: SeoulChecked = closedChecked()
        for iso in ["2020-01-01", "2026-12-01", "2030-06-15"] {
            XCTAssertEqual(closedWhy(f, iso, c), "2025 年歇業")
        }
    }

    /* ---------- 2 排行程 ---------- */

    func test排行程不排休館那天_各種節奏天數亂數都掃一次() {
        let paces: [Pace] = [.slow, .mid, .fast]
        for pace in paces {
            var st: Settings = defaultSettings()
            st.pace = pace
            st.play = [.sight: 2, .art: 1]
            for days in [1, 2, 3, 5, 7, 10, 14] {
                for seed in 1...6 {
                    let start: String = addDays("2026-12-01", seed)
                    let t: Trip = generate(
                        closedDraft(days: days, start: start), st, true, closedRandom(seed), closed: spreadClosed)
                    let tag: String = "\(pace) \(days) 天 亂數 \(seed)"
                    XCTAssertEqual(closedNotes(t, closed: spreadClosed), [], tag)
                    XCTAssertEqual(t.slots.count, days * 3, tag)
                    let ids: [String] = allItems(t).map { (x: Found) -> String in x.it.id }
                    XCTAssertEqual(Set(ids).count, ids.count, "同一站不會排兩次：\(tag)")
                    XCTAssertFalse(ids.isEmpty, tag)
                    for d in 1...days { XCTAssertTrue(bigCount(t, d) <= 2, tag) }
                }
            }
        }
    }

    func test這份假的休館判斷真的擋得到東西() {
        // 反例：不看休館的排法，會排到休館那天。不然上一條是空的
        var hit: Int = 0
        for seed in 1...6 {
            let d: TripDraft = closedDraft(days: 10)
            let t: Trip = generate(d, defaultSettings(), true, closedRandom(seed), closed: neverClosed)
            hit += closedNotes(t, closed: spreadClosed).count
        }
        XCTAssertTrue(hit > 0)
    }

    func test排行程_只有那一天休才避開_別的日子休不影響() throws {
        let d: TripDraft = closedDraft(days: 5)
        let plain: Trip = generate(d, defaultSettings(), closed: neverClosed)
        let x: Found = try XCTUnwrap(dayStops(plain, 2).first)
        let shut: ClosedCheck = closedOnly([x.it.id], "2026-12-02", "每週三休")
        let avoided: Trip = generate(d, defaultSettings(), closed: shut)
        XCTAssertFalse(dayStops(avoided, 2).contains { (f: Found) -> Bool in f.it.id == x.it.id })
        XCTAssertFalse(dayStops(avoided, 2).isEmpty, "那天排別的，不是空著")
        // 回來之後那天才休：排出來一模一樣
        let later: ClosedCheck = closedOnly([x.it.id], "2026-12-09", "每週三休")
        XCTAssertEqual(generate(d, defaultSettings(), closed: later), plain)
    }

    func test排行程_整個城市都休_留白不會卡住() {
        let t: Trip = generate(closedDraft(days: 7), defaultSettings(), closed: alwaysClosed)
        XCTAssertEqual(t.slots.count, 21)
        XCTAssertTrue(allItems(t).isEmpty)
        XCTAssertTrue(t.slots.allSatisfy { (s: Slot) -> Bool in s.off == true || s.rest })
    }

    func test排行程_全城休一天_只有那天空著() {
        let all: Set<String> = Set(PLACES.map { (p: Place) -> String in p.id })
        let shut: ClosedCheck = closedOnly(all, "2026-12-03", "節日休")
        let t: Trip = generate(closedDraft(days: 5), defaultSettings(), closed: shut)
        XCTAssertTrue(dayStops(t, 3).isEmpty)
        for d in [1, 2, 4, 5] { XCTAssertFalse(dayStops(t, d).isEmpty, "第 \(d) 天有開") }
    }

    func test排行程_近郊那天全休_改排市區_白天不空著() throws {
        var st: Settings = defaultSettings()
        st.play = [.sight: 2]
        let d: TripDraft = closedDraft(days: 7)
        let plain: Trip = generate(d, st, closed: neverClosed)
        let hit: Found? = allItems(plain).first { (x: Found) -> Bool in x.it.a == AreaKey.J }
        guard let far = hit else { throw XCTSkip("這份資料沒有排到近郊") }
        let ids: [String] = PLACES.filter { (p: Place) -> Bool in p.a == AreaKey.J }.map { (p: Place) -> String in p.id }
        let shut: ClosedCheck = closedOnly(Set(ids), addDays(d.start, far.s.day - 1), "每週休")
        let t: Trip = generate(d, st, closed: shut)
        let stops: [Found] = dayStops(t, far.s.day)
        XCTAssertFalse(stops.contains { (x: Found) -> Bool in x.it.a == AreaKey.J })
        XCTAssertTrue(stops.contains { (x: Found) -> Bool in x.s.part != .eve }, "白天照平常的一天排")
    }

    /* ---------- 3 換一個、附近 ---------- */

    func test換一個_跳過這一站那天休館的() throws {
        let st: Settings = defaultSettings()
        let t: Trip = generate(closedDraft(days: 5), st, closed: neverClosed)
        let found: Found? = allItems(t).first { (x: Found) -> Bool in
            !alternatives(t, st, x.it, closed: neverClosed).isEmpty
        }
        let x: Found = try XCTUnwrap(found)
        let before: [Place] = alternatives(t, st, x.it, closed: neverClosed)
        let first: Place = try XCTUnwrap(before.first)
        let date: String = addDays(t.start, x.s.day - 1)
        let after: [Place] = alternatives(t, st, x.it, closed: closedOnly([first.id], date, "休"))
        XCTAssertFalse(after.contains { (p: Place) -> Bool in p.id == first.id })
        // 反例：隔天才休，照樣給
        let next: ClosedCheck = closedOnly([first.id], addDays(date, 1), "休")
        XCTAssertEqual(alternatives(t, st, x.it, closed: next), before)
        XCTAssertTrue(alternatives(t, st, x.it, closed: alwaysClosed).isEmpty)
        // 不在行程裡的不知道是哪天，不擋
        var loose: Stop = x.it
        loose.id = "不在行程裡"
        XCTAssertFalse(alternatives(t, st, loose, closed: alwaysClosed).isEmpty)
    }

    func test附近_跳過這天休館的() throws {
        let st: Settings = defaultSettings()
        let t: Trip = closedTrip()
        let before: [NearbyPick] = nearbyRanked(t, st, 2, closed: neverClosed)
        let first: NearbyPick = try XCTUnwrap(before.first)
        let today: ClosedCheck = closedOnly([first.place.id], "2026-12-02", "休")
        let after: [NearbyPick] = nearbyRanked(t, st, 2, closed: today)
        XCTAssertEqual(after, Array(before.dropFirst()))
        let other: ClosedCheck = closedOnly([first.place.id], "2026-12-03", "休")
        XCTAssertEqual(nearbyRanked(t, st, 2, closed: other), before)
    }

    func test順路可去_跳過這天休館的() throws {
        let t: Trip = generate(closedDraft(days: 5), defaultSettings(), closed: neverClosed)
        let day: Int = try XCTUnwrap(
            [1, 2, 3, 4, 5].first { (d: Int) -> Bool in !nearbyPool(t, d, nil, closed: neverClosed).isEmpty })
        let before: [String] = nearbyPool(t, day, nil, closed: neverClosed)
        let name: String = try XCTUnwrap(before.first)
        let place: Place = try XCTUnwrap(PLACES.first { (p: Place) -> Bool in p.n == name })
        let date: String = addDays(t.start, day - 1)
        XCTAssertFalse(nearbyPool(t, day, nil, closed: closedOnly([place.id], date, "休")).contains(name))
        XCTAssertEqual(nearbyPool(t, day, nil, closed: closedOnly([place.id], addDays(date, 1), "休")), before)
    }

    /* ---------- 4 排回這趟 ---------- */

    func test排回這趟_原本那天休館就換一天_講清楚() throws {
        var t: Trip = closedTrip()
        var seeds: [Seed] = [closedSeed(closedStop("x1", "景福宮"), SeedFrom(day: 2, part: .am))]
        let shut: ClosedCheck = closedOnly(["x1"], "2026-12-02", "每週三休")
        let msg: String = restoreSeed(&t, &seeds, "s-x1", nil, closed: shut)
        XCTAssertEqual(msg, "第 2 天「景福宮」休館（每週三休），改排在第 3 天上午")
        XCTAssertEqual(try XCTUnwrap(findItem(t, "x1")).s.day, 3)
        XCTAssertEqual(seeds.count, 0)
        XCTAssertEqual(closedNotes(t, closed: shut), [])
    }

    func test排回這趟_別的站休館_別天休館_都照舊放回原本的時段() throws {
        let checks: [ClosedCheck] = [
            closedOnly(["別站"], "2026-12-02", "每週三休"), closedOnly(["x1"], "2026-12-03", "每週四休"), neverClosed,
        ]
        for shut in checks {
            var t: Trip = closedTrip()
            var seeds: [Seed] = [closedSeed(closedStop("x1", "景福宮"), SeedFrom(day: 2, part: .am))]
            let msg: String = restoreSeed(&t, &seeds, "s-x1", nil, closed: shut)
            XCTAssertEqual(msg, "「景福宮」排回第 2 天上午了")
        }
    }

    func test排回這趟_沒記原本在哪天_也不放休館那天() throws {
        var t: Trip = closedTrip()
        var seeds: [Seed] = [closedSeed(closedStop("x1", "景福宮"), nil)]
        let shut: ClosedCheck = closedOnly(["x1"], "2026-12-02", "每週三休")
        let msg: String = restoreSeed(&t, &seeds, "s-x1", nil, closed: shut)
        XCTAssertEqual(msg, "「景福宮」排回第 3 天上午了")
    }

    func test排回這趟_原本的時段過了_改排的那天也要有開() throws {
        var t: Trip = closedTrip()
        var seeds: [Seed] = [closedSeed(closedStop("x1", "景福宮"), SeedFrom(day: 2, part: .am))]
        let now: TripNow = TripNow(day: 3, part: .pm, clock: "14:00")
        let shut: ClosedCheck = closedOnly(["x1"], "2026-12-03", "每週四休")
        let msg: String = restoreSeed(&t, &seeds, "s-x1", now, closed: shut)
        XCTAssertEqual(msg, "第 2 天上午已經過了，「景福宮」改排在第 4 天上午")
    }

    func test排回這趟_能放的日子全休_照放回原本的時段_講明() throws {
        var t: Trip = closedTrip()
        var seeds: [Seed] = [closedSeed(closedStop("x1", "景福宮"), SeedFrom(day: 2, part: .am))]
        let msg: String = restoreSeed(&t, &seeds, "s-x1", nil, closed: alwaysClosed)
        XCTAssertEqual(msg, "「景福宮」排回第 2 天上午了，但那天它休館（天天休），能排的別天也都休")
        XCTAssertEqual(try XCTUnwrap(findItem(t, "x1")).s.day, 2)
        XCTAssertEqual(seeds.count, 0)
    }

    func test排回這趟_時段都過了還是留在下次再來() {
        var t: Trip = closedTrip()
        var seeds: [Seed] = [closedSeed(closedStop("x1", "景福宮"), SeedFrom(day: 2, part: .am))]
        let now: TripNow = TripNow(day: 5, part: .eve, clock: "20:00")
        let msg: String = restoreSeed(&t, &seeds, "s-x1", now, closed: alwaysClosed)
        XCTAssertEqual(seeds.count, 1)
        XCTAssertTrue(allItems(t).isEmpty)
        XCTAssertTrue(msg.contains("都過了"), msg)
    }

    /* ---------- 5 自己決定的不擋，但要講 ---------- */

    func test排到休館那天要講_照天數_拔起來的不講() throws {
        var t: Trip = closedTrip()
        closedPut(&t, 4, .am, closedStop("x2", "國立中央博物館"))
        closedPut(&t, 1, .pm, closedStop("x1", "景福宮"))
        var pulled: Stop = closedStop("x3", "昌德宮")
        pulled.status = .pulled
        closedPut(&t, 2, .am, pulled)
        let shut: ClosedCheck = { (id: String, iso: String) -> String? in
            return id == "x2" ? "整修" : "每週\(weekday(iso))休"
        }
        let want: [String] = [
            "第 1 天 12/1（二）「景福宮」休館：每週二休。", "第 4 天 12/4（五）「國立中央博物館」休館：整修。",
        ]
        XCTAssertEqual(closedNotes(t, closed: shut), want)
        XCTAssertEqual(warnings(t, closed: shut), want)
        XCTAssertEqual(closedNotes(t, closed: neverClosed), [])
        XCTAssertEqual(warnings(t, closed: neverClosed), [])
        // 還沒有日期的不知道哪天，不講
        t.start = ""
        XCTAssertEqual(closedNotes(t, closed: alwaysClosed), [])
    }

    func test移站_對調不擋_提醒跟著走() throws {
        var t: Trip = closedTrip()
        closedPut(&t, 2, .am, closedStop("x1", "景福宮"))
        let shut: ClosedCheck = closedOnly(["x1"], "2026-12-03", "每週四休")
        XCTAssertEqual(closedNotes(t, closed: shut), [])
        XCTAssertNil(moveItem(&t, "x1", 3, .pm))
        XCTAssertEqual(closedNotes(t, closed: shut), ["第 3 天 12/3（四）「景福宮」休館：每週四休。"])
        XCTAssertNil(swapDays(&t, 3, 4))
        XCTAssertEqual(closedNotes(t, closed: shut), [], "換到第 4 天就沒事了")
        XCTAssertNil(swapDays(&t, 3, 4))
        XCTAssertNil(swapParts(&t, 3, .am, .pm))
        XCTAssertEqual(closedNotes(t, closed: shut).count, 1, "同一天換時段還是休館")
    }

    /* ---------- 6 給 AI 的字 ---------- */

    func test給AI的固定休_短的() {
        XCTAssertEqual(closedShort(closedFact(closed: [2])), "週二休")
        XCTAssertEqual(closedShort(closedFact(closed: [0, 1])), "週日、一休")
        XCTAssertEqual(closedShort(closedFact(closed: [])), "沒有固定休")
        XCTAssertEqual(closedShort(closedFact(nth: [NthDay(week: 2, dow: 0)])), "每月第 2 個週日休")
        XCTAssertEqual(closedShort(closedFact(closed: [1], gone: "歇業")), "已經不開了")
        XCTAssertNil(closedShort(closedFact()), "沒查到就不寫")
    }

    func test給AI的休館_寫這趟第幾天不開() {
        let t: Trip = closedTrip()
        let id: String = "沒有這個代號"
        let shut: ClosedCheck = { (_: String, iso: String) -> String? in
            return iso == "2026-12-02" || iso == "2026-12-04" ? "休" : nil
        }
        XCTAssertEqual(closedTag(t, id, closed: shut), ",第 2、4 天不開")
        XCTAssertEqual(closedTag(t, id, closed: alwaysClosed), ",這趟每天都不開")
        XCTAssertEqual(closedTag(t, id, closed: neverClosed), "")
    }

    func test提示詞_有寫休館日的照寫的_資料有的都帶上() {
        let t: Trip = generate(closedDraft(days: 5), defaultSettings(), closed: neverClosed)
        let clock: ChatClock = ChatClock(phase: .plan(daysToGo: 12), hour: 9, minute: 0)
        let p: String = aiPrompt("下一站去哪", t, defaultSettings(), [], clock)
        XCTAssertTrue(p.contains("照寫的對星期幾"))
        XCTAssertTrue(p.contains("沒寫的，說去之前查"))
        let used: Set<String> = usedIds(t)
        for x in PLACES {
            let gone: Bool = factOf(x.id)?.gone != nil
            if gone && !used.contains(x.id) {
                XCTAssertFalse(p.contains("[\(x.id)]"), "不開了的不給挑：\(x.n)")
                continue
            }
            let tag: String = closedTag(t, x.id)
            if !tag.isEmpty { XCTAssertTrue(p.contains(tag), x.n) }
        }
    }

    /* ---------- 7 手機自己答的、傳給旅伴的：核對過的不說沒核對 ---------- */

    private func state(_ it: Stop) -> AppState {
        var t: Trip = closedTrip()
        closedPut(&t, 2, .am, it)
        var d: AppState = AppState()
        d.trip = t
        return d
    }

    func test這一站要注意什麼_有沒核對的才說沒核對() throws {
        for p in PLACES {
            let it: Stop = planToStop(p, "測試")
            let d: AppState = state(it)
            let fact: PlaceFact? = factOf(p.id)
            var checked: Bool = false
            if let f = fact { checked = f.status != FactStatus.none }
            var unsure: Bool = false
            if let tip = tipOf(it), tip.status == FactStatus.none { unsure = true }
            if it.b == true && !(checked && fact?.book != nil) { unsure = true }
            if !checked && closedWhy(p.id, "2026-12-02") != nil { unsure = true }
            let one: String = try XCTUnwrap(phoneAnswer("這一站要注意什麼", d, 2, p.id, nil))
            XCTAssertEqual(one.contains("還沒核對過"), unsure, one)
            let day: String = try XCTUnwrap(phoneAnswer("第 2 天要注意什麼", d, 2, nil, nil))
            XCTAssertEqual(day.contains("還沒核對過"), unsure, day)
        }
    }

    func test這一站要注意什麼_沒有資料的照舊說還沒核對過() throws {
        var it: Stop = closedStop("x1", "那家店")
        it.tip = "要脫鞋"
        it.b = true
        let d: AppState = state(it)
        let one: String? = phoneAnswer("這一站要注意什麼", d, 2, "x1", nil)
        XCTAssertEqual(one, "「那家店」：要脫鞋；要先訂。這是資料裡寫的，還沒核對過，去之前查一下。")
        let book: String = try XCTUnwrap(phoneAnswer("有哪些要先訂", d, 2, nil, nil))
        XCTAssertTrue(book.contains("還沒核對過"), book)
        it.b = nil
        let none: String = try XCTUnwrap(phoneAnswer("有哪些要先訂", state(it), 2, nil, nil))
        XCTAssertTrue(none.contains("還沒核對過"), none)
    }

    func test傳給旅伴_照實寫幾站看過官方頁() {
        var t: Trip = closedTrip()
        closedPut(&t, 2, .am, closedStop("x1", "那家店"))
        closedPut(&t, 2, .pm, closedStop("x2", "另一家"))
        XCTAssertTrue(shareText(t).contains("這 2 站都還沒看過官方頁"), shareText(t))
        for p in PLACES { closedPut(&t, 3, .am, planToStop(p, "測試")) }
        var seen: Int = 0
        for p in PLACES {
            guard let f = factOf(p.id) else { continue }
            if f.status == FactStatus.official { seen += 1 }
        }
        let text: String = shareText(t)
        let all: Int = PLACES.count + 2
        if seen == 0 {
            XCTAssertTrue(text.contains("這 \(all) 站都還沒看過官方頁"), text)
        } else {
            XCTAssertTrue(text.contains("有 \(seen) 站看過官方頁，\(all - seen) 站沒有"), text)
        }
        XCTAssertFalse(shareText(closedTrip()).contains("官方頁"), "一站都沒有就不講")
    }
}
