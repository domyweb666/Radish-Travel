// 用真的核對資料掃：同組只排一間、一天最多兩站吃的、不排在不開的日子和時段、白天不整個空著。
// 加上時段、提醒、以後都不排、訂位的字。iOS 版才有。
import XCTest

@testable import RadishCore

private func ckStop(_ id: String, _ c: Cat = .sight) -> Stop {
    if let p: Place = PLACES.first(where: { (x: Place) -> Bool in x.id == id }) { return planToStop(p, "測試") }
    return Stop(
        id: id, n: id, kr: "", a: nil, s: .S, c: c, lat: nil, lng: nil, status: .kept, swaps: 0, why: "測試")
}

private func ckTrip(_ start: String, _ days: Int) -> Trip {
    var slots: [Slot] = []
    for day in 1...days {
        for part in PARTS { slots.append(Slot(day: day, part: part, items: [])) }
    }
    return Trip(start: start, days: days, arrive: .am, leave: .eve, people: 2, slots: slots)
}

private func ckPut(_ t: inout Trip, _ day: Int, _ part: Part, _ it: Stop) {
    if let si = slotAt(t, day, part) { t.slots[si].items.append(it) }
}

private func ckNone(_ id: String, _ iso: String) -> String? {
    return nil
}

private let CK_TAIPEI: TimeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone.current

final class CheckedTests: XCTestCase {
    /* ---------- 排行程 ---------- */

    func test真的資料掃84種組合() {
        let paces: [Pace] = [.slow, .mid, .fast]
        for pace in paces {
            for days in 4...7 {
                for w in 0..<7 {
                    var st: Settings = defaultSettings()
                    st.pace = pace
                    let d: TripDraft = TripDraft(
                        city: "seoul", start: addDays("2026-12-06", w), days: days, arrive: .am, leave: .eve, people: 2)
                    sweep(generate(d, st), "\(pace) \(days) 天 \(d.start)")
                }
            }
        }
    }

    private func sweep(_ t: Trip, _ tag: String) {
        XCTAssertEqual(closedNotes(t, caution: ckNone), [], tag)
        let groups: [String] = allItems(t).map { (x: Found) -> String in placeGroup(x.it.id) }
        XCTAssertEqual(Set(groups).count, groups.count, "同組只排一間：\(tag)")
        for day in 1...t.days {
            let stops: [Found] = dayStops(t, day)
            let eats: [Found] = stops.filter { (x: Found) -> Bool in x.it.c == .eat }
            XCTAssertTrue(eats.count <= 2, "第 \(day) 天吃 \(eats.count) 站：\(tag)")
            let light: [Found] = eats.filter { (x: Found) -> Bool in x.s.part != .eve }
            XCTAssertTrue(light.count <= 1, "第 \(day) 天白天：\(tag)")
            let open: Bool = t.slots.contains { (s: Slot) -> Bool in
                return s.day == day && s.part != .eve && s.off != true
            }
            if open {
                XCTAssertTrue(stops.contains { (x: Found) -> Bool in x.s.part != .eve }, "第 \(day) 天白天空著：\(tag)")
            }
        }
    }

    func test拆開的那幾間是同一組_換一個照樣列全部() {
        XCTAssertEqual(placeGroup("p4a"), "p4")
        XCTAssertEqual(placeGroup("p4c"), "p4")
        XCTAssertEqual(placeGroup("p4"), "p4")
        XCTAssertEqual(placeGroup("p27"), "p27")
        XCTAssertEqual(placeGroup("p0"), "p0")
        XCTAssertEqual(placeGroup("m1"), "m1")
        var t: Trip = ckTrip("2026-12-07", 3)
        ckPut(&t, 2, .eve, ckStop("p26a"))
        var st: Settings = defaultSettings()
        st.food = [.street: 0, .local: 3, .famous: 0, .fine: 0]
        let ids: [String] = alternatives(t, st, ckStop("p26a")).map { (p: Place) -> String in p.id }
        XCTAssertTrue(ids.contains("p26b"), "\(ids)")
    }

