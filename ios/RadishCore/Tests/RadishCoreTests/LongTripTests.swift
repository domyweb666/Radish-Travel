// 長行程（8、10、14 天）白天空著的，不比 0.4.1 多；晚餐那句的字；行程文字的要先訂。iOS 版才有。
import XCTest

@testable import RadishCore

private func longNone(_ id: String, _ iso: String) -> String? {
    return nil
}

private func longTrip(_ st: Settings, _ start: String, _ days: Int) -> Trip {
    let d: TripDraft = TripDraft(
        city: "seoul", start: start, days: days, arrive: .am, leave: .eve, people: 2)
    return generate(d, st)
}

private func longDayCount(_ t: Trip, _ day: Int) -> Int {
    return dayStops(t, day).filter { (x: Found) -> Bool in x.s.part != .eve }.count
}

final class LongTripTests: XCTestCase {
    func test長行程_白天空著的不比以前多_規矩照守() {
        let paces: [Pace] = [.slow, .mid, .fast]
        let bases: [BaseKey] = [.C, .D, .G, .I]
        var empty: Int = 0
        var few: Int = 0
        var filled: Int = 0
        for days in [8, 10, 14] {
            for pace in paces {
                for base in bases {
                    for w in [0, 3] {
                        var st: Settings = defaultSettings()
                        st.pace = pace
                        st.base = base
                        let t: Trip = longTrip(st, addDays("2026-12-06", w), days)
                        for day in 2...days {
                            let n: Int = longDayCount(t, day)
                            if n == 0 { empty += 1 }
                            if n < 2 { few += 1 }
                        }
                        filled += checkLong(t, "\(pace) 住 \(base) \(days) 天 \(t.start)")
                    }
                }
            }
        }
        // 0.4.1（還沒有核對資料）掃同樣這 72 趟：整個白天空著 60 天，少於兩站 88 天
        XCTAssertTrue(empty <= 60, "整個白天空著 \(empty) 天")
        XCTAssertTrue(few <= 88, "白天少於兩站 \(few) 天")
        XCTAssertTrue(filled > 0, "沒有一趟放寬到，這條就是空的")
    }

    /// 同一間不排兩次、不開的不排、一天最多兩站吃的（白天一站）、白天放寬的不是吃的、每晚有晚餐。回白天放寬幾次
    private func checkLong(_ t: Trip, _ tag: String) -> Int {
        XCTAssertEqual(closedNotes(t, caution: longNone), [], tag)
        let all: [Found] = allItems(t)
        let ids: [String] = all.map { (x: Found) -> String in x.it.id }
        XCTAssertEqual(Set(ids).count, ids.count, "同一間不會排兩次：\(tag)")
        for day in 1...t.days {
            let eats: [Found] = dayStops(t, day).filter { (x: Found) -> Bool in x.it.c == .eat }
            let light: [Found] = eats.filter { (x: Found) -> Bool in x.s.part != .eve }
            XCTAssertTrue(eats.count <= 2 && light.count <= 1, "第 \(day) 天吃 \(eats.count) 站：\(tag)")
            if day < t.days { XCTAssertEqual(eats.count - light.count, 1, "第 \(day) 天晚餐：\(tag)") }
        }
        var hits: Int = 0
        var before: Set<String> = []
        for x in all {
            let group: String = placeGroup(x.it.id)
            if before.contains(group) && x.s.part != .eve {
                hits += 1
                XCTAssertTrue(x.it.c != .eat, "白天放寬排了吃的「\(x.it.n)」：\(tag)")
            }
            before.insert(group)
        }
        return hits
    }

    func test排滿住明洞的八天_最後一天白天不空著() {
        var st: Settings = defaultSettings()
        st.pace = .fast
        for w in 0..<7 {
            let t: Trip = longTrip(st, addDays("2026-12-06", w), 8)
            XCTAssertTrue(longDayCount(t, 8) > 0, t.start)
        }
    }

    /* ---------- 字 ---------- */

    private func dinnerWhys(_ st: Settings, _ days: Int) -> [String] {
        let eves: [Found] = allItems(longTrip(st, "2026-12-06", days)).filter { (x: Found) -> Bool in
            return x.s.part == .eve && x.it.c == .eat
        }
        return eves.map { (x: Found) -> String in x.it.why }
    }

    func test晚餐那句講白話_同組第二間也講得通() {
        var st: Settings = defaultSettings()
        st.pace = .fast
        st.food = [.street: 0, .local: 3, .famous: 0, .fine: 0]
        let whys: [String] = dinnerWhys(st, 6)
        let usual: String = "晚餐吃\(FOOD[need: .local].name)，你說主要吃這種"
        let same: String = "晚餐吃\(FOOD[need: .local].name)，這一晚沒有別類的店可以排"
        XCTAssertTrue(whys.contains(usual), "\(whys)")
        XCTAssertTrue(whys.contains(same), "\(whys)")
        XCTAssertTrue(whys.allSatisfy { (w: String) -> Bool in w == usual || w == same }, "\(whys)")
        // 每一種都說不要：還是排小館，但不說成是你說的
        st.food = [.street: 0, .local: 0, .famous: 0, .fine: 0]
        XCTAssertEqual(dinnerWhys(st, 2), ["晚餐吃\(FOOD[need: .local].name)"])
    }

    func test行程文字的要先訂_看現在的資料() throws {
        let place: Place = try XCTUnwrap(PLACES.first { (p: Place) -> Bool in p.id == "p27" })
        var it: Stop = planToStop(place, "測試")
        it.b = true
        let slot: Slot = Slot(day: 1, part: .am, items: [it])
        let t: Trip = Trip(start: "2026-12-07", days: 1, arrive: .am, leave: .eve, people: 2, slots: [slot])
        XCTAssertTrue(planText(t).contains(it.n))
        XCTAssertFalse(planText(t).contains("要先訂"))
    }
}
