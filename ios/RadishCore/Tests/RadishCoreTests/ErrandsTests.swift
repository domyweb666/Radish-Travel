// 代購清單（Errands.swift）：輸入清乾淨、加、改、勾、刪、排順序、分組、還差幾樣；
// 重排、放一邊再拿回來、收起來、不要這一版、復原都不掉；舊存檔沒有這一欄讀得進來。mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class ErrandsTests: XCTestCase {
    private func plan(_ name: String, _ start: String, _ days: Int = 3) -> Trip {
        let d: TripDraft = TripDraft(
            city: "seoul", name: name, start: start, days: days, arrive: .am, leave: .eve, people: 2)
        return generate(d, defaultSettings())
    }

    /// 跟 AppStore 一樣：改一下，該留一步的留一步（照 PoolTests）
    private struct Desk {
        var s: AppState = AppState()
        var stack: [UndoSnap] = []

        mutating func act(_ undoable: Bool, _ change: (inout AppState) -> Void) {
            let prev: AppState = s
            var draft: AppState = s
            change(&draft)
            syncAIUsed(&draft)
            movePool(&draft)
            moveErrands(&draft)
            let swap: Bool = tripSwapped(prev, draft)
            if undoable || swap {
                stack.append(undoSnap(prev, swap: swap))
            }
            s = draft
        }

        mutating func undo() {
            guard let snap = stack.popLast() else { return }
            _ = applyUndo(&s, snap)
        }
    }

    /// 開著 A
    private func desk() -> Desk {
        var k: Desk = Desk()
        k.s.trip = plan("A", "2026-12-01", 5)
        syncAIUsed(&k.s)
        return k
    }

    /// 在現在這趟加一樣（可以復原的一步）
    private func add(_ k: inout Desk, _ who: String, _ what: String, _ qty: Int = 1, _ note: String? = nil) {
        k.act(true) { (d: inout AppState) -> Void in
            guard var trip = d.trip else { return }
            _ = addErrand(&trip, who, what, qty, note)
            d.trip = trip
        }
    }

    /// 開新的一趟（現在這趟放一邊），跟 PoolTests 一樣
    private func startTrip(_ k: inout Desk, _ name: String) {
        let trip: Trip = plan(name, "2027-03-10")
        k.act(false) { (d: inout AppState) -> Void in
            shelveCurrent(&d)
            d.trip = trip
        }
    }

    /// 這樣東西一共出現幾次：現在這趟、其他排好的、去過的、還沒放進哪一趟的
    private func count(_ s: AppState, _ what: String) -> Int {
        var all: [Errand] = s.errands
        all.append(contentsOf: s.trip?.errands ?? [])
        for x in s.shelf { all.append(contentsOf: x.trip.errands ?? []) }
        for b in s.baskets { all.append(contentsOf: b.trip?.errands ?? []) }
        return all.filter { (x: Errand) -> Bool in x.what == what }.count
    }

    private func whats(_ list: [Errand]?) -> [String] {
        return (list ?? []).map { (x: Errand) -> String in x.what }
    }

    private func hydrated(_ s: AppState) throws -> AppState {
        let data: Data = try JSONEncoder().encode(s)
        return try XCTUnwrap(AppState.hydrate(data))
    }

    private func item(_ id: String, _ who: String, _ what: String, done: Bool = false) -> Errand {
        return Errand(id: id, who: who, what: what, qty: 1, note: nil, done: done)
    }

    /* ---------- 清乾淨 ---------- */

    func test清乾淨_去頭尾空白_備註空的變nil() throws {
        let x: ErrandInput = try XCTUnwrap(cleanErrand("  媽媽 ", " 面膜\n", 2, "   "))
        XCTAssertEqual(x, ErrandInput(who: "媽媽", what: "面膜", qty: 2, note: nil))
        let y: ErrandInput = try XCTUnwrap(cleanErrand("", "面膜", 1, " 要綠色的 "))
        XCTAssertEqual(y.who, "")
        XCTAssertEqual(y.note, "要綠色的")
        let z: ErrandInput = try XCTUnwrap(cleanErrand("", "面膜", 1, nil))
        XCTAssertNil(z.note)
    }

    func test清乾淨_買什麼空的不收() {
        XCTAssertNil(cleanErrand("媽媽", "", 1, nil))
        XCTAssertNil(cleanErrand("媽媽", "   \n ", 1, "備註"))
    }

    func test清乾淨_幾個至少1最多99() throws {
        XCTAssertEqual(try XCTUnwrap(cleanErrand("", "面膜", 0, nil)).qty, 1)
        XCTAssertEqual(try XCTUnwrap(cleanErrand("", "面膜", -3, nil)).qty, 1)
        XCTAssertEqual(try XCTUnwrap(cleanErrand("", "面膜", 150, nil)).qty, ERRAND_QTY_MAX)
        XCTAssertEqual(try XCTUnwrap(cleanErrand("", "面膜", 7, nil)).qty, 7)
    }

    func test清乾淨_太長切到上限() throws {
        let long: String = String(repeating: "字", count: ERRAND_WHAT_MAX + 10)
        let x: ErrandInput = try XCTUnwrap(cleanErrand(String(repeating: "名", count: 50), long, 1, String(repeating: "備", count: 200)))
        XCTAssertEqual(x.what.count, ERRAND_WHAT_MAX)
        XCTAssertEqual(x.who.count, ERRAND_WHO_MAX)
        XCTAssertEqual(x.note?.count, ERRAND_NOTE_MAX)
    }

    /* ---------- 加、改、勾、刪 ---------- */

    func test加_接在最後面_代號不一樣_還沒買() throws {
        var t: Trip = plan("A", "2026-12-01")
        XCTAssertNil(t.errands)
        let a: Errand = try XCTUnwrap(addErrand(&t, "媽媽", "面膜", 3, "要綠色的"))
        let b: Errand = try XCTUnwrap(addErrand(&t, "", " 泡麵 "))
        XCTAssertEqual(whats(t.errands), ["面膜", "泡麵"])
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertFalse(a.done)
        XCTAssertEqual(a.qty, 3)
        XCTAssertEqual(a.note, "要綠色的")
        XCTAssertEqual(b.who, "")
        XCTAssertEqual(b.qty, 1)
        XCTAssertNil(b.note)
    }

    func test加_買什麼空的_什麼都不動() {
        var t: Trip = plan("A", "2026-12-01")
        let before: Trip = t
        XCTAssertNil(addErrand(&t, "媽媽", "  "))
        XCTAssertEqual(t, before)
        XCTAssertNil(t.errands)
    }

    func test改_位置和買到了沒都不變() throws {
        var t: Trip = plan("A", "2026-12-01")
        let a: Errand = try XCTUnwrap(addErrand(&t, "媽媽", "面膜"))
        _ = addErrand(&t, "爸爸", "燒酒")
        _ = toggleErrand(&t, a.id)
        let now: Errand = try XCTUnwrap(editErrand(&t, a.id, " 姊姊 ", "護手霜", 4, "  "))
        XCTAssertEqual(now.id, a.id)
        XCTAssertTrue(now.done, "改字不會把買到了改掉")
        XCTAssertEqual(now.who, "姊姊")
        XCTAssertEqual(now.qty, 4)
        XCTAssertNil(now.note)
        XCTAssertEqual(whats(t.errands), ["護手霜", "燒酒"], "改完還在原本的位置")
    }

    func test改_找不到或買什麼改成空的_什麼都不動() throws {
        var t: Trip = plan("A", "2026-12-01")
        let a: Errand = try XCTUnwrap(addErrand(&t, "媽媽", "面膜"))
        let before: Trip = t
        XCTAssertNil(editErrand(&t, "沒有這個", "媽媽", "面膜", 1, nil))
        XCTAssertNil(editErrand(&t, a.id, "媽媽", "   ", 1, nil))
        XCTAssertEqual(t, before)
        var empty: Trip = plan("B", "2026-12-01")
        XCTAssertNil(editErrand(&empty, a.id, "媽媽", "面膜", 1, nil))
    }

    func test勾_再勾一次取消() throws {
        var t: Trip = plan("A", "2026-12-01")
        let a: Errand = try XCTUnwrap(addErrand(&t, "媽媽", "面膜"))
        XCTAssertEqual(toggleErrand(&t, a.id)?.done, true)
        XCTAssertEqual(t.errands?.first?.done, true)
        XCTAssertEqual(toggleErrand(&t, a.id)?.done, false)
        XCTAssertEqual(t.errands?.first?.done, false)
        XCTAssertNil(toggleErrand(&t, "沒有這個"))
    }

    func test刪_刪到沒有變回nil_找不到不動() throws {
        var t: Trip = plan("A", "2026-12-01")
        let a: Errand = try XCTUnwrap(addErrand(&t, "媽媽", "面膜"))
        let b: Errand = try XCTUnwrap(addErrand(&t, "爸爸", "燒酒"))
        let before: Trip = t
        XCTAssertNil(removeErrand(&t, "沒有這個"))
        XCTAssertEqual(t, before)
        XCTAssertEqual(removeErrand(&t, a.id)?.what, "面膜")
        XCTAssertEqual(whats(t.errands), ["燒酒"])
        XCTAssertEqual(removeErrand(&t, b.id)?.what, "燒酒")
        XCTAssertNil(t.errands)
    }

    /* ---------- 排順序、分組、還差幾樣 ---------- */

    func test排序_還沒買的在前_同一邊照新增順序() {
        let list: [Errand] = [
            item("1", "", "甲", done: true), item("2", "", "乙"), item("3", "", "丙", done: true),
            item("4", "", "丁"), item("5", "", "戊"),
        ]
        XCTAssertEqual(whats(sortedErrands(list)), ["乙", "丁", "戊", "甲", "丙"])
        XCTAssertEqual(sortedErrands([]), [])
    }

    func test還差幾樣_一列算一樣_不管幾個() {
        var list: [Errand] = [item("1", "", "甲"), item("2", "", "乙", done: true)]
        list[0].qty = 5
        XCTAssertEqual(errandsLeft(list), 1)
        XCTAssertEqual(errandsLeft([]), 0)
    }

    func test最上面那一行() {
        XCTAssertNil(errandsLine([]))
        let some: [Errand] = [item("1", "", "甲"), item("2", "", "乙", done: true), item("3", "", "丙")]
        XCTAssertEqual(errandsLine(some), "還差 2 樣沒買，一共 3 樣。")
        let all: [Errand] = [item("1", "", "甲", done: true), item("2", "", "乙", done: true)]
        XCTAssertEqual(errandsLine(all), "都買到了，一共 2 樣。")
    }

    func test分組_照誰託的_沒寫的歸到沒寫是誰_放最後() {
        let list: [Errand] = [
            item("1", "", "甲"), item("2", "媽媽", "乙"), item("3", "爸爸", "丙"),
            item("4", "媽媽", "丁", done: true), item("5", "媽媽", "戊"),
        ]
        let groups: [ErrandGroup] = errandGroups(list)
        XCTAssertEqual(groups.map { (g: ErrandGroup) -> String in g.title }, ["媽媽", "爸爸", ERRAND_NO_WHO])
        XCTAssertEqual(groups.first?.who, "媽媽")
        XCTAssertEqual(groups.last?.who, "", "沒寫是誰的那一組存的是空字串")
        XCTAssertEqual(whats(groups.first?.items), ["乙", "戊", "丁"], "組裡還沒買的在前")
        XCTAssertEqual(errandWho(item("9", "  ", "x")), ERRAND_NO_WHO)
        XCTAssertEqual(errandWho(item("9", "媽媽", "x")), "媽媽")
    }

    func test分組_都買到的組排到後面() {
        let list: [Errand] = [
            item("1", "媽媽", "甲", done: true), item("2", "", "乙", done: true), item("3", "爸爸", "丙"),
            item("4", "", "丁"), item("5", "姊姊", "戊", done: true),
        ]
        let titles: [String] = errandGroups(list).map { (g: ErrandGroup) -> String in g.title }
        XCTAssertEqual(titles, ["爸爸", ERRAND_NO_WHO, "媽媽", "姊姊"])
        let allDone: [Errand] = [item("1", "", "甲", done: true), item("2", "媽媽", "乙", done: true)]
        XCTAssertEqual(errandGroups(allDone).map { (g: ErrandGroup) -> String in g.title }, ["媽媽", ERRAND_NO_WHO])
        XCTAssertEqual(errandGroups([]), [])
    }

    func test寫過的名字_不重複_沒寫的不算() {
        let list: [Errand] = [item("1", "媽媽", "甲"), item("2", "", "乙"), item("3", "爸爸", "丙"), item("4", "媽媽", "丁")]
        XCTAssertEqual(errandNames(list), ["媽媽", "爸爸"])
    }

    func test一列的第二行_幾個和備註() {
        var x: Errand = item("1", "", "面膜")
        XCTAssertNil(errandNote(x))
        x.qty = 3
        XCTAssertEqual(errandNote(x), "3 個")
        x.note = "要綠色的"
        XCTAssertEqual(errandNote(x), "3 個・要綠色的")
        x.qty = 1
        XCTAssertEqual(errandNote(x), "要綠色的")
    }

    /* ---------- 不掉 ---------- */

    func test整趟重排_代購清單帶著() throws {
        var k: Desk = desk()
        add(&k, "媽媽", "面膜")
        k.act(true) { (d: inout AppState) -> Void in
            _ = replanCurrent(&d)
        }
        XCTAssertEqual(whats(k.s.trip?.errands), ["面膜"])
        // AI 整趟重排、改行程設定走的也是 replanTrip
        let trip: Trip = try XCTUnwrap(k.s.trip)
        let next: Trip = replanTrip(trip, draftOf(trip), k.s.settings, true)
        XCTAssertEqual(next.errands, trip.errands)
    }

    func test放一邊再拿回來_代購清單還在_勾的也還在() throws {
        var k: Desk = desk()
        add(&k, "媽媽", "面膜")
        add(&k, "", "泡麵")
        let id: String = try XCTUnwrap(k.s.trip?.errands?.first?.id)
        k.act(true) { (d: inout AppState) -> Void in
            guard var trip = d.trip else { return }
            _ = toggleErrand(&trip, id)
            d.trip = trip
        }
        let kept: [Errand]? = k.s.trip?.errands
        // 開新的一趟：這趟放一邊
        let other: Trip = plan("B", "2027-03-10")
        k.act(false) { (d: inout AppState) -> Void in
            shelveCurrent(&d)
            d.trip = other
        }
        XCTAssertNil(k.s.trip?.errands, "新的一趟沒有別趟的代購")
        XCTAssertEqual(k.s.shelf.first?.trip.errands, kept)
        // 切回去
        let shelfId: String = try XCTUnwrap(k.s.shelf.first?.id)
        k.act(true) { (d: inout AppState) -> Void in
            _ = openShelved(&d, shelfId)
        }
        XCTAssertEqual(k.s.trip?.name, "A")
        XCTAssertEqual(k.s.trip?.errands, kept)
        XCTAssertEqual(k.s.trip?.errands?.first?.done, true)
        // 復原切換：又回到 B，A 的代購還在放一邊的那一份裡
        k.undo()
        XCTAssertEqual(k.s.trip?.name, "B")
        XCTAssertEqual(k.s.shelf.first?.trip.errands, kept)
    }

    func test收起來_去過的旅行和其他排好的都帶著() throws {
        var k: Desk = desk()
        add(&k, "媽媽", "面膜")
        var gone: AppState = k.s
        archiveTrip(&gone)
        XCTAssertEqual(whats(gone.shelf.first?.trip.errands), ["面膜"])

        var trip: Trip = try XCTUnwrap(k.s.trip)
        let first: Found = try XCTUnwrap(allItems(trip).first)
        trip.slots[first.si].items[first.ii].status = .pulled
        k.s.trip = trip
        k.act(true) { (d: inout AppState) -> Void in
            _ = archiveTrip(&d)
        }
        XCTAssertEqual(whats(k.s.baskets.first?.trip?.errands), ["面膜"])
        k.undo()
        XCTAssertEqual(whats(k.s.trip?.errands), ["面膜"])
    }

    func test不要這一版_代購先留著_放進下一趟_復原也不會兩份() {
        var k: Desk = desk()
        add(&k, "媽媽", "面膜")
        add(&k, "", "泡麵")
        var said: String? = nil
        k.act(true) { (d: inout AppState) -> Void in
            said = dropPlan(&d)
        }
        XCTAssertEqual(said, "這一版拿掉了，可以重新開一趟。代購清單的 2 樣也留著，會放進下一趟。")
        XCTAssertNil(k.s.trip)
        XCTAssertEqual(whats(k.s.errands), ["面膜", "泡麵"])
        startTrip(&k, "下一趟")
        XCTAssertEqual(whats(k.s.trip?.errands), ["面膜", "泡麵"])
        XCTAssertEqual(k.s.errands, [])
        XCTAssertEqual(count(k.s, "面膜"), 1)

        k.undo()
        XCTAssertEqual(count(k.s, "面膜"), 1)
        k.undo()
        XCTAssertEqual(k.s.trip?.name, "A")
        XCTAssertEqual(whats(k.s.trip?.errands), ["面膜", "泡麵"])
        XCTAssertEqual(count(k.s, "面膜"), 1)
    }

    func test不要這一版之後_存檔再讀_代購還在() throws {
        var k: Desk = desk()
        add(&k, "媽媽", "面膜")
        k.act(true) { (d: inout AppState) -> Void in
            _ = dropPlan(&d)
        }
        let back: AppState = try hydrated(k.s)
        XCTAssertNil(back.trip)
        XCTAssertEqual(whats(back.errands), ["面膜"])
    }

    func test不要這一版_順路和代購都有_兩句都講() {
        var k: Desk = desk()
        add(&k, "媽媽", "面膜")
        k.act(true) { (d: inout AppState) -> Void in
            _ = addToPool(&d, "甲")
        }
        let said: String? = dropPlan(&k.s)
        XCTAssertEqual(
            said, "這一版拿掉了，可以重新開一趟。順路清單的 1 個地方留著，會放進下一趟。代購清單的 1 樣也留著，會放進下一趟。")
    }

    /* ---------- 復原 ---------- */

    func test勾掉和刪掉都能復原() throws {
        var k: Desk = desk()
        add(&k, "媽媽", "面膜")
        add(&k, "爸爸", "燒酒")
        let id: String = try XCTUnwrap(k.s.trip?.errands?.first?.id)
        k.act(true) { (d: inout AppState) -> Void in
            guard var trip = d.trip else { return }
            _ = toggleErrand(&trip, id)
            d.trip = trip
        }
        XCTAssertEqual(k.s.trip?.errands?.first?.done, true)
        k.undo()
        XCTAssertEqual(k.s.trip?.errands?.first?.done, false)

        k.act(true) { (d: inout AppState) -> Void in
            guard var trip = d.trip else { return }
            _ = removeErrand(&trip, id)
            d.trip = trip
        }
        XCTAssertEqual(whats(k.s.trip?.errands), ["燒酒"])
        k.undo()
        XCTAssertEqual(whats(k.s.trip?.errands), ["面膜", "燒酒"], "刪掉的回到原本的位置")
    }

    func test代購不算改過這一版() throws {
        var t: Trip = plan("A", "2026-12-01")
        let mark: String = planMarkOf(t)
        let untouched: Bool = planUntouched(t)
        _ = addErrand(&t, "媽媽", "面膜")
        XCTAssertEqual(planMarkOf(t), mark)
        XCTAssertEqual(planUntouched(t), untouched)
    }

    /* ---------- 存檔 ---------- */

    func test存檔_每一趟的代購都帶著() throws {
        var k: Desk = desk()
        add(&k, "媽媽", "面膜", 2, "要綠色的")
        let other: Trip = plan("B", "2027-03-10")
        k.act(false) { (d: inout AppState) -> Void in
            shelveCurrent(&d)
            d.trip = other
        }
        add(&k, "", "泡麵")
        let back: AppState = try hydrated(k.s)
        XCTAssertEqual(back.trip?.errands, k.s.trip?.errands)
        XCTAssertEqual(back.shelf.first?.trip.errands, k.s.shelf.first?.trip.errands)
        XCTAssertEqual(back.shelf.first?.trip.errands?.first?.note, "要綠色的")
        XCTAssertEqual(back.shelf.first?.trip.errands?.first?.qty, 2)
    }

    func test舊存檔_沒有代購這一欄_讀得進來() throws {
        var old: AppState = desk().s
        let other: Trip = plan("B", "2027-03-10")
        old.shelf = [Shelved(id: "t-old", trip: other)]
        // 舊版存檔：把每一趟的 errands 這一鍵整個拿掉（沒有代購時本來就不會寫出來，這裡再確定一次）
        let data: Data = try JSONEncoder().encode(old)
        var json: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var trip: [String: Any] = try XCTUnwrap(json["trip"] as? [String: Any])
        trip.removeValue(forKey: "errands")
        json["trip"] = trip
        var shelf: [[String: Any]] = try XCTUnwrap(json["shelf"] as? [[String: Any]])
        for i in shelf.indices {
            var t: [String: Any] = try XCTUnwrap(shelf[i]["trip"] as? [String: Any])
            t.removeValue(forKey: "errands")
            shelf[i]["trip"] = t
        }
        json["shelf"] = shelf
        let oldData: Data = try JSONSerialization.data(withJSONObject: json)
        let text: String = try XCTUnwrap(String(data: oldData, encoding: .utf8))
        XCTAssertFalse(text.contains("errands"))

        let back: AppState = try XCTUnwrap(AppState.hydrate(oldData))
        XCTAssertNotNil(back.trip)
        XCTAssertNil(back.trip?.errands)
        XCTAssertEqual(back.shelf.count, 1)
        XCTAssertNil(back.shelf.first?.trip.errands)
        // 讀進來之後照樣加得進去
        var t: Trip = try XCTUnwrap(back.trip)
        XCTAssertNotNil(addErrand(&t, "媽媽", "面膜"))
        XCTAssertEqual(whats(t.errands), ["面膜"])
    }
}