    func test以後都不排_舊代號擋整組_新代號只擋那一間() {
        for old in ["p4", "p5", "p13", "p14", "p15", "p16", "p20", "p22", "p26", "p30", "p33", "p34", "p35", "p47"] {
            var st: Settings = defaultSettings()
            _ = learn(&st, LearnChoice(kind: .place, key: old, n: old), "測試")
            let fresh: [Place] = PLACES.filter { (p: Place) -> Bool in placeGroup(p.id) == old }
            XCTAssertFalse(fresh.isEmpty, old)
            XCTAssertTrue(fresh.allSatisfy { (p: Place) -> Bool in banned(p, st) }, old)
        }
        var one: Settings = defaultSettings()
        _ = learn(&one, LearnChoice(kind: .place, key: "p4a", n: "土俗村"), "測試")
        XCTAssertTrue(banned(ckStop("p4a"), one))
        XCTAssertFalse(banned(ckStop("p4b"), one))
        XCTAssertFalse(banned(ckStop("p4"), one))
    }

    /* ---------- 時段 ---------- */

    func test時段_幾點開幾點關() {
        // 12/7 是週一，12/11 週五，12/12 週六
        XCTAssertEqual(partClosedWhy("p26c", "2026-12-07", .pm), "還沒開，16:00 才開")
        XCTAssertNil(partClosedWhy("p26c", "2026-12-07", .eve))
        XCTAssertEqual(partClosedWhy("p26b", "2026-12-07", .am), "還沒開，15:00 才開")
        XCTAssertNil(partClosedWhy("p26b", "2026-12-07", .pm), "15:00 開的下午算開")
        XCTAssertEqual(partClosedWhy("p30c", "2026-12-07", .pm), "還沒開，16:00 才開")
        XCTAssertNil(partClosedWhy("p30c", "2026-12-11", .pm))
        XCTAssertEqual(partClosedWhy("p4c", "2026-12-12", .eve), "15:00 就關了")
        XCTAssertNil(partClosedWhy("p4c", "2026-12-13", .eve), "週日整天休，看 closedWhy")
        XCTAssertEqual(partClosedWhy("p2", "2026-12-07", .eve), "紅區只開 10:00 到 17:00")
        XCTAssertEqual(partClosedWhy("p0", "2026-12-07", .eve), "這個時段不開")
        XCTAssertNotNil(partClosedWhy("p6", "2026-12-08", .eve))
        XCTAssertEqual(partClosedWhy("p5a", "2026-12-07", .eve), "19:00 就關了")
        XCTAssertEqual(partClosedWhy("p44", "2026-12-08", .eve), "17:30 就關了")
        XCTAssertNil(partClosedWhy("p44", "2026-12-09", .eve), "週三開到 21:00")
        XCTAssertNil(partClosedWhy("p11", "2026-12-07", .eve))
        XCTAssertNil(partClosedWhy("p14a", "2026-12-11", .eve))
        XCTAssertEqual(partClosedWhy("p14a", "2026-12-25", .eve), "沒有場次", "國定假日照週日")
        XCTAssertNil(partClosedWhy("p17", "2026-12-07", .am), "沒查到的不講")
        XCTAssertNil(partClosedWhy("沒有這個代號", "2026-12-07", .am))
    }

    func test時段資料_跟時間對得起來() throws {
        let from: [Part: Int] = [.am: 540, .pm: 720, .eve: 1080]
        let to: [Part: Int] = [.am: 720, .pm: 1020, .eve: 1260]
        func minutes(_ s: String) -> Int {
            let b: [Int] = s.components(separatedBy: ":").compactMap { (x: String) -> Int? in Int(x) }
            return b.count == 2 ? b[0] * 60 + b[1] : -1
        }
        func derive(_ spans: [String]) -> [Part] {
            return PARTS.filter { (p: Part) -> Bool in
                let a: Int = from[p] ?? 0
                let b: Int = to[p] ?? 0
                return spans.contains { (s: String) -> Bool in
                    let e: [String] = s.components(separatedBy: "-")
                    if e.count != 2 { return false }
                    return min(b, minutes(e[1])) - max(a, minutes(e[0])) >= 90
                }
            }
        }
        for (id, f) in SeoulChecked.shared.facts {
            for key in Array((f.partsOn ?? [:]).keys) + Array((f.timesOn ?? [:]).keys) {
                XCTAssertTrue(["0", "1", "2", "3", "4", "5", "6", "h"].contains(key), "\(id) \(key)")
            }
            if let t = f.times { XCTAssertEqual(derive(t), f.parts ?? [], id) }
            for (key, t) in f.timesOn ?? [:] {
                XCTAssertEqual(derive(t), f.partsOn?[key] ?? f.parts ?? [], "\(id) \(key)")
            }
        }
    }

