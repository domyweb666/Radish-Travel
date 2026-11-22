// 這一天的路線「請 AI 提一個改法」（S12，線框 A8）的規則測試：手機算的改法、AI 的改法先在複本上試套、
// 動到別天要擋掉、省不到 5 分鐘不給。iOS 版才有，mobile/tests/ 沒有對應的。
// 分鐘數照 Plan.swift 的 leg（直線距離加三成），住的地方是預設的明洞。
import XCTest

@testable import RadishCore

private func routeStop(_ name: String, pulled: Bool = false) throws -> Stop {
    let p: Place = try XCTUnwrap(PLACES.first { (x: Place) -> Bool in x.n == name }, "資料包裡沒有「\(name)」")
    var it: Stop = planToStop(p, "測試")
    if pulled { it.status = .pulled }
    return it
}

/// 第 1 天上午、下午、晚上各放幾站；other 有給的話，第 2 天上午放那幾站
private func routeTrip(am: [Stop], pm: [Stop], eve: [Stop], other: [Stop]? = nil) -> Trip {
    var slots: [Slot] = [
        Slot(day: 1, part: .am, items: am),
        Slot(day: 1, part: .pm, items: pm),
        Slot(day: 1, part: .eve, items: eve),
    ]
    if let other = other {
        slots.append(Slot(day: 2, part: .am, items: other))
        slots.append(Slot(day: 2, part: .pm, items: []))
        slots.append(Slot(day: 2, part: .eve, items: []))
    }
    return Trip(start: "2026-12-16", days: other == nil ? 1 : 2, arrive: .am, leave: .eve, people: 2, slots: slots)
}

/// 下午跑去聖水洞、晚上又回北村：下午和晚上對調最省
private func detourTrip(other: [Stop]? = nil, pulledCafe: Bool = false) throws -> Trip {
    return try routeTrip(
        am: [routeStop("景福宮")],
        pm: [routeStop("聖水洞咖啡廳", pulled: pulledCafe)],
        eve: [routeStop("北村韓屋村")],
        other: other
    )
}

private func partOf(_ t: Trip, _ name: String) -> Part? {
    return allItems(t).first { (x: Found) -> Bool in x.it.n == name }?.s.part
}

final class RouteSuggestTests: XCTestCase {
    func test手機算的_挑最省的那一個_而且至少省5分鐘() throws {
        let t: Trip = try detourTrip()
        let st: Settings = defaultSettings()
        let v: RouteVerdict = routePhone(t, st, 1, nil)
        guard case .plan(let p) = v else { return XCTFail("應該找得到改法：\(v)") }
        XCTAssertEqual(p.by, .phone)
        XCTAssertEqual(p.reply, "")
        XCTAssertEqual(p.before, routeMinutes(t, st, 1))
        XCTAssertTrue(p.saved >= ROUTE_MIN_SAVE, "只省 \(p.saved) 分鐘")
        XCTAssertTrue(p.moves.contains(RouteMove(id: "p24", name: "聖水洞咖啡廳", from: .pm, to: .eve)), "\(p.moves)")
        XCTAssertTrue(p.moves.allSatisfy { (m: RouteMove) -> Bool in m.name != "景福宮" }, "主要景點不該被換到晚上")
        XCTAssertEqual(routeMoveLine(RouteMove(id: "p24", name: "聖水洞咖啡廳", from: .pm, to: .eve)), "聖水洞咖啡廳：下午 → 晚上")

        // 照它給的 ops 真的套一次：分鐘數跟它講的一樣、站數沒變
        var after: Trip = t
        var seeds: [Seed] = []
        let r: (changes: [String], notes: [String]) = applyOps(&after, &seeds, p.ops, nil, true)
        XCTAssertEqual(r.notes, [])
        XCTAssertEqual(routeMinutes(after, st, 1), p.after)
        XCTAssertEqual(dayStops(after, 1).count, 3)
        XCTAssertEqual(partOf(after, "景福宮"), .am)
        XCTAssertEqual(partOf(after, "聖水洞咖啡廳"), .eve)
    }

    func test手機算的_省不到5分鐘就不給_AI提的有比較省就給() throws {
        // 這三站怎麼排最多只省 4 分鐘（估）
        let t: Trip = try routeTrip(am: [routeStop("南大門市場")], pm: [routeStop("廣藏市場")], eve: [routeStop("N 首爾塔")])
        let st: Settings = defaultSettings()
        guard case .smooth = routePhone(t, st, 1, nil) else { return XCTFail("省不到 \(ROUTE_MIN_SAVE) 分鐘，不該給") }

        let ops: [Any] = [["op": "swapParts", "day": 1, "a": "pm", "b": "eve"] as [String: Any]]
        guard case .plan(let p) = routeTry(t, st, 1, ops, nil, by: .ai, reply: "下午晚上對調比較順") else {
            return XCTFail("AI 提的有比較省就該拿出來")
        }
        XCTAssertEqual(p.by, .ai)
        XCTAssertTrue(p.saved > 0 && p.saved < ROUTE_MIN_SAVE, "省了 \(p.saved)")
        guard case .smooth = routeTry(t, st, 1, ops, nil, by: .phone, minSave: ROUTE_MIN_SAVE) else {
            return XCTFail("要省 \(ROUTE_MIN_SAVE) 分鐘才算數時，不該給")
        }
    }

