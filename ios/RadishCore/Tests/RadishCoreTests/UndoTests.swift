// 復原跨趟不掉資料、收起來不掉資料、有去過的站不整趟重排、等回覆時換了一趟。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class UndoTests: XCTestCase {
    private func plan(_ name: String, _ start: String, _ days: Int = 3) -> Trip {
        let d: TripDraft = TripDraft(
            city: "seoul", name: name, start: start, days: days, arrive: .am, leave: .eve, people: 2)
        return generate(d, defaultSettings())
    }

    /// 跟 AppStore 一樣：改一下，該留一步的留一步
    private struct Desk {
        var s: AppState = AppState()
        var stack: [UndoSnap] = []

        mutating func act(_ undoable: Bool, _ change: (inout AppState) -> Void) {
            let prev: AppState = s
            var draft: AppState = s
            change(&draft)
            syncAIUsed(&draft)
            let swap: Bool = tripSwapped(prev, draft)
            if undoable || swap {
                stack.append(undoSnap(prev, swap: swap))
            }
            s = draft
        }

        @discardableResult
        mutating func undo() -> String {
            guard let snap = stack.popLast() else { return "" }
            return applyUndo(&s, snap)
        }
    }

    /// 開著 A，架上一趟 B
    private func desk() -> Desk {
        var k: Desk = Desk()
        k.s.trip = plan("B", "2027-03-10")
        k.s.chat = [ChatMsg(r: .me, t: "B 的話")]
        k.s.checks = ["passport": true, "b_b1": true]
        shelveCurrent(&k.s)
        k.s.trip = plan("A", "2026-12-01", 5)
        k.s.chat = [ChatMsg(r: .me, t: "A 的話")]
        k.s.checks["b_a1"] = true
        k.s.debugDay = 2
        syncAIUsed(&k.s)
        return k
    }

    private func names(_ s: AppState) -> [String] {
        var out: [String] = s.shelf.map { (x: Shelved) -> String in x.trip.name ?? "" }
        if let t = s.trip { out.append(t.name ?? "") }
        return out.sorted()
    }

    private func rename(_ k: inout Desk, _ stay: String) {
        k.act(true) { (d: inout AppState) -> Void in
            d.trip?.stayName = stay
        }
    }

    private func openFirst(_ k: inout Desk) throws {
        let id: String = try XCTUnwrap(k.s.shelf.first?.id)
        k.act(true) { (d: inout AppState) -> Void in
            _ = openShelved(&d, id)
        }
    }

    private func pull(_ t: inout Trip, _ say: String) throws {
        let first: Found = try XCTUnwrap(allItems(t).first)
        t.slots[first.si].items[first.ii].status = .pulled
        t.slots[first.si].items[first.ii].say = say
        t.slots[first.si].items[first.ii].photos = ["p1.jpg"]
    }

    /* ---------- 1 復原跨趟 ---------- */

    func test改A_切到B_復原兩次_回到A改之前_B原樣在架上() throws {
        var k: Desk = desk()
        let before: AppState = k.s
        rename(&k, "改過")
        try openFirst(&k)
        XCTAssertEqual(k.s.trip?.name, "B")
        XCTAssertEqual(k.s.checks, ["passport": true, "b_b1": true])

        let said: String = k.undo()
        XCTAssertEqual(said, "復原了上一步。")
        XCTAssertEqual(k.s.trip?.name, "A")
        XCTAssertEqual(k.s.trip?.stayName, "改過")
        XCTAssertEqual(names(k.s), ["A", "B"], "一趟都沒少、也沒有多一份")
        XCTAssertEqual(k.s.chat, before.chat)
        XCTAssertEqual(k.s.checks, before.checks)
        XCTAssertEqual(k.s.debugDay, 2)
        XCTAssertEqual(k.s.shelf.first?.chat, [ChatMsg(r: .me, t: "B 的話")])
        XCTAssertEqual(k.s.shelf.first?.checks, ["b_b1": true])

        k.undo()
        XCTAssertEqual(k.s.trip, before.trip)
        XCTAssertEqual(names(k.s), ["A", "B"])
    }

    func test切到B之後講的話_打的勾_復原切換還在() throws {
        var k: Desk = desk()
        try openFirst(&k)
        k.act(false) { (d: inout AppState) -> Void in
            d.chat.append(ChatMsg(r: .me, t: "後來講的"))
            d.checks["b_b2"] = true
            d.checks["adapter"] = true
        }
        k.undo()
        XCTAssertEqual(k.s.trip?.name, "A")
        let b: Shelved = try XCTUnwrap(k.s.shelf.first)
        XCTAssertEqual(b.chat.count, 2)
        XCTAssertEqual(b.checks, ["b_b1": true, "b_b2": true])
        XCTAssertEqual(k.s.checks, ["passport": true, "adapter": true, "b_a1": true], "行李檢查表不跟著退")
    }

    func test切過去再切回來_復原一路退回去_每一步都兩趟() throws {
        var k: Desk = desk()
        rename(&k, "一")
        try openFirst(&k)
        rename(&k, "二")
        try openFirst(&k)
        rename(&k, "三")
        XCTAssertEqual(k.stack.count, 5)
        while !k.stack.isEmpty {
            k.undo()
            XCTAssertEqual(names(k.s), ["A", "B"])
        }
        XCTAssertEqual(k.s.trip?.name, "A")
        XCTAssertNil(k.s.trip?.stayName)
        XCTAssertNil(k.s.shelf.first?.trip.stayName)
    }

    func test收起A_排C_復原_C放到其他排好的_再復原_A回來() throws {
        var k: Desk = desk()
        var a: Trip = try XCTUnwrap(k.s.trip)
        try pull(&a, "湯很清")
        k.s.trip = a
        k.act(true) { (d: inout AppState) -> Void in
            _ = archiveTrip(&d)
        }
        XCTAssertEqual(k.s.baskets.count, 1)
        let c: Trip = plan("C", "2027-05-01")
        k.act(false) { (d: inout AppState) -> Void in
            d.trip = c
            d.chat = []
            d.checks = ["passport": true]
            d.debugDay = nil
        }
        XCTAssertEqual(k.stack.count, 2, "開新的一趟沒寫 undoable 也會留一步")

        let said: String = k.undo()
        XCTAssertTrue(said.contains("其他排好的"))
        XCTAssertNil(k.s.trip)
        XCTAssertEqual(names(k.s), ["B", "C"])

        XCTAssertEqual(k.undo(), "復原了上一步。", "這一步沒有把哪一趟放到架上")
        XCTAssertEqual(k.s.trip, a)
        XCTAssertEqual(k.s.chat, [ChatMsg(r: .me, t: "A 的話")])
        XCTAssertEqual(k.s.checks["b_a1"], true)
        XCTAssertEqual(k.s.debugDay, 2)
        XCTAssertEqual(k.s.baskets, [], "收進去的那一份跟著退")
        XCTAssertEqual(names(k.s), ["A", "B", "C"], "C 沒有不見")
    }

    func test不要這一版_復原_對話打勾都回來() throws {
        var k: Desk = desk()
        let before: AppState = k.s
        k.act(true) { (d: inout AppState) -> Void in
            _ = dropPlan(&d)
        }
        XCTAssertNil(k.s.trip)
        k.undo()
        XCTAssertEqual(k.s, before)
    }

    func test開新的一趟_復原_現在這趟拿回來_架上不會多一份() throws {
        var k: Desk = desk()
        let before: AppState = k.s
        k.act(true) { (d: inout AppState) -> Void in
            shelveCurrent(&d)
        }
        XCTAssertNil(k.s.trip)
        k.undo()
        XCTAssertEqual(k.s, before)
    }

    func test換趟之後問的句數_復原不退() throws {
        var k: Desk = desk()
        let aId: String = try XCTUnwrap(k.s.trip?.id)
        try openFirst(&k)
        let bId: String = try XCTUnwrap(k.s.trip?.id)
        // A 等回覆的時候切到 B，回來算在 A；B 自己問兩句
        k.act(false) { (d: inout AppState) -> Void in
            countAI(&d, aId)
            countAI(&d, bId)
            countAI(&d, bId)
        }
        k.undo()
        XCTAssertEqual(k.s.trip?.aiUsed, 1)
        XCTAssertEqual(k.s.shelf.first?.trip.aiUsed, 2)
    }

    /* ---------- 2 復原不退掉後來改的 ---------- */

    func test復原_後來改的設定還沒套_這件事還在_打勾也還在() throws {
        var k: Desk = desk()
        rename(&k, "改過")
        k.act(false) { (d: inout AppState) -> Void in
            d.settings.pace = .slow
            d.settingsDirty = true
            d.checks["b_a2"] = true
        }
        k.undo()
        XCTAssertTrue(k.s.settingsDirty)
        XCTAssertEqual(k.s.checks["b_a2"], true)
        XCTAssertNil(k.s.trip?.stayName)
    }

    func test重排再復原_還沒套的提醒回來() throws {
        var k: Desk = desk()
        k.s.settingsDirty = true
        k.act(true) { (d: inout AppState) -> Void in
            _ = replanCurrent(&d)
        }
        XCTAssertFalse(k.s.settingsDirty)
        k.undo()
        XCTAssertTrue(k.s.settingsDirty)
    }

    /* ---------- 3 有去過的站不整趟重排 ---------- */

    func test有去過的站_照新的設定重排擋下來_行程不動() throws {
        var k: Desk = desk()
        var a: Trip = try XCTUnwrap(k.s.trip)
        XCTAssertFalse(tripVisited(a))
        try pull(&a, "好吃")
        k.s.trip = a
        k.s.settingsDirty = true
        XCTAssertTrue(tripVisited(a))
        let said: String? = replanCurrent(&k.s)
        XCTAssertEqual(said, NO_REGEN_VISITED)
        XCTAssertEqual(k.s.trip, a)
        XCTAssertTrue(k.s.settingsDirty)
    }

    /* ---------- 4 收起來 ---------- */

    func test收起來_一站都沒去過_整趟放到其他排好的_不再提醒_打開又會提醒() throws {
        var k: Desk = desk()
        let a: Trip = try XCTUnwrap(k.s.trip)
        let said: String? = archiveTrip(&k.s)
        XCTAssertTrue((said ?? "").contains("其他排好的"))
        XCTAssertNil(k.s.trip)
        XCTAssertEqual(k.s.baskets, [])
        let kept: Shelved = try XCTUnwrap(k.s.shelf.first)
        XCTAssertEqual(kept.trip, a)
        XCTAssertEqual(kept.chat, [ChatMsg(r: .me, t: "A 的話")])
        XCTAssertEqual(kept.checks, ["b_a1": true])
        XCTAssertEqual(kept.shut, true)
        XCTAssertEqual(names(remindState(k.s)), ["B"])
        openShelved(&k.s, kept.id)
        XCTAssertEqual(k.s.trip, a)
        shelveCurrent(&k.s)
        XCTAssertEqual(names(remindState(k.s)), ["A", "B"])
    }

    func test收起來_有去過的_花費_匯率_機票_沒去的站_對話都留著_存檔讀得回來() throws {
        var k: Desk = desk()
        var a: Trip = try XCTUnwrap(k.s.trip)
        let all: Int = allItems(a).count
        try pull(&a, "湯很清")
        a.rate = 23
        a.flight = 12000
        addSpend(&a, 5000, "刀削麵", 1)
        k.s.trip = a
        archiveTrip(&k.s)

        let data: Data = try JSONEncoder().encode(k.s)
        let back: AppState = try XCTUnwrap(AppState.hydrate(data))
        let b: Basket = try XCTUnwrap(back.baskets.first)
        XCTAssertEqual(b.items.count, 1)
        XCTAssertEqual(b.items.first?.say, "湯很清")
        XCTAssertEqual(b.trip?.rate, 23)
        XCTAssertEqual(b.trip?.flight, 12000)
        XCTAssertEqual(b.trip?.spend?.first?.note, "刀削麵")
        XCTAssertEqual(basketLeft(b).count, all - 1)
        XCTAssertEqual(b.chat, [ChatMsg(r: .me, t: "A 的話")])
        // 那一句和照片只留 items 那一份，之後改了不會有舊的
        let trip: Trip = try XCTUnwrap(b.trip)
        let pulled: Found = try XCTUnwrap(allItems(trip).first { (x: Found) -> Bool in x.it.status == .pulled })
        XCTAssertNil(pulled.it.say)
        XCTAssertNil(pulled.it.photos)
    }

    func test舊檔的去過的旅行沒有整趟_讀得出來() throws {
        var d: AppState = AppState()
        d.baskets = [Basket(id: "b1", title: "舊的", items: [], start: "2026-01-01", days: 3)]
        let encoded: Data = try JSONEncoder().encode(d)
        let text: String = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("\"trip\""), "沒有的欄位不會寫進去，跟舊檔一樣")
        let back: AppState = try XCTUnwrap(AppState.hydrate(encoded))
        let b: Basket = try XCTUnwrap(back.baskets.first)
        XCTAssertNil(b.trip)
        XCTAssertEqual(basketLeft(b).count, 0)
    }

    /* ---------- 等 AI 回覆的時候換了一趟 ---------- */

    func test等回覆的時候換到B_回的話留在A的對話_復原回A還在() throws {
        var k: Desk = desk()
        let aId: String = try XCTUnwrap(k.s.trip?.id)
        k.act(false) { (d: inout AppState) -> Void in
            d.chat.append(ChatMsg(r: .me, t: "第 3 天輕鬆一點"))
        }
        try openFirst(&k)
        let bChat: [ChatMsg] = k.s.chat
        var name: String?
        k.act(false) { (d: inout AppState) -> Void in
            name = leaveReply(&d, aId, 1, "第 3 天輕鬆一點", ChatMsg(r: .ai, t: "好。"), true)
        }
        XCTAssertEqual(name, "A")
        XCTAssertEqual(k.s.chat, bChat, "沒有記進 B 的對話")
        XCTAssertEqual(k.stack.count, 1, "這不算一步")
        k.undo()
        XCTAssertEqual(k.s.trip?.name, "A")
        XCTAssertEqual(k.s.chat.count, 4)
        XCTAssertEqual(k.s.chat[2].t, "好。")
    }

    func test等回覆的時候換到B_沒收到_記在A的對話_對不上就不動() throws {
        var k: Desk = desk()
        let aId: String = try XCTUnwrap(k.s.trip?.id)
        try openFirst(&k)
        leaveFail(&k.s, aId, 0, "A 的話", "E1")
        let a: Shelved = try XCTUnwrap(k.s.shelf.first { (x: Shelved) -> Bool in x.trip.id == aId })
        XCTAssertEqual(a.chat.first?.failed, "E1")
        let before: AppState = k.s
        leaveFail(&k.s, aId, 5, "A 的話", "E2")
        XCTAssertNil(leaveReply(&k.s, "沒有這趟", 0, "A 的話", ChatMsg(r: .ai, t: "好。"), false))
        XCTAssertNil(leaveReply(&k.s, aId, 0, "別句", ChatMsg(r: .ai, t: "好。"), false))
        XCTAssertEqual(k.s, before)
    }

    /* ---------- 9 排好之後才說的調整 ---------- */

    func test重排之後才加的調整_剛排好那張卡不出現() throws {
        let old: Trip = plan("A", "2026-12-01", 5)
        var draft: TripDraft = draftOf(old)
        draft.tweaks = [.easy, .elder]
        var t: Trip = replanTrip(old, draft, defaultSettings(), true)
        XCTAssertNil(t.planMark, "還沒看這趟那一頁")
        XCTAssertTrue(planUntouched(t))
        t.tweaks = [.elder, .easy]
        XCTAssertTrue(planUntouched(t), "順序不同不算改")
        t.tweaks = [.elder, .easy, .save]
        XCTAssertFalse(planUntouched(t))
        // 舊檔沒有記排的時候的調整，照以前的算法
        t.planTweaks = nil
        XCTAssertTrue(planUntouched(t))
    }
}