    func test自己移的不擋_講短短一句() {
        var t: Trip = ckTrip("2026-12-07", 3)
        ckPut(&t, 1, .am, ckStop("p26c"))
        ckPut(&t, 1, .eve, ckStop("p4c"))
        XCTAssertEqual(closedNotes(t), ["第 1 天 12/7（一）上午「\(ckStop("p26c").n)」還沒開，16:00 才開。"])
        ckPut(&t, 2, .am, ckStop("p16a"))
        t.start = "2026-12-06"
        XCTAssertTrue(closedNotes(t).contains("第 1 天 12/6（日）「鍾路蔘雞湯」公休：每週日休。"), "\(closedNotes(t))")
        XCTAssertTrue(closedNotes(t).contains { (s: String) -> Bool in s.contains("「韓國之家韓定食」公休") })
        XCTAssertTrue(closedNotes(t).allSatisfy { (s: String) -> Bool in !s.contains("休館") })
    }

    func test換一個_附近_排回這趟_避開不開的時段() throws {
        let st: Settings = defaultSettings()
        var t: Trip = ckTrip("2026-12-07", 3)
        ckPut(&t, 1, .pm, ckStop("p26a"))
        let ids: [String] = alternatives(t, st, ckStop("p26a")).map { (p: Place) -> String in p.id }
        XCTAssertFalse(ids.contains("p26c"), "16:00 才開")
        let origin: NearbyOrigin = nearbyOrigin(t, st, 1)
        let noru: Place = try XCTUnwrap(PLACES.first { (p: Place) -> Bool in p.id == "p26c" })
        XCTAssertEqual(nearbyPart(t, 1, origin, nil), .pm)
        XCTAssertEqual(nearbyPart(t, 1, origin, nil, place: noru), .eve)
        var seeds: [Seed] = [
            Seed(id: "s1", n: noru.n, a: "聖水", why: "測試", stop: ckStop("p26c"), from: SeedFrom(day: 2, part: .am))
        ]
        let msg: String = restoreSeed(&t, &seeds, "s1")
        XCTAssertEqual(try XCTUnwrap(findItem(t, "p26c")).s.part, .eve)
        XCTAssertTrue(msg.hasPrefix("第 2 天上午「\(noru.n)」不開（還沒開，16:00 才開），改排在"), msg)
    }

    func test排回這趟_只有一天的不說別天也都休_餐廳說公休() {
        var t: Trip = ckTrip("2026-12-06", 1)
        var seeds: [Seed] = [
            Seed(id: "s1", n: "鍾路蔘雞湯", a: "", why: "測試", stop: ckStop("p4c"), from: SeedFrom(day: 1, part: .pm))
        ]
        XCTAssertEqual(restoreSeed(&t, &seeds, "s1"), "「鍾路蔘雞湯」排回第 1 天下午了，但那天它公休（每週日休）")
    }

    /* ---------- 休館、提醒 ---------- */

    func test中央博物館_只有3_6_9_12月第一個週一_碰到國定假日只提醒() throws {
        XCTAssertEqual(closedWhy("p44", "2026-12-07"), "3、6、9、12 月第 1 個週一休")
        XCTAssertNil(closedWhy("p44", "2027-01-04"))
        XCTAssertNil(closedWhy("p44", "2026-12-14"))
        XCTAssertNotNil(closedWhy("p44", "2027-06-07"))
        XCTAssertNil(closedWhy("p44", "2027-03-01"), "三一節，官方沒講")
        XCTAssertNotNil(cautionWhy("p44", "2027-03-01"))
        XCTAssertNil(cautionWhy("p44", "2026-12-07"))
        let f: PlaceFact = try XCTUnwrap(factOf("p44"))
        XCTAssertEqual(closedText(f), "3、6、9、12 月第 1 個週一，部分節日也休")
        XCTAssertEqual(closedShort(f), "3、6、9、12 月第 1 個週一休")
    }

    func testN首爾塔_只提醒不擋_字不說休館() {
        XCTAssertNil(closedWhy("p11", "2027-02-01"))
        XCTAssertNil(cautionWhy("p11", "2026-12-31"))
        XCTAssertNotNil(cautionWhy("p11", "2027-04-10"), "重開日期沒公布")
        var t: Trip = ckTrip("2027-02-01", 1)
        ckPut(&t, 1, .eve, ckStop("p11"))
        let notes: [String] = closedNotes(t)
        XCTAssertEqual(notes, ["第 1 天 2/1（一）「N 首爾塔」：官網公告 2027 年 1 到 3 月展望台限制使用，重開日期未公布。"])
        XCTAssertEqual(closedLines(t).count, 1)
        XCTAssertFalse(closedLines(t).joined().contains("休館"))
    }

