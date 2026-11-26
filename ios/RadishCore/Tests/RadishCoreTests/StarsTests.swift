// 星級（第一次來的外國遊客多想去，估的）與去過的站往後排。iOS 版才有。
// 排出來的結果先用 ios/tools/scan-stars.mjs 照搬規則跑過：中性偏好、住明洞、2026-12-09 起三天、不看休館，
// 第一次來排到 仁寺洞街、高麗蔘雞湯、景福宮、昌德宮與後苑、廣藏市場、明洞逛街、益善洞韓屋巷（三星 4 站／7 站）。
import XCTest

@testable import RadishCore

/// 這個檔看的是星級和去過，不看休館資料
private func starNoClose(_ id: String, _ iso: String) -> String? {
    return nil
}

private func starNoPart(_ id: String, _ iso: String, _ part: Part) -> String? {
    return nil
}

/// 沒說過喜歡哪一類的人（開一趟時四題都沒選）
private func neutralSettings() -> Settings {
    var st: Settings = defaultSettings()
    st.play = [:]
    return st
}

private func starTrip(_ days: Int, _ st: Settings, _ visited: [String: Int] = [:]) -> Trip {
    let d: TripDraft = TripDraft(
        tweaks: nil, city: "seoul", base: nil, stayName: nil, name: nil, cover: nil,
        start: "2026-12-09", days: days, arrive: .am, leave: .eve, people: 2
    )
    return generate(d, st, closed: starNoClose, parts: starNoPart, visited: visited)
}

private func starStops(_ t: Trip) -> [Stop] {
    return allItems(t).map { (x: Found) -> Stop in x.it }
}

private func starCount(_ stops: [Stop], _ star: Int) -> Int {
    return stops.filter { (s: Stop) -> Bool in
        guard let p = PLACES.first(where: { (q: Place) -> Bool in q.id == s.id }) else { return false }
        return starOf(p) == star
    }.count
}

private func basketOf(_ id: String, _ items: [BasketItem]) -> Basket {
    return Basket(id: id, title: "上次的首爾", items: items)
}

final class StarsTests: XCTestCase {
    /* ---------- 資料 ---------- */

    func test每個地點都有1到3顆星_而且是寫明的不是漏寫補的() {
        XCTAssertTrue(PLACES.count > 50)
        for p in PLACES {
            let s: Int = p.star ?? 0
            XCTAssertTrue((1...3).contains(s), "\(p.id) \(p.n) 是 \(s) 顆")
            let inJson: Bool = SeoulData.shared.places.contains { (q: Place) -> Bool in q.id == p.id && q.star != nil }
            XCTAssertTrue(inJson || ADDED_STAR[p.id] != nil, "\(p.id) \(p.n) 沒寫星級（seoul.json 或 Stars.swift 的 ADDED_STAR）")
        }
        // 資料包裡被拆掉的「挑一間」也要有，拆出來的真店漏寫時才有得退
        for p in SeoulData.shared.places {
            XCTAssertNotNil(p.star, "seoul.json 的 \(p.id) 沒有 star（重跑 export-seoul.ts 會弄丟，要一起補）")
        }
    }

    func test三星是少數_景福宮明洞N首爾塔是三星() throws {
        let three: [Place] = PLACES.filter { (p: Place) -> Bool in starOf(p) == 3 }
        XCTAssertTrue(three.count * 5 < PLACES.count, "三星要是第一次來幾乎都會去的，不能太多：\(three.count)")
        for id in ["p0", "p10", "p11"] {
            let p: Place = try XCTUnwrap(PLACES.first { (q: Place) -> Bool in q.id == id })
            XCTAssertEqual(starOf(p), 3, p.n)
        }
    }

    func test舊存檔_地點沒有star也讀得進來_漏寫當二星() throws {
        let raw: String = #"{"id":"x1","n":"某個地方","kr":"","a":"C","s":"S","c":"shop","lat":37.5,"lng":127.0}"#
        let p: Place = try JSONDecoder().decode(Place.self, from: Data(raw.utf8))
        XCTAssertNil(p.star)
        XCTAssertEqual(starOf(p), STAR_MISSING)
        // 星級不存在行程裡：舊的一趟照樣讀得回來，一站也沒有 star
        let old: String = #"{"n":"景福宮","s":"L","c":"sight"}"#
        let it: BasketItem = try JSONDecoder().decode(BasketItem.self, from: Data(old.utf8))
        XCTAssertNil(it.id)
        XCTAssertEqual(visitedOf([basketOf("b1", [it])]), ["p0": 1])
    }

