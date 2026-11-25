// 要先訂的：開賣日、台灣時間、一站一則的提醒、最晚決定日、再查一次的橫幅、跟著日期走的字。
// 核對資料一律用自己編的，不靠 seoul-checked.json 裡有什麼。iOS 版才有。
import XCTest

@testable import RadishCore

private func bStop(_ id: String, _ name: String, book: Bool = true, tip: String? = nil) -> Stop {
    var it: Stop = Stop(
        id: id, n: name, kr: "", a: nil, s: .S, c: .sight, lat: nil, lng: nil,
        status: .kept, swaps: 0, why: "測試"
    )
    if book { it.b = true }
    it.tip = tip
    return it
}

/// 空的五天，12/7（一）到。後苑排第 2 天就是 12/8（二）
private func bTrip(_ start: String = "2026-12-07", _ days: Int = 5) -> Trip {
    var slots: [Slot] = []
    for day in 1...days {
        for part in PARTS {
            slots.append(Slot(day: day, part: part, items: []))
        }
    }
    return Trip(start: start, days: days, arrive: .am, leave: .eve, people: 2, slots: slots)
}

private func bPut(_ t: inout Trip, _ day: Int, _ part: Part, _ it: Stop) {
    guard let si = slotAt(t, day, part) else {
        XCTFail("第 \(day) 天沒有這個時段")
        return
    }
    t.slots[si].items.append(it)
}

private func bFact(_ b: BookInfo?, status: FactStatus = .official) -> PlaceFact {
    return PlaceFact(status: status, checked: "2026-11-25", src: [], book: b)
}

/// 照後苑的規則：去的那天前 6 天，韓國 10 點開賣
private let GARDEN: BookInfo = BookInfo(how: "官網", url: "https://www.royal.example.kr/ko", opensDays: 6, opensAt: "10:00")

private func gardenFact(_ id: String) -> PlaceFact? {
    return id == "g" ? bFact(GARDEN) : nil
}

private func noFact(_ id: String) -> PlaceFact? {
    return nil
}

private func oneTrip(_ day: Int, _ it: Stop) -> AppState {
    var t: Trip = bTrip()
    bPut(&t, day, .am, it)
    var d: AppState = AppState()
    d.trip = t
    return d
}

private func garden(_ day: Int) -> AppState {
    return oneTrip(day, bStop("g", "昌德宮與後苑"))
}

/// 台灣時間的那一刻
private func tw(_ on: String, _ at: String) -> Date {
    return Date(timeIntervalSince1970: taiwanSeconds(on, bookMinutes(at) ?? 0))
}

/// 手機在台灣。CI 的機器是別的時區
private let TAIPEI: TimeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone.current

final class BookTests: XCTestCase {
    /* ---------- 開賣日 ---------- */

    func test前幾天開賣_跨月_跨年() {
        let b: BookInfo = BookInfo(how: "官網", opensDays: 6, opensAt: "10:00")
        XCTAssertEqual(bookOpen(b, "2026-12-08")?.on, "2026-12-02")
        XCTAssertEqual(bookOpen(b, "2026-12-08")?.at, "10:00")
        XCTAssertEqual(bookOpen(b, "2026-12-03")?.on, "2026-11-27")
        XCTAssertEqual(bookOpen(b, "2027-01-03")?.on, "2026-12-28")
        XCTAssertEqual(bookOpen(b, "2028-03-02")?.on, "2028-02-25", "閏年")
        let same: BookInfo = BookInfo(how: "現場", opensDays: 0)
        XCTAssertEqual(bookOpen(same, "2026-12-08")?.on, "2026-12-08")
        XCTAssertNil(bookOpen(same, "2026-12-08")?.at, "沒寫幾點")
    }

    func test前幾個月的幾號開賣_跨年_那個月沒有那一號就取最後一天() {
        let b: BookInfo = BookInfo(how: "官網", opensMonths: 1, opensDay: 15)
        XCTAssertEqual(bookOpen(b, "2026-12-08")?.on, "2026-11-15")
        XCTAssertEqual(bookOpen(b, "2027-01-08")?.on, "2026-12-15")
        let end: BookInfo = BookInfo(how: "官網", opensMonths: 1, opensDay: 31)
        XCTAssertEqual(bookOpen(end, "2026-12-08")?.on, "2026-11-30")
        XCTAssertEqual(bookOpen(end, "2027-03-08")?.on, "2027-02-28")
        XCTAssertEqual(bookOpen(end, "2028-03-08")?.on, "2028-02-29")
        XCTAssertEqual(bookOpen(end, "2027-01-08")?.on, "2026-12-31")
        let far: BookInfo = BookInfo(how: "官網", opensMonths: 14, opensDay: 1)
        XCTAssertEqual(bookOpen(far, "2027-01-08")?.on, "2025-11-01")
        let now: BookInfo = BookInfo(how: "官網", opensMonths: 0, opensDay: 1)
        XCTAssertEqual(bookOpen(now, "2027-01-08")?.on, "2027-01-01")
    }