    func test南大門市場不擋_戰爭紀念館連假隔天休_韓國之家假日不猜() {
        XCTAssertNil(closedWhy("p12", "2026-12-06"))
        XCTAssertNil(closedWhy("p45", "2027-03-01"))
        XCTAssertNotNil(closedWhy("p45", "2027-03-02"))
        XCTAssertNotNil(closedWhy("p45", "2027-02-10"))
        XCTAssertNotNil(closedWhy("p16a", "2027-03-01"), "官網沒講清楚的照固定休")
    }

    /* ---------- 須知、日期的字 ---------- */

    func test須知_資料包那句另外放_不掛成核對過() throws {
        for id in ["p2", "p3", "p12", "p27", "p41", "p49", "p50", "p51"] {
            let tip = try XCTUnwrap(tipOf(ckStop(id)), id)
            let extra: String = try XCTUnwrap(tip.extra, id)
            XCTAssertFalse(tip.text.contains(extra), id)
        }
        XCTAssertNil(tipOf(ckStop("p0"))?.extra)
        XCTAssertNil(tipOf(ckStop("p23"))?.extra)
    }

    func test檢查表_字_核對日期_來源一起換() {
        let plain: Fact = Fact(text: "原本", status: "二手核對", checked: "2026-11-14", source: "媒體")
        let k: Fact = datedFact("c2", plain, "2026-12-07")
        XCTAssertEqual(k.status, "看過官方頁")
        XCTAssertEqual(k.checked, "2026-11-25")
        XCTAssertTrue(k.source.contains("overseas.mofa.go.kr"), k.source)
        let a: Fact = datedFact("c1", plain, "2026-12-07")
        XCTAssertEqual(a.checked, "2026-11-14")
        XCTAssertEqual(a.status, "二手核對")
        XCTAssertEqual(datedFact("c2", plain, nil), plain)
        XCTAssertEqual(datedFact("c9", plain, "2026-12-07"), plain)
        for id in ["c1", "c2"] {
            for start in ["2026-12-07", "2027-12-20"] {
                let text: String = datedText(id, "", start)
                XCTAssertTrue(text.count <= 46, "\(text.count) \(text)")
                XCTAssertFalse(text.contains("） "), text)
                XCTAssertFalse(text.contains("{"), text)
            }
        }
    }

    func test文字長度_不寫韓國時間() {
        for (id, f) in SeoulChecked.shared.facts {
            let b: BookInfo? = f.book
            for text in [f.hours, f.last, f.price, b?.cancel, b?.foreigner] {
                XCTAssertTrue((text ?? "").count <= 40, "\(id) \(text ?? "")")
                XCTAssertFalse((text ?? "").contains("韓國時間"), id)
            }
            XCTAssertTrue((b?.how ?? "").count <= 60, id)
            XCTAssertFalse((b?.how ?? "").contains("韓國時間"), id)
            XCTAssertFalse((f.addr ?? "").contains("  "), id)
        }
    }

    /* ---------- 訂位 ---------- */

    func test後苑_去的當天不說已經開賣_沒有免費取消那天() throws {
        var t: Trip = ckTrip("2026-12-07", 3)
        ckPut(&t, 2, .am, ckStop("p6"))
        func text(_ today: String) throws -> String {
            let r: BookRow = try XCTUnwrap(bookPlan(t, [:], today).first)
            XCTAssertNil(r.decideOn)
            return bookOpenText(r, today)
        }
        XCTAssertEqual(try text("2026-12-05"), "已經開賣")
        XCTAssertEqual(try text("2026-12-07"), "已經開賣")
        XCTAssertEqual(try text("2026-12-08"), "網路賣到 12/7，今天 9:00 起現場賣（當地時間）")
        let b: BookInfo = try XCTUnwrap(factOf("p6")?.book)
        XCTAssertEqual(bookOnlineText(b, "2026-12-08", "2026-12-01"), "網路賣到 12/7，當天 9:00 起現場賣（當地時間）")
        XCTAssertNil(bookOnlineText(BookInfo(how: "官網"), "2026-12-08", "2026-12-01"))
    }