    /* ---------- 去過幾次 ---------- */

    func test去過幾次_代號對得到用代號_沒有用中文名_同一趟兩次算一次() {
        let a: Basket = basketOf("b1", [
            BasketItem(id: "p0", n: "景福宮", s: .L, c: .sight),
            BasketItem(id: nil, n: "N 首爾塔", s: .S, c: .sight),
            BasketItem(id: "p0", n: "景福宮", s: .L, c: .sight),
            BasketItem(id: "m-123", n: "自己加的咖啡店", s: .S, c: .cafe),
        ])
        let b: Basket = basketOf("b2", [
            BasketItem(id: "ai-9", n: "景福宮", s: .L, c: .sight),
        ])
        XCTAssertEqual(visitedOf([a, b]), ["p0": 2, "p11": 1])
        XCTAssertEqual(visitedOf([]), [:])
    }

    /* ---------- 第一次來 ---------- */

    func test第一次來的短行程_三星佔多數() {
        for days in [2, 3] {
            let stops: [Stop] = starStops(starTrip(days, neutralSettings()))
            XCTAssertFalse(stops.isEmpty)
            let three: Int = starCount(stops, 3)
            XCTAssertTrue(three * 2 > stops.count, "\(days) 天：三星 \(three)／\(stops.count)")
        }
        let ids: [String] = starStops(starTrip(3, neutralSettings())).map { (s: Stop) -> String in s.id }
        XCTAssertTrue(ids.contains("p0"), "第一次來的三天要有景福宮：\(ids)")
    }

    func test第一次來排到三星_理由講估計多半會去_不講成確定() throws {
        let stops: [Stop] = starStops(starTrip(3, neutralSettings()))
        let gyeong: Stop = try XCTUnwrap(stops.first { (s: Stop) -> Bool in s.id == "p0" })
        XCTAssertEqual(gyeong.why, STAR_FIRST_WHY)
        XCTAssertTrue(STAR_FIRST_WHY.contains("估"))
    }

    func test沒給去過的表_跟以前的呼叫一樣() {
        let d: TripDraft = TripDraft(
            tweaks: nil, city: "seoul", base: nil, stayName: nil, name: nil, cover: nil,
            start: "2026-12-09", days: 4, arrive: .am, leave: .eve, people: 2
        )
        XCTAssertEqual(generate(d, defaultSettings()), generate(d, defaultSettings(), visited: [:]))
    }

    /* ---------- 去過的 ---------- */

    func test去過的有別的可排就不排() {
        let t: Trip = starTrip(3, neutralSettings(), ["p0": 1])
        let ids: [String] = starStops(t).map { (s: Stop) -> String in s.id }
        XCTAssertFalse(ids.contains("p0"), "去過景福宮，這趟有別的可排：\(ids)")
        XCTAssertFalse(ids.isEmpty)
    }

    func test全部都去過_沒別的可排才排_而且講為什麼() {
        var all: [String: Int] = [:]
        for p in PLACES { all[p.id] = 2 }
        let stops: [Stop] = starStops(starTrip(3, neutralSettings(), all))
        XCTAssertFalse(stops.isEmpty, "全部去過也不能整趟空著")
        for s in stops {
            XCTAssertEqual(s.why, visitedWhy(2), s.n)
        }
        XCTAssertEqual(visitedWhy(1), "你上次來去過，這一帶沒別的可排")
    }

    func test去過以後_三星的比例下降() {
        let first: [Stop] = starStops(starTrip(3, neutralSettings()))
        var been: [String: Int] = [:]
        for s in first {
            guard let p = PLACES.first(where: { (q: Place) -> Bool in q.id == s.id }), starOf(p) == 3 else { continue }
            been[s.id] = 1
        }
        XCTAssertFalse(been.isEmpty)
        let again: [Stop] = starStops(starTrip(3, neutralSettings(), been))
        XCTAssertFalse(again.isEmpty)
        let before: Double = Double(starCount(first, 3)) / Double(first.count)
        let after: Double = Double(starCount(again, 3)) / Double(again.count)
        XCTAssertTrue(after < before, "第一次 \(before)，去過以後 \(after)")
        XCTAssertTrue(starBonus(3, firstTime: false) < starBonus(3, firstTime: true))
    }