    func test開賣日不知道或寫得不對_就是不知道() {
        XCTAssertNil(bookOpen(BookInfo(how: "官網"), "2026-12-08"))
        XCTAssertNil(bookOpen(BookInfo(how: "官網", opensAt: "10:00"), "2026-12-08"), "只知道幾點不算")
        XCTAssertNil(bookOpen(BookInfo(how: "官網", opensMonths: 1), "2026-12-08"), "不知道幾號不猜")
        XCTAssertNil(bookOpen(BookInfo(how: "官網", opensDay: 1), "2026-12-08"))
        XCTAssertNil(bookOpen(BookInfo(how: "官網", opensDays: -1), "2026-12-08"))
        XCTAssertNil(bookOpen(BookInfo(how: "官網", opensMonths: 1, opensDay: 0), "2026-12-08"))
        let odd: BookInfo = BookInfo(how: "官網", opensDays: 6, opensAt: "上午十點")
        XCTAssertEqual(bookOpen(odd, "2026-12-08")?.on, "2026-12-02")
        XCTAssertNil(bookOpen(odd, "2026-12-08")?.at, "時間看不懂就當沒寫")
    }

    func test最晚要決定的那天() {
        XCTAssertEqual(bookDecide(BookInfo(how: "官網", decideDays: 3), "2026-12-02"), "2026-11-29")
        XCTAssertEqual(bookDecide(BookInfo(how: "官網", decideDays: 0), "2026-12-02"), "2026-12-02")
        XCTAssertNil(bookDecide(BookInfo(how: "官網"), "2026-12-02"))
        XCTAssertNil(bookDecide(BookInfo(how: "官網", decideDays: -2), "2026-12-02"))
    }

    /* ---------- 韓國時間換台灣時間 ---------- */

    func test韓國時間換台灣時間_早一小時_過半夜是前一天() {
        XCTAssertEqual(koreaToTaiwan("2026-12-02", "10:00")?.on, "2026-12-02")
        XCTAssertEqual(koreaToTaiwan("2026-12-02", "10:00")?.at, "9:00")
        XCTAssertEqual(koreaToTaiwan("2026-12-02", "01:00")?.on, "2026-12-02")
        XCTAssertEqual(koreaToTaiwan("2026-12-02", "01:00")?.at, "0:00")
        XCTAssertEqual(koreaToTaiwan("2026-12-01", "00:30")?.on, "2026-11-30")
        XCTAssertEqual(koreaToTaiwan("2026-12-01", "00:30")?.at, "23:30")
        XCTAssertEqual(koreaToTaiwan("2027-01-01", "00:00")?.on, "2026-12-31")
        XCTAssertEqual(koreaToTaiwan("2027-01-01", "00:00")?.at, "23:00")
        XCTAssertNil(koreaToTaiwan("2026-12-01", "24:00"))
        XCTAssertNil(koreaToTaiwan("2026-12-01", "10:60"))
        XCTAssertNil(koreaToTaiwan("2026-12-01", "10"))
    }

    func test秒數對得上_台灣和韓國是同一刻() {
        XCTAssertEqual(taiwanSeconds("2026-12-02", 8 * 60 + 45), 1_796_172_300)
        XCTAssertEqual(koreaSeconds("2026-12-02", 9 * 60 + 45), 1_796_172_300)
        XCTAssertEqual(koreaLocal(1_796_172_300).on, "2026-12-02")
        XCTAssertEqual(koreaLocal(1_796_172_300).minutes, 9 * 60 + 45)
    }

    /* ---------- 這趟要先訂的 ---------- */