    func testJungsik_雙數月開後面兩個月() throws {
        let b: BookInfo = try XCTUnwrap(factOf("p33a")?.book)
        XCTAssertEqual(bookOpen(b, "2027-05-20")?.on, "2027-04-01")
        XCTAssertEqual(bookOpen(b, "2027-06-20")?.on, "2027-04-01")
        XCTAssertEqual(bookOpen(b, "2027-01-20")?.on, "2026-12-01")
        XCTAssertEqual(bookOpen(b, "2027-02-20")?.on, "2026-12-01")
        XCTAssertEqual(bookOpen(b, "2026-12-20")?.on, "2026-10-01")
        XCTAssertEqual(bookOpen(b, "2026-12-20")?.at, "11:00")
    }

    func test有寫怎麼訂但算不出開賣日_沒有網頁的叫他點開那一站() throws {
        var t: Trip = ckTrip("2026-12-07", 3)
        ckPut(&t, 2, .eve, ckStop("p16b"))
        let r: BookRow = try XCTUnwrap(bookPlan(t, [:], "2026-11-25").first)
        XCTAssertNil(r.url)
        XCTAssertEqual(bookOpenText(r, "2026-11-25"), "怎麼訂，在這趟點開這一站看")
    }

    func test開賣提醒只留一句短的() throws {
        var d: AppState = AppState()
        var t: Trip = ckTrip("2026-12-07", 3)
        ckPut(&t, 2, .am, ckStop("p6"))
        d.trip = t
        let r: Reminder = try XCTUnwrap(remindersOf(d, "2026-11-25").first)
        XCTAssertEqual(r.body, "第 2 天 12/8（二）上午要去。到 ticket.uforus.co.kr 訂。")
    }

    func test決定日的提醒_手機當地九點之後才算過() throws {
        var d: AppState = AppState()
        var t: Trip = ckTrip("2026-12-07", 3)
        ckPut(&t, 2, .am, ckStop("x"))
        t.slots[3].items[0].b = true
        d.trip = t
        let fact: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in
            return PlaceFact(
                status: .official, checked: "2026-11-25", src: [], book: BookInfo(how: "官網", decideDays: 3))
        }
        let pacific: TimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -8 * 3600))
        func count(_ zone: TimeZone, _ at: Double) -> Int {
            let list: [Reminder] = remindersOf(
                d, "2026-12-05", now: Date(timeIntervalSince1970: at), fact: fact, zone: zone)
            return list.filter { (r: Reminder) -> Bool in r.id.contains("decide") }.count
        }
        let late: Double = taiwanSeconds("2026-12-05", 10 * 60)
        XCTAssertEqual(count(CK_TAIPEI, late), 0)
        XCTAssertEqual(count(pacific, late), 1, "那邊還沒到 12/5 早上九點")
        XCTAssertEqual(count(pacific, zoneSeconds("2026-12-05", 9 * 60 + 1, pacific)), 0)
        XCTAssertEqual(zoneSeconds("2026-12-05", 540, CK_TAIPEI), taiwanSeconds("2026-12-05", 540))
    }

    /* ---------- 手機自己答 ---------- */

    func test舊存檔的樂天世界_不說要先訂() throws {
        var it: Stop = ckStop("p27")
        it.b = true
        var t: Trip = ckTrip("2026-12-07", 3)
        ckPut(&t, 2, .am, it)
        var d: AppState = AppState()
        d.trip = t
        let one: String = try XCTUnwrap(phoneAnswer("這一站要注意什麼", d, 2, "p27", nil))
        XCTAssertTrue(one.contains("還沒核對過的：先上網買票通常比較便宜；假日人多，去之前查一下"), one)
        XCTAssertFalse(one.contains("要先訂"), one)
    }

    func test自己加的站_不算進沒核對() throws {
        var mine: Stop = ckStop("m1")
        mine.mine = true
        var t: Trip = ckTrip("2026-12-07", 3)
        ckPut(&t, 2, .am, ckStop("p0"))
        ckPut(&t, 2, .pm, mine)
        var d: AppState = AppState()
        d.trip = t
        let text: String = try XCTUnwrap(phoneAnswer("有哪些要先訂", d, 2, nil, nil))
        XCTAssertTrue(text.contains("每一站都核對過"), text)
    }
}