    /* ---------- 喜好比星級重要 ---------- */

    func test使用者說過的喜好_勝過星級() {
        // 最小的一階喜好（喜歡一類 +2）也要比三星大
        XCTAssertTrue(starBonus(3, firstTime: true) < 2)
        // 公園散步的地方沒有三星。沒說喜歡就一站都排不到，說喜歡就排得到，理由講喜歡
        let plain: [Stop] = starStops(starTrip(4, neutralSettings()))
        XCTAssertEqual(plain.filter { (s: Stop) -> Bool in s.c == .nature }.count, 0)
        var st: Settings = neutralSettings()
        st.play = [.nature: 1]
        let liked: [Stop] = starStops(starTrip(4, st)).filter { (s: Stop) -> Bool in s.c == .nature }
        XCTAssertFalse(liked.isEmpty)
        // 第一天、最後一天排到的講「排輕鬆的」，中間那幾天照喜好排到的講喜歡
        let saysLike: Bool = liked.contains { (s: Stop) -> Bool in s.why.hasPrefix("你喜歡") }
        XCTAssertTrue(saysLike, liked.map { (s: Stop) -> String in "\(s.n)：\(s.why)" }.joined(separator: "、"))
    }

    func test喜歡的那一類排到三星_理由講喜歡_不講多半會去() throws {
        var st: Settings = neutralSettings()
        st.play = [.sight: 1]
        let stops: [Stop] = starStops(starTrip(3, st))
        let gyeong: Stop = try XCTUnwrap(stops.first { (s: Stop) -> Bool in s.id == "p0" })
        XCTAssertTrue(gyeong.why.hasPrefix("你喜歡"), gyeong.why)
        for s in stops where s.c == .sight {
            XCTAssertNotEqual(s.why, STAR_FIRST_WHY, "說過喜歡古蹟，三星的古蹟要講喜歡：\(s.n)")
        }
    }

    /* ---------- 問 AI ---------- */

    func test問AI_候選帶星級_去過的帶次數_規則講先挑三星() throws {
        let t: Trip = starTrip(3, neutralSettings())
        let used: Set<String> = usedIds(t)
        let open: [Place] = PLACES.filter { (p: Place) -> Bool in
            return !used.contains(p.id) && factOf(p.id)?.gone == nil
        }
        let been: Place = try XCTUnwrap(open.first { (p: Place) -> Bool in starOf(p) == 3 })
        let other: Place = try XCTUnwrap(open.first { (p: Place) -> Bool in p.id != been.id })
        let prompt: String = aiPrompt("還有哪裡可以去", t, neutralSettings(), [], nil, "", visited: [been.id: 2])
        let lines: [String] = prompt.components(separatedBy: "\n")
        let beenLine: String = try XCTUnwrap(lines.first { (l: String) -> Bool in l.hasPrefix("[\(been.id)] ") })
        XCTAssertTrue(beenLine.contains("估3星"), beenLine)
        XCTAssertTrue(beenLine.contains("去過2次"), beenLine)
        let otherLine: String = try XCTUnwrap(lines.first { (l: String) -> Bool in l.hasPrefix("[\(other.id)] ") })
        XCTAssertTrue(otherLine.contains("估\(starOf(other))星"), otherLine)
        XCTAssertFalse(otherLine.contains("去過"), otherLine)
        XCTAssertTrue(prompt.contains("先挑 3 星"))
        XCTAssertTrue(prompt.contains("除非使用者自己要，不要再排"))
        // 沒給去過的表（舊的呼叫）：一樣帶星級，沒有「去過」
        let plain: String = aiPrompt("還有哪裡可以去", t, neutralSettings(), [])
        XCTAssertTrue(plain.contains("估3星"))
        XCTAssertFalse(plain.contains("去過2次"))
    }

    /* ---------- 畫面上的字 ---------- */

    func test星星的字_講明是估的() {
        XCTAssertEqual(starMarks(3), "★★★")
        XCTAssertEqual(starMarks(1), "★☆☆")
        XCTAssertEqual(starMarks(9), "★★★")
        XCTAssertTrue(starSpoken(2).contains("估"))
        XCTAssertTrue(STAR_NOTE.contains("估"))
    }
}