    func test要先訂的_還沒開賣_已經開賣_不知道() throws {
        var t: Trip = bTrip()
        bPut(&t, 2, .am, bStop("g", "昌德宮與後苑"))
        bPut(&t, 3, .pm, bStop("x", "公演"))
        bPut(&t, 4, .pm, bStop("n", "景福宮", book: false))
        let rows: [BookRow] = bookPlan(t, ["b_x": true], "2026-11-25", fact: gardenFact)
        XCTAssertEqual(rows.count, 2, "只有要先訂的")
        let g: BookRow = try XCTUnwrap(rows.first)
        XCTAssertEqual(g.visit, "2026-12-08")
        XCTAssertEqual(g.stage, BookStage.notYet)
        XCTAssertEqual(g.openOn, "2026-12-02")
        XCTAssertEqual(g.openAt, "9:00")
        XCTAssertFalse(g.checked)
        let x: BookRow = try XCTUnwrap(rows.last)
        XCTAssertEqual(x.stage, BookStage.unknown)
        XCTAssertTrue(x.checked)

        let before: BookRow? = bookPlan(t, [:], "2026-12-02", now: tw("2026-12-02", "8:59"), fact: gardenFact).first
        XCTAssertEqual(before?.stage, BookStage.notYet)
        let after: BookRow? = bookPlan(t, [:], "2026-12-02", now: tw("2026-12-02", "9:00"), fact: gardenFact).first
        XCTAssertEqual(after?.stage, BookStage.open)
    }

    func test沒標要先訂的_有訂位資料也不管() {
        var t: Trip = bTrip()
        bPut(&t, 2, .am, bStop("g", "昌德宮與後苑", book: false))
        XCTAssertEqual(bookPlan(t, [:], "2026-11-25", fact: gardenFact), [])
        var d: AppState = AppState()
        d.trip = t
        XCTAssertEqual(remindersOf(d, "2026-11-25", fact: gardenFact), [])
    }

