// 2026-11-25 獨立 review 的修正：舊存檔的要先訂、休前橫幅和手機自己答的時段與公告、訂票那一句、文字。
// 用真的核對資料。iOS 版才有。
import XCTest

@testable import RadishCore

private func rvStop(_ id: String) -> Stop {
    if let p: Place = PLACES.first(where: { (x: Place) -> Bool in x.id == id }) { return planToStop(p, "測試") }
    return Stop(
        id: id, n: id, kr: "", a: nil, s: .S, c: .sight, lat: nil, lng: nil, status: .kept, swaps: 0, why: "測試")
}

/// 三天的行程，這一站排在第 1 天的 part
private func rvTrip(_ start: String, _ part: Part, _ it: Stop) -> Trip {
    var slots: [Slot] = []
    for day in 1...3 {
        for p in PARTS {
            let items: [Stop] = day == 1 && p == part ? [it] : []
            slots.append(Slot(day: day, part: p, items: items))
        }
    }
    return Trip(start: start, days: 3, arrive: .am, leave: .eve, people: 2, slots: slots)
}

private func rvState(_ t: Trip) -> AppState {
    var d: AppState = AppState()
    d.trip = t
    return d
}

final class ReviewFixTests: XCTestCase {
    /* ---------- 舊存檔的要先訂 ---------- */

    func test舊存檔的樂天世界_照現在的資料_不用先訂_打的勾不動() {
        var it: Stop = rvStop("p27")
        it.b = true
        XCTAssertFalse(needsBook(it))
        let t: Trip = rvTrip("2026-12-07", .am, it)
        XCTAssertEqual(bookPlan(t, [:], "2026-11-25"), [])
        XCTAssertTrue(unbookedOf(t, [:]).isEmpty)
        XCTAssertTrue(recheckStops(t).isEmpty)
        var d: AppState = rvState(t)
        d.checks = ["b_p27": true]
        XCTAssertEqual(remindersOf(d, "2026-11-25"), [])
        XCTAssertEqual(d.checks, ["b_p27": true])
    }

    func test舊存檔少了標記的_照現在的資料要先訂() {
        var it: Stop = rvStop("p6")
        it.b = nil
        XCTAssertTrue(needsBook(it))
        let t: Trip = rvTrip("2026-12-08", .am, it)
        XCTAssertEqual(bookPlan(t, ["b_p6": true], "2026-11-25").first?.checked, true, "勾還在")
        XCTAssertEqual(unbookedOf(t, [:]).count, 1)
    }

    func test拆掉的舊代號和自己加的_看站自己的標記() {
        for id in ["p16", "m1"] {
            var it: Stop = rvStop(id)
            XCTAssertFalse(needsBook(it), id)
            it.b = true
            XCTAssertTrue(needsBook(it), id)
            XCTAssertEqual(unbookedOf(rvTrip("2026-12-07", .am, it), [:]).count, 1, id)
        }
    }

    /* ---------- 時段不開、公告 ---------- */

    func test休前橫幅_時段不開直接講原因_不重複_不說整個不開() {
        XCTAssertEqual(
            closedLines(rvTrip("2026-12-07", .eve, rvStop("p2"))), ["第 1 天北村韓屋村排在晚上，紅區只開 10:00 到 17:00"])
        XCTAssertEqual(
            closedLines(rvTrip("2026-12-07", .eve, rvStop("p0"))), ["第 1 天景福宮排在晚上，這個時段不開"])
        let pig: Stop = rvStop("p30c")
        XCTAssertEqual(
            closedLines(rvTrip("2026-12-07", .pm, pig)), ["第 1 天\(pig.n)排在下午，還沒開，16:00 才開"])
    }

    func test問這一站要注意什麼_時段不開和公告都講_去過了不講() throws {
        let pig: Stop = rvStop("p30c")
        let t: Trip = rvTrip("2026-12-07", .pm, pig)
        let one: String = try XCTUnwrap(phoneAnswer("這一站要注意什麼", rvState(t), 1, "p30c", nil))
        XCTAssertTrue(one.contains("排在下午，還沒開，16:00 才開"), one)
        XCTAssertTrue(one.contains("二手資料"), one)
        let day: String = try XCTUnwrap(phoneAnswer("第 1 天要注意什麼", rvState(t), 1, nil, nil))
        XCTAssertTrue(day.contains("排在下午，還沒開，16:00 才開"), day)
        var done: Stop = pig
        done.status = .pulled
        let after: String = try XCTUnwrap(
            phoneAnswer("這一站要注意什麼", rvState(rvTrip("2026-12-07", .pm, done)), 1, "p30c", nil))
        XCTAssertFalse(after.contains("排在下午"), after)

        let tower: Trip = rvTrip("2027-02-01", .eve, rvStop("p11"))
        let why: String = try XCTUnwrap(phoneAnswer("這一站要注意什麼", rvState(tower), 1, "p11", nil))
        XCTAssertTrue(why.contains("限制使用"), why)
    }

    func test漢江遊船_2027年1月起提醒夜船() {
        XCTAssertNil(cautionWhy("p38", "2026-12-31"))
        XCTAssertNotNil(cautionWhy("p38", "2027-01-01"))
        XCTAssertNil(closedWhy("p38", "2027-01-01"), "只提醒不擋")
    }

    /* ---------- 訂票那一句 ---------- */

    func test算不出開賣日_有網頁的指到下面那一列_去過了不講() throws {
        let show: Stop = rvStop("p14a")
        let r: BookRow = try XCTUnwrap(bookPlan(rvTrip("2026-12-07", .eve, show), [:], "2026-11-25").first)
        XCTAssertEqual(bookOpenText(r, "2026-11-25"), "哪天開賣沒查到，看下面的訂票網頁")
        XCTAssertNil(factOf("p14a")?.last, "網路賣到幾點不是最後入場")
        XCTAssertEqual(factOf("p14a")?.book?.how.contains("開演前 2 小時"), true)
        var done: Stop = show
        done.status = .pulled
        let p: BookRow = try XCTUnwrap(bookPlan(rvTrip("2026-12-07", .eve, done), [:], "2026-11-25").first)
        XCTAssertFalse(bookNote(p, "2026-11-25").contains("\n"), bookNote(p, "2026-11-25"))
    }

    /* ---------- 文字 ---------- */

    func test給人看的字_不寫2026減12減31那種日期() throws {
        let pattern: NSRegularExpression = try NSRegularExpression(pattern: "20[0-9]{2}-[0-9]{2}")
        func bad(_ text: String) -> Bool {
            return pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        for (id, f) in SeoulChecked.shared.facts {
            let b: BookInfo? = f.book
            let texts: [String?] = [f.hours, f.last, f.price, f.tip, f.plainTip, b?.how, b?.cancel, b?.foreigner]
            for text in texts { XCTAssertFalse(bad(text ?? ""), "\(id) \(text ?? "")") }
        }
        for x in SeoulChecked.shared.dated {
            XCTAssertFalse(bad(x.before), x.before)
            XCTAssertFalse(bad(x.after), x.after)
        }
    }

    func test二手的說法統一_其他照原本() {
        XCTAssertEqual(statusWord("二手核對"), "二手資料")
        for x in ["看過官方頁", "來源較舊", "未核對"] { XCTAssertEqual(statusWord(x), x) }
    }
}
