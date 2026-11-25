// 晚餐的測試，用真的核對資料掃：平常的設定每個該有晚餐的晚上都有晚餐；
// 同一組一趟一間，只有晚餐沒別組可排才排同組的另一間；同一間不排兩次；不開的不排。iOS 版才有。
import XCTest

@testable import RadishCore

private let DINNER_KINDS: [FoodKind] = [.street, .local, .famous, .fine]

private func dinnerNone(_ id: String, _ iso: String) -> String? {
    return nil
}

private func dinnerSettings(_ kinds: Set<FoodKind>, _ pace: Pace) -> Settings {
    var st: Settings = defaultSettings()
    st.pace = pace
    var food: [FoodKind: Int] = [:]
    for k in DINNER_KINDS { food[k] = kinds.contains(k) ? 3 : 0 }
    st.food = food
    return st
}

private func dinnerTrip(_ st: Settings, _ start: String, _ days: Int) -> Trip {
    let d: TripDraft = TripDraft(
        city: "seoul", start: start, days: days, arrive: .am, leave: .eve, people: 2)
    return generate(d, st)
}

/// 該有晚餐的晚上：不在路上的晚上。回的是在 t.slots 裡的位置
private func dinnerSlots(_ t: Trip) -> [Int] {
    return t.slots.indices.filter { (i: Int) -> Bool in
        return t.slots[i].part == .eve && t.slots[i].off != true
    }
}

private func dinnerHas(_ s: Slot) -> Bool {
    return s.items.contains { (it: Stop) -> Bool in it.c == .eat }
}

/// 排到這個時段的時候，有在吃、那時候有開、前面還沒排過的店
private func dinnerLeft(_ t: Trip, _ si: Int, _ st: Settings) -> [Place] {
    let s: Slot = t.slots[si]
    var used: Set<String> = []
    for x in allItems(t) where x.si < si { used.insert(x.it.id) }
    let lv: [FoodKind: Int] = foodLv(st)
    var out: [Place] = []
    for p in PLACES where p.c == .eat && p.s == .S && !used.contains(p.id) {
        guard let f = p.f, (lv[f] ?? 0) > 0 else { continue }
        if closedOnTripDay(t.start, s.day, p.id, closedByFacts) != nil { continue }
        if closedAtTripPart(t.start, s.day, s.part, p.id, partClosedByFacts) != nil { continue }
        out.append(p)
    }
    return out
}

final class DinnerTests: XCTestCase {
    func test每個該有晚餐的晚上都有晚餐_每種吃的組合都掃() {
        // 資料裡就是不夠的兩種，缺了不算錯，但那一晚要真的一間都不剩：
        // 只吃路邊：市場一共四個，白天也會排；只吃精緻：一共六間，週日、一只開兩間
        let scarce: [Set<FoodKind>] = [[.street], [.fine]]
        // 四天的七種出發日都掃，七天的掃兩種（本來就每個星期幾都碰得到）
        var trips: [(days: Int, w: Int)] = [(days: 7, w: 0), (days: 7, w: 3)]
        for w in 0..<7 { trips.append((days: 4, w: w)) }
        let paces: [Pace] = [.slow, .mid, .fast]
        var sameGroup: Int = 0
        for bits in 0..<16 {
            var kinds: Set<FoodKind> = []
            for i in 0..<4 {
                if (bits >> i) & 1 == 1 { kinds.insert(DINNER_KINDS[i]) }
            }
            let picked: [FoodKind] = DINNER_KINDS.filter { (k: FoodKind) -> Bool in kinds.contains(k) }
            let names: [String] = picked.map { (k: FoodKind) -> String in k.rawValue }
            for pace in paces {
                let st: Settings = dinnerSettings(kinds, pace)
                for one in trips {
                    let start: String = addDays("2026-12-06", one.w)
                    let t: Trip = dinnerTrip(st, start, one.days)
                    let tag: String = "\(names) \(pace) \(one.days) 天 \(start)"
                    for si in dinnerSlots(t) where !dinnerHas(t.slots[si]) {
                        let day: Int = t.slots[si].day
                        XCTAssertTrue(scarce.contains(kinds), "第 \(day) 天沒有晚餐：\(tag)")
                        let left: [String] = dinnerLeft(t, si, st).map { (p: Place) -> String in p.n }
                        XCTAssertEqual(left, [], "第 \(day) 天還有得排：\(tag)")
                    }
                    sameGroup += checkGroups(t, st, tag)
                }
            }
        }
        XCTAssertTrue(sameGroup > 0, "沒有一趟排到同組的另一間，同組那幾條就是空的")
    }

    /// 七天以內的：同一間不排兩次、不開的不排、同組的第二間只會是晚餐而且那時候沒有別組可排。回同組第二間有幾次
    private func checkGroups(_ t: Trip, _ st: Settings, _ tag: String) -> Int {
        XCTAssertEqual(closedNotes(t, caution: dinnerNone), [], tag)
        let all: [Found] = allItems(t)
        let ids: [String] = all.map { (x: Found) -> String in x.it.id }
        XCTAssertEqual(Set(ids).count, ids.count, "同一間不會排兩次：\(tag)")
        var hits: Int = 0
        var before: Set<String> = []
        for x in all {
            let group: String = placeGroup(x.it.id)
            if before.contains(group) {
                hits += 1
                let dinner: Bool = x.it.c == .eat && x.s.part == .eve
                XCTAssertTrue(dinner, "「\(x.it.n)」不是晚餐，不能排同組第二間：\(tag)")
                var fresh: [String] = []
                for p in dinnerLeft(t, x.si, st) where !before.contains(placeGroup(p.id)) {
                    fresh.append(p.n)
                }
                XCTAssertEqual(fresh, [], "還有別組可以排，卻排了「\(x.it.n)」：\(tag)")
            }
            before.insert(group)
        }
        return hits
    }

    func test只吃在地小館_排滿的四天_每晚都有晚餐() {
        let st: Settings = dinnerSettings([.local], .fast)
        for w in 0..<7 {
            let t: Trip = dinnerTrip(st, addDays("2026-12-06", w), 4)
            let nights: [Int] = dinnerSlots(t)
            XCTAssertEqual(nights.count, 3)
            for si in nights {
                XCTAssertTrue(dinnerHas(t.slots[si]), "第 \(t.slots[si].day) 天 \(t.start)")
            }
        }
    }

    func test預設的偏好_七天也不用排到同組第二間() {
        let st: Settings = defaultSettings()
        for w in 0..<7 {
            let t: Trip = dinnerTrip(st, addDays("2026-12-06", w), 7)
            let groups: [String] = allItems(t).map { (x: Found) -> String in placeGroup(x.it.id) }
            XCTAssertEqual(Set(groups).count, groups.count, t.start)
        }
    }
}