    func test那一列的字_一律寫台灣時間_最多兩行() throws {
        let b: BookInfo = BookInfo(how: "官網", opensDays: 6, opensAt: "10:00", decideDays: 3)
        let fact: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in bFact(b) }
        var t: Trip = bTrip()
        bPut(&t, 2, .am, bStop("g", "昌德宮與後苑"))
        func note(_ today: String, _ checks: [String: Bool]) -> String {
            let rows: [BookRow] = bookPlan(t, checks, today, fact: fact)
            guard let r = rows.first else { return "" }
            return bookNote(r, today)
        }
        XCTAssertEqual(note("2026-11-25", [:]), "第 2 天 12/8（二）上午・免費取消到 12/5\n12/2（三）9:00 開賣（台灣時間）")
        XCTAssertEqual(note("2026-12-02", [:]), "第 2 天 12/8（二）上午・免費取消到 12/5\n今天 9:00 開賣（台灣時間）")
        XCTAssertEqual(note("2026-12-05", [:]), "第 2 天 12/8（二）上午・免費取消到 12/5\n已經開賣")
        XCTAssertEqual(note("2026-12-06", [:]), "第 2 天 12/8（二）上午・免費取消的期限過了\n已經開賣")
        XCTAssertEqual(note("2026-11-25", ["b_g": true]), "第 2 天 12/8（二）上午・免費取消到 12/5")
    }

    func test那一列的字_不知道的照實講() throws {
        var t: Trip = bTrip()
        bPut(&t, 2, .am, bStop("g", "昌德宮與後苑"))
        let r: BookRow = try XCTUnwrap(bookPlan(t, [:], "2026-11-25", fact: noFact).first)
        XCTAssertEqual(bookNote(r, "2026-11-25"), "第 2 天 12/8（二）上午\n開賣時間還不知道")
        let day: BookInfo = BookInfo(how: "官網", opensDays: 6)
        let s: BookRow = try XCTUnwrap(
            bookPlan(t, [:], "2026-11-25", fact: { (_: String) -> PlaceFact? in bFact(day) }).first)
        XCTAssertEqual(bookOpenText(s, "2026-11-25"), "12/2（三）開賣，幾點還不知道")
        XCTAssertEqual(bookOpenText(s, "2026-12-02"), "今天開賣，幾點還不知道")
    }

    func test下面那句_有資料和沒資料講的不一樣() {
        var t: Trip = bTrip()
        bPut(&t, 2, .am, bStop("g", "昌德宮與後苑"))
        let known: String = bookFooter(bookPlan(t, [:], "2026-11-25", fact: gardenFact))
        let none: String = bookFooter(bookPlan(t, [:], "2026-11-25", fact: noFact))
        XCTAssertNotEqual(known, none)
        XCTAssertTrue(none.contains("自己查"), none)
        XCTAssertTrue(known.contains("自己查"), known)
    }

    func test訂票網頁_只收網址() {
        XCTAssertEqual(bookHost("https://www.klook.com/a?b=1"), "klook.com")
        XCTAssertEqual(bookHost("http://royal.example.kr"), "royal.example.kr")
        XCTAssertNil(bookHost("royal.example.kr"))
        XCTAssertNil(bookHost("tel:119"))
        XCTAssertNil(bookHost("javascript:alert(1)"))
        XCTAssertNil(bookHost(""))
        XCTAssertNil(bookHost(nil))
    }

    /* ---------- 提醒 ---------- */

    func test後苑第1天和第5天_都在開賣前15分鐘提醒() throws {
        let days: [(day: Int, on: String)] = [(day: 1, on: "2026-12-01"), (day: 5, on: "2026-12-05")]
        for x in days {
            let list: [Reminder] = remindersOf(garden(x.day), "2026-11-25", fact: gardenFact)
            XCTAssertEqual(list.count, 1, "第 \(x.day) 天")
            let r: Reminder = try XCTUnwrap(list.first)
            XCTAssertEqual(r.on, x.on)
            XCTAssertEqual(r.at, taiwanSeconds(x.on, 8 * 60 + 45))
        }
    }

    func test開賣提醒的字() throws {
        let r: Reminder = try XCTUnwrap(remindersOf(garden(2), "2026-11-25", fact: gardenFact).first)
        XCTAssertEqual(r.title, "昌德宮與後苑 9:00（台灣時間）開賣")
        XCTAssertEqual(r.body, "第 2 天 12/8（二）上午要去。到官網訂。")
        XCTAssertEqual(remindWhen(r), "12/2（三）早上 8:45（台灣時間）")
    }

    func test怎麼訂_已經是一句就照寫_沒寫就用網站名() throws {
        func body(_ b: BookInfo) -> String {
            let fact: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in bFact(b) }
            return remindersOf(garden(2), "2026-11-25", fact: fact).first?.body ?? ""
        }
        let full: BookInfo = BookInfo(how: "官網預約，每人 10 張。", opensDays: 6, opensAt: "10:00")
        XCTAssertTrue(body(full).hasSuffix("要去。官網預約，每人 10 張。"), body(full))
        let host: BookInfo = BookInfo(how: "", url: "https://www.klook.com/x", opensDays: 6, opensAt: "10:00")
        XCTAssertTrue(body(host).hasSuffix("要去。到 klook.com 訂。"), body(host))
        let empty: BookInfo = BookInfo(how: "", opensDays: 6, opensAt: "10:00")
        XCTAssertTrue(body(empty).hasSuffix("要去。"), body(empty))
    }

    func test提醒的時間給人看_早上中午下午晚上凌晨() {
        func text(_ on: String, _ minutes: Int) -> String {
            return remindWhen(Reminder(id: "t", on: on, at: taiwanSeconds(on, minutes), title: "", body: ""))
        }
        XCTAssertEqual(text("2026-12-02", 15), "12/2（三）凌晨 0:15（台灣時間）")
        XCTAssertEqual(text("2026-12-02", 12 * 60 + 45), "12/2（三）中午 12:45（台灣時間）")
        XCTAssertEqual(text("2026-12-02", 14 * 60 + 45), "12/2（三）下午 2:45（台灣時間）")
        XCTAssertEqual(text("2026-12-02", 23 * 60 + 15), "12/2（三）晚上 11:15（台灣時間）")
        let plain: Reminder = Reminder(id: "t", on: "2026-12-02", at: nil, title: "", body: "")
        XCTAssertEqual(remindWhen(plain), "12/2（三）早上 9 點")
    }

    func test韓國半夜開賣_提醒落在台灣前一天晚上() throws {
        let b: BookInfo = BookInfo(how: "官網", opensDays: 7, opensAt: "00:10")
        let fact: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in bFact(b) }
        let r: Reminder = try XCTUnwrap(remindersOf(garden(2), "2026-11-25", fact: fact).first)
        // 韓國 12/1 00:10＝台灣 11/30 23:10，前 15 分鐘是 22:55
        XCTAssertEqual(r.on, "2026-11-30")
        XCTAssertEqual(r.at, taiwanSeconds("2026-11-30", 22 * 60 + 55))
        XCTAssertTrue(r.title.contains("23:10"), r.title)
        let when: DateComponents = try XCTUnwrap(reminderTime(r))
        XCTAssertEqual(when.month, 11)
        XCTAssertEqual(when.day, 30)
        XCTAssertEqual(when.hour, 23)
        XCTAssertEqual(when.minute, 55)
    }

    func test有開賣日沒有幾點_那天早上九點() throws {
        let b: BookInfo = BookInfo(how: "官網", opensDays: 6)
        let fact: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in bFact(b) }
        let list: [Reminder] = remindersOf(garden(2), "2026-11-25", fact: fact)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.on, "2026-12-02")
        XCTAssertNil(list.first?.at)
        // 那天早上九點過了：併進明天那一則
        let late: [Reminder] = remindersOf(garden(2), "2026-12-02", now: tw("2026-12-02", "9:01"), fact: fact, zone: TAIPEI)
        XCTAssertEqual(late.count, 1)
        XCTAssertEqual(late.first?.on, "2026-12-03")
        XCTAssertEqual(late.first?.id, "0-all")
    }

    func test開賣過了還沒勾_併進合併那一則_提醒過的那一刻不再排() throws {
        // 8:45 過了、9:00 還沒到：開賣前那則不排了，也不會變成沒有提醒
        let edges: [String] = ["8:45", "8:50", "9:00", "20:00"]
        for at in edges {
            let list: [Reminder] = remindersOf(garden(2), "2026-12-02", now: tw("2026-12-02", at), fact: gardenFact)
            XCTAssertEqual(list.count, 1, at)
            XCTAssertNil(list.first?.at, at)
            XCTAssertEqual(list.first?.on, "2026-12-03", at)
            XCTAssertTrue(list.first?.body.contains("昌德宮與後苑") ?? false, at)
        }
        let early: [Reminder] = remindersOf(garden(2), "2026-12-02", now: tw("2026-12-02", "8:44"), fact: gardenFact)
        XCTAssertEqual(early.first?.at, taiwanSeconds("2026-12-02", 8 * 60 + 45))
    }

    func test不知道的和開賣過了的_同一趟只有一則_還沒開賣的不在裡面() throws {
        var t: Trip = bTrip()
        bPut(&t, 1, .am, bStop("x", "公演"))
        bPut(&t, 2, .am, bStop("g", "昌德宮與後苑"))
        bPut(&t, 3, .am, bStop("y", "韓定食"))
        var d: AppState = AppState()
        d.trip = t
        let list: [Reminder] = remindersOf(d, "2026-11-16", fact: gardenFact)
        XCTAssertEqual(list.count, 2)
        let all: Reminder = try XCTUnwrap(list.first)
        XCTAssertEqual(all.on, "2026-11-30")
        XCTAssertTrue(all.body.contains("有 2 站"), all.body)
        XCTAssertTrue(all.body.contains("公演、韓定食"), all.body)
        XCTAssertFalse(all.body.contains("後苑"), all.body)
    }

    func test勾了_拔了_已經出發_都不排() {
        var checked: AppState = garden(2)
        checked.checks["b_g"] = true
        XCTAssertEqual(remindersOf(checked, "2026-11-25", fact: gardenFact), [])
        var pulled: AppState = garden(2)
        if var t = pulled.trip, let x = findItem(t, "g") {
            t.slots[x.si].items[x.ii].status = .pulled
            pulled.trip = t
        } else {
            XCTFail("找不到那一站")
        }
        XCTAssertEqual(remindersOf(pulled, "2026-11-25", fact: gardenFact), [])
        XCTAssertEqual(remindersOf(garden(5), "2026-12-07", fact: gardenFact), [], "出發那天")
        XCTAssertEqual(remindersOf(garden(5), "2027-01-01", fact: gardenFact), [], "早就回來了")
        XCTAssertEqual(remindersOf(AppState(), "2026-11-25", fact: gardenFact), [], "沒有這趟")
    }

    func test明天就出發_開賣過了的沒有提醒() {
        XCTAssertEqual(remindersOf(garden(1), "2026-12-06", fact: gardenFact), [])
    }

    func test其他排好的也提醒_收起來的不提醒_同名同日分得開() throws {
        var d: AppState = garden(2)
        let trip: Trip = try XCTUnwrap(d.trip)
        d.shelf = [Shelved(id: "s1", trip: trip), Shelved(id: "s2", trip: trip, shut: true)]
        let list: [Reminder] = remindersOf(remindState(d), "2026-11-25", fact: gardenFact)
        XCTAssertEqual(list.count, 2, "收起來的那趟不算")
        XCTAssertEqual(list.first?.title, list.last?.title)
        XCTAssertEqual(list.first?.on, list.last?.on)
        XCTAssertNotEqual(list.first?.id, list.last?.id)
        // 架上那趟的勾選跟著自己那一趟
        d.shelf[0].checks["b_g"] = true
        XCTAssertEqual(remindersOf(remindState(d), "2026-11-25", fact: gardenFact).count, 1)
    }

    func test同一趟同一站排兩次_提醒分得開() {
        var t: Trip = bTrip()
        bPut(&t, 2, .am, bStop("g", "昌德宮與後苑"))
        bPut(&t, 2, .pm, bStop("g", "昌德宮與後苑"))
        var d: AppState = AppState()
        d.trip = t
        let ids: [String] = remindersOf(d, "2026-11-25", fact: gardenFact).map { (r: Reminder) -> String in r.id }
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, 2)
    }

    func test最多40則_照時間先後留前面的() throws {
        // 第 n 站在出發前 n 天開賣
        var t: Trip = bTrip()
        for n in 1...50 {
            bPut(&t, 1, .am, bStop("p\(n)", "站\(n)"))
        }
        var d: AppState = AppState()
        d.trip = t
        let fact: (String) -> PlaceFact? = { (id: String) -> PlaceFact? in
            let n: Int = Int(id.dropFirst()) ?? 0
            return bFact(BookInfo(how: "官網", opensDays: n, opensAt: "10:00"))
        }
        let list: [Reminder] = remindersOf(d, "2026-10-01", fact: fact)
        XCTAssertEqual(list.count, 40)
        XCTAssertTrue(list.first?.title.hasPrefix("站50 ") ?? false)
        XCTAssertTrue(list.last?.title.hasPrefix("站11 ") ?? false)
        for i in 1..<list.count {
            XCTAssertLessThan(remindSeconds(list[i - 1]), remindSeconds(list[i]))
        }
    }

    /* ---------- 最晚要決定的那天 ---------- */

    private func decideFact(_ days: Int, _ opens: Int) -> (String) -> PlaceFact? {
        let b: BookInfo = BookInfo(how: "官網", opensDays: opens, opensAt: "10:00", decideDays: days)
        return { (_: String) -> PlaceFact? in bFact(b) }
    }

    func test最晚決定日_那天早上九點提醒_不保證() throws {
        let list: [Reminder] = remindersOf(garden(2), "2026-11-25", fact: decideFact(3, 6))
        XCTAssertEqual(list.count, 2)
        let r: Reminder = try XCTUnwrap(list.last)
        XCTAssertEqual(r.on, "2026-12-05")
        XCTAssertNil(r.at)
        XCTAssertTrue(r.body.contains("官方頁寫今天是免費取消的最後一天"), r.body)
        XCTAssertTrue(r.body.contains("以訂的那邊為準"), r.body)
    }

    func test最晚決定日_二手資料不說是官方頁() throws {
        let b: BookInfo = BookInfo(how: "官網", decideDays: 3)
        let fact: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in bFact(b, status: .second) }
        let list: [Reminder] = remindersOf(garden(2), "2026-11-25", fact: fact)
        let r: Reminder = try XCTUnwrap(list.last)
        XCTAssertEqual(r.on, "2026-12-05")
        XCTAssertFalse(r.body.contains("官方頁"), r.body)
    }

    func test最晚決定日跟開賣同一天_只留開賣那則() {
        let list: [Reminder] = remindersOf(garden(2), "2026-11-25", fact: decideFact(6, 6))
        XCTAssertEqual(list.count, 1)
        XCTAssertNotNil(list.first?.at)
    }

    func test最晚決定日過了或勾了_不提醒() {
        func decides(_ d: AppState, _ today: String, _ at: String) -> Int {
            let list: [Reminder] = remindersOf(d, today, now: tw(today, at), fact: decideFact(3, 6), zone: TAIPEI)
            return list.filter { (r: Reminder) -> Bool in r.id.contains("decide") }.count
        }
        XCTAssertEqual(decides(garden(2), "2026-12-04", "20:00"), 1)
        XCTAssertEqual(decides(garden(2), "2026-12-05", "8:00"), 1, "那天九點前還排得到")
        XCTAssertEqual(decides(garden(2), "2026-12-05", "9:00"), 0)
        XCTAssertEqual(decides(garden(2), "2026-12-06", "8:00"), 0)
        var checked: AppState = garden(2)
        checked.checks["b_g"] = true
        XCTAssertEqual(decides(checked, "2026-11-25", "8:00"), 0)
    }

    func test旅途中_開賣和最後決定日還沒到的提醒還在_整趟走完就沒有() throws {
        // 12/7 到 12/11。第 5 天 12/11 要去：12/9 開賣、12/10 最後決定
        let fact: (String) -> PlaceFact? = decideFact(1, 2)
        let list: [Reminder] = remindersOf(garden(5), "2026-12-08", fact: fact)
        XCTAssertEqual(list.count, 2, "旅途第 2 天，兩則都還在")
        XCTAssertEqual(list.first?.at, taiwanSeconds("2026-12-09", 8 * 60 + 45))
        let decide: Reminder = try XCTUnwrap(list.last)
        XCTAssertEqual(decide.on, "2026-12-10")
        XCTAssertNil(decide.at)
        XCTAssertEqual(remindersOf(garden(5), "2026-12-07", fact: fact).count, 2, "出發那天")
        // 開賣過了只剩最後決定日，不會多出合併那一則
        let later: [Reminder] = remindersOf(garden(5), "2026-12-09", now: tw("2026-12-09", "20:00"), fact: fact)
        XCTAssertEqual(later, [decide])
        // 勾了就沒有
        var checked: AppState = garden(5)
        checked.checks["b_g"] = true
        XCTAssertEqual(remindersOf(checked, "2026-12-08", fact: fact), [])
        // 最後一天還算在旅途中，隔天才是走完
        let last: (String) -> PlaceFact? = decideFact(0, 2)
        XCTAssertEqual(remindersOf(garden(5), "2026-12-11", now: tw("2026-12-11", "8:00"), fact: last).count, 1)
        XCTAssertEqual(remindersOf(garden(5), "2026-12-12", fact: last), [])
        // 走完了：就算資料寫的日子還沒到也不提醒（去的那天排在行程外面）
        var odd: AppState = garden(5)
        odd.trip?.days = 1
        XCTAssertEqual(remindersOf(odd, "2026-12-07", fact: fact).count, 2)
        XCTAssertEqual(remindersOf(odd, "2026-12-08", fact: fact), [])
    }

    /* ---------- 出發前再查一次 ---------- */

    private let calm: SeoulChecked = SeoulChecked(
        checked: "2026-11-25", facts: [:], drop: [], add: [], lunar: [:], holidays: [], dated: [])

    func test核對過的站_休館就明講_沒休就不提_沒核對的照舊列出() {
        var t: Trip = bTrip()
        bPut(&t, 2, .am, bStop("k", "景福宮", book: false, tip: "週二休館"))
        bPut(&t, 3, .am, bStop("m", "博物館", book: false, tip: "有休館日"))
        bPut(&t, 4, .am, bStop("u", "美術館", book: false, tip: "有休館日"))
        bPut(&t, 4, .pm, bStop("z", "咖啡廳", book: false))
        let fact: (String) -> PlaceFact? = { (id: String) -> PlaceFact? in
            if id != "k" && id != "m" { return nil }
            return PlaceFact(status: .official, checked: "2026-11-25", src: [], closed: [2])
        }
        XCTAssertEqual(closedLines(t, fact: fact, calm), ["第 2 天景福宮那天休館（每週二休）"])
        let left: [String] = recheckStops(t, fact: fact).map { (x: Stop) -> String in x.id }
        XCTAssertEqual(left, ["u"])
        XCTAssertEqual(
            recheckText(t, 3, fact: fact, calm),
            "還有 3 天出發。第 2 天景福宮那天休館（每週二休）。這 1 站有訂位、休館日或班次，再查一次：美術館。")
    }

    func test沒查到的不當成核對過_休館照closedWhy_都沒有就沒有橫幅() {
        var t: Trip = bTrip()
        bPut(&t, 2, .am, bStop("k", "景福宮", book: false, tip: "週二休館"))
        let none: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in
            PlaceFact(status: .none, checked: "2026-11-25", src: [], closed: [2])
        }
        XCTAssertEqual(closedLines(t, fact: none, calm), ["第 2 天景福宮那天休館（每週二休）"], "不看核對狀態")
        XCTAssertEqual(recheckStops(t, fact: none).count, 1)
        // 核對過但沒查到哪天休，須知又寫了休館：還是要他再查
        let blank: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in
            PlaceFact(status: .official, checked: "2026-11-25", src: [])
        }
        XCTAssertEqual(recheckStops(t, fact: blank).count, 1)
        let open: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in
            PlaceFact(status: .second, checked: "2026-11-25", src: [], closed: [])
        }
        XCTAssertNil(recheckText(t, 3, fact: open, calm))
        XCTAssertNil(recheckText(bTrip(), 3, fact: noFact, calm))
    }

    func test去過的不再說休館_歇業的講去不了() {
        var t: Trip = bTrip()
        bPut(&t, 2, .am, bStop("k", "老店", book: false))
        let gone: (String) -> PlaceFact? = { (_: String) -> PlaceFact? in
            PlaceFact(status: .second, checked: "2026-11-25", src: [], gone: "已歇業")
        }
        XCTAssertEqual(closedLines(t, fact: gone, calm), ["第 2 天老店去不了（已歇業）"])
        if let x = findItem(t, "k") {
            t.slots[x.si].items[x.ii].status = .pulled
        }
        XCTAssertEqual(closedLines(t, fact: gone, calm), [])
    }

    /* ---------- 改完才出現的提醒 ---------- */

    /// 景福宮週二休
    private func tuesday(_ id: String, _ iso: String) -> String? {
        return id == "k" && dowOf(iso) == 2 ? "每週二休" : nil
    }

    private func palace(_ day: Int) -> Trip {
        var t: Trip = bTrip()
        bPut(&t, day, .am, bStop("k", "景福宮", book: false))
        return t
    }

    func test這一輪才出現的才講_原本就有的不重複() {
        let shut: Trip = palace(2)
        let open: Trip = palace(3)
        XCTAssertEqual(newWarnings(open, shut, closed: tuesday), closedNotes(shut, closed: tuesday))
        XCTAssertEqual(newWarnings(open, shut, closed: tuesday).count, 1)
        XCTAssertEqual(newWarnings(shut, shut, closed: tuesday), [], "沒有改動")
        XCTAssertEqual(newWarnings(shut, open, closed: tuesday), [], "移走了就不講")
        var more: Trip = shut
        bPut(&more, 4, .pm, bStop("z", "咖啡廳", book: false))
        XCTAssertEqual(newWarnings(shut, more, closed: tuesday), [], "改的是別站，休館那站不重複講")
        XCTAssertEqual(newClosedNotes(shut, more, closed: tuesday), [])
    }

    func test太滿的也只講這一輪才出現的() {
        func big(_ n: Int) -> Trip {
            var t: Trip = bTrip()
            for i in 0..<n {
                var it: Stop = bStop("L\(i)", "大站\(i)", book: false)
                it.s = .L
                bPut(&t, 1, .pm, it)
            }
            return t
        }
        XCTAssertEqual(newWarnings(big(2), big(3), closed: tuesday).count, 1)
        XCTAssertEqual(newWarnings(big(3), big(4), closed: tuesday).count, 1, "變得更滿要講")
        XCTAssertEqual(newWarnings(big(3), big(3), closed: tuesday), [])
        XCTAssertEqual(newWarnings(big(3), big(2), closed: tuesday), [])
        XCTAssertEqual(newClosedNotes(big(2), big(3), closed: tuesday), [], "太滿不是休館")
    }

    func test只改出發日_星期幾變了才講休館() {
        let open: Trip = palace(3)
        var moved: Trip = open
        moved.start = "2026-12-06"
        XCTAssertEqual(newClosedNotes(open, moved, closed: tuesday).count, 1, "第 3 天變成週二")
        var named: Trip = moved
        named.name = "跟媽媽"
        XCTAssertEqual(newClosedNotes(moved, named, closed: tuesday), [], "只改名字")
    }

    func test休館接在後面_兩條以內照寫_超過就講幾站() {
        XCTAssertEqual(closedTail([]), "")
        XCTAssertEqual(closedTail(["甲。", "乙。"]), "甲。乙。")
        XCTAssertEqual(closedTail(["甲。", "乙。", "丙。"]), "有 3 件開放時間要注意的，看每天最上面那一行。")
    }

    /* ---------- 跟著日期走的字 ---------- */

    private let dated: SeoulChecked = SeoulChecked(
        checked: "2026-11-25", facts: [:], drop: [], add: [], lunar: [:], holidays: [],
        dated: [
            DatedText(id: "c1", until: "9999-12-31", before: "{start} 到，{minus3} 起可以填", after: ""),
            DatedText(id: "c2", until: "2026-12-31", before: "不用辦，你 {start} 到", after: "要再查，你 {start} 到"),
        ])

    func test跟著日期走的字_期限當天還是前一種_隔天換() {
        XCTAssertEqual(datedText("c2", "原本", "2026-12-07", dated), "不用辦，你 12/7（一） 到")
        XCTAssertEqual(datedText("c2", "原本", "2026-12-31", dated), "不用辦，你 12/31（四） 到")
        XCTAssertEqual(datedText("c2", "原本", "2027-01-01", dated), "要再查，你 1/1（五） 到")
        XCTAssertEqual(datedText("c1", "原本", "2027-01-01", dated), "1/1（五） 到，12/29（二） 起可以填")
        XCTAssertEqual(datedText("c2", "原本", nil, dated), "原本", "沒有這趟")
        XCTAssertEqual(datedText("c3", "原本", "2027-01-01", dated), "原本", "沒有跟日期走的版本")
    }

    func test過了期限才比較急() {
        XCTAssertFalse(datedLate("c2", "2026-12-31", dated))
        XCTAssertTrue(datedLate("c2", "2027-01-01", dated))
        XCTAssertFalse(datedLate("c2", nil, dated))
        XCTAssertFalse(datedLate("c1", "2027-01-01", dated))
        XCTAssertFalse(datedLate("c9", "2027-01-01", dated))
    }
}