    func test沒有比較省或ops是空的_就說已經算順() throws {
        let t: Trip = try detourTrip()
        let st: Settings = defaultSettings()
        guard case .smooth = routeTry(t, st, 1, [], nil, by: .ai) else { return XCTFail("ops 是空的") }
        // 先把下午和晚上對調成順的，再叫它對調回去（變繞路）：不給
        var good: Trip = t
        var seeds: [Seed] = []
        applyOps(&good, &seeds, [Op.swapParts(day: 1, a: .pm, b: .eve)] as [Any], nil, true)
        let worse: [Any] = [Op.swapParts(day: 1, a: .pm, b: .eve)]
        guard case .smooth = routeTry(good, st, 1, worse, nil, by: .ai) else { return XCTFail("改了更繞，不該給") }
        XCTAssertEqual(routeVerdictText(.smooth, .ai), "AI 看過了，這天的順序已經算順，沒有更省的改法。")
    }

    func test試套時動到別天_用了不准用的動作_一律擋掉() throws {
        let t: Trip = try detourTrip(other: [routeStop("仁寺洞街")])
        let st: Settings = defaultSettings()
        let blocked: [[Any]] = [
            // 把第 2 天的站拉到第 1 天
            [["op": "move", "id": "p8", "day": 1, "part": "pm"] as [String: Any]],
            // 把第 1 天的站移到第 2 天
            [["op": "move", "id": "p24", "day": 2, "part": "pm"] as [String: Any]],
            // 整天對調、對調別天的時段
            [Op.swapDays(a: 1, b: 2)],
            [Op.swapParts(day: 2, a: .am, b: .pm)],
            // 拿站、加站、換站、留白
            [Op.remove(id: "p24")],
            [Op.add(day: 1, part: .pm, id: "p9", place: nil)],
            [Op.replace(id: "p24", with: .id("p9"))],
            [Op.rest(day: 1, part: .pm, on: true)],
            // 一步對、一步不對：整串都不要
            [Op.swapParts(day: 1, a: .pm, b: .eve), Op.move(id: "p8", day: 1, part: .am)],
            // 同一個時段對調、看不懂的東西
            [["op": "swapParts", "day": 1, "a": "pm", "b": "pm"] as [String: Any]],
            ["swapParts"],
        ]
        for ops in blocked {
            guard case .broken = routeTry(t, st, 1, ops, nil, by: .ai) else {
                return XCTFail("這串應該擋掉：\(ops)")
            }
        }
        XCTAssertEqual(routeVerdictText(.broken, .ai), "AI 提的改法套不上，這天先不動。")

        // 只動第 1 天的照樣給，而且第 2 天一點都沒變
        let ok: [Any] = [["op": "swapParts", "day": 1, "a": "pm", "b": "eve"] as [String: Any]]
        guard case .plan(let p) = routeTry(t, st, 1, ok, nil, by: .ai) else { return XCTFail("只動第 1 天的應該給") }
        var after: Trip = t
        var seeds: [Seed] = []
        applyOps(&after, &seeds, p.ops, nil, true)
        XCTAssertEqual(after.slots.filter { (s: Slot) -> Bool in s.day == 2 }, t.slots.filter { (s: Slot) -> Bool in s.day == 2 })
    }

    func test旅途中_過去的時段和拔起來的站不動() throws {
        let st: Settings = defaultSettings()
        let now: TripNow = TripNow(day: 1, part: .pm, clock: "13:00")
        // 上午已經過了、下午那站拔起來了：能動的只剩晚上，手機找不到改法
        let pulled: Trip = try detourTrip(pulledCafe: true)
        guard case .smooth = routePhone(pulled, st, 1, now) else { return XCTFail("沒有能動的時段，不該給") }
        // AI 要動拔起來的站、要動過去的時段，都擋掉
        guard case .broken = routeTry(pulled, st, 1, [Op.move(id: "p24", day: 1, part: .eve)], now, by: .ai) else {
            return XCTFail("拔起來的站不能動")
        }
        let open: Trip = try detourTrip()
        guard case .broken = routeTry(open, st, 1, [Op.swapParts(day: 1, a: .am, b: .pm)], now, by: .ai) else {
            return XCTFail("上午已經過了，不能對調")
        }
        // 手機算的也不碰上午
        if case .plan(let p) = routePhone(open, st, 1, now) {
            XCTAssertTrue(p.moves.allSatisfy { (m: RouteMove) -> Bool in m.from != .am && m.to != .am }, "\(p.moves)")
        }
    }

    func test有站沒有位置_算不出來就不給() throws {
        var mine: Stop = try routeStop("北村韓屋村")
        mine.lat = nil
        mine.lng = nil
        let t: Trip = try routeTrip(am: [routeStop("景福宮")], pm: [routeStop("聖水洞咖啡廳")], eve: [mine])
        let st: Settings = defaultSettings()
        guard case .unknown = routePhone(t, st, 1, nil) else { return XCTFail("有站沒有位置，算不出分鐘") }
        XCTAssertNil(routeMinutes(t, st, 1))
    }

    func test提示詞只給這一天_只准move和swapParts() throws {
        let t: Trip = try detourTrip(other: [routeStop("仁寺洞街")])
        let prompt: String = routePrompt(t, defaultSettings(), 1, nil)
        XCTAssertTrue(prompt.contains("[p24] 聖水洞咖啡廳"), "這天的站要有 id")
        XCTAssertFalse(prompt.contains("[p8]"), "別天的站不該給 AI 看")
        XCTAssertTrue(prompt.contains("\"op\":\"move\""))
        XCTAssertTrue(prompt.contains("\"op\":\"swapParts\""))
        for banned in ["\"op\":\"remove\"", "\"op\":\"add\"", "\"op\":\"replace\"", "\"op\":\"swapDays\"", "\"op\":\"rest\""] {
            XCTAssertFalse(prompt.contains(banned), "提示詞不該教 AI 用 \(banned)")
        }
        XCTAssertTrue(prompt.contains("{\"reply\":"), "回覆格式沿用 {reply, ops}")
        XCTAssertTrue(prompt.contains("（估）"))
    }
}
