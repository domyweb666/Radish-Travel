// 順路清單每趟一份：舊檔搬移、重排、放一邊、收起來、復原都不掉，也不會變成兩份；可以拿掉、不重複加。
// 2026-11-25 多米定的，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class PoolTests: XCTestCase {
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
            movePool(&draft)
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

    private func add(_ k: inout Desk, _ name: String) {
        k.act(true) { (d: inout AppState) -> Void in
            _ = addToPool(&d, name)
        }
    }

    private func startTrip(_ k: inout Desk, _ name: String) {
        let trip: Trip = plan(name, "2027-03-10")
        k.act(false) { (d: inout AppState) -> Void in
            shelveCurrent(&d)
            d.trip = trip
        }
    }

    /// 這個名字一共出現幾次：現在這趟、其他排好的、去過的、還沒放進哪一趟的
    private func count(_ s: AppState, _ name: String) -> Int {
        var all: [String] = s.pool
        all.append(contentsOf: s.trip?.pool ?? [])
        for x in s.shelf { all.append(contentsOf: x.trip.pool ?? []) }
        for b in s.baskets { all.append(contentsOf: b.trip?.pool ?? []) }
        return all.filter { (x: String) -> Bool in x == name }.count
    }

    private func hydrated(_ s: AppState) throws -> AppState {
        let data: Data = try JSONEncoder().encode(s)
        return try XCTUnwrap(AppState.hydrate(data))
    }

    /* ---------- 舊檔 ---------- */

    func test舊檔_有現在這趟_搬進這趟_舊欄位清空_再讀一次也一樣() throws {
        var old: AppState = desk().s
        old.pool = ["甲", "乙", "甲"]
        let once: AppState = try hydrated(old)
        XCTAssertEqual(once.trip?.pool, ["甲", "乙"])
        XCTAssertEqual(once.pool, [])
        let twice: AppState = try hydrated(once)
        XCTAssertEqual(twice.trip?.pool, ["甲", "乙"])
        XCTAssertEqual(twice.pool, [])
    }

    func test舊檔_沒有現在這趟_先留著_開一趟才搬進去() throws {
        var old: AppState = AppState()
        old.pool = ["甲", "乙"]
        var k: Desk = Desk()
        k.s = try hydrated(old)
        XCTAssertEqual(k.s.pool, ["甲", "乙"])
        k.act(false) { (d: inout AppState) -> Void in
            d.remind = true
        }
        XCTAssertEqual(k.s.pool, ["甲", "乙"], "還沒有這趟，別的動作不會動到")
        startTrip(&k, "新的")
        XCTAssertEqual(k.s.trip?.pool, ["甲", "乙"])
        XCTAssertEqual(k.s.pool, [])
    }

    func test舊檔_沒有現在這趟_切回放一邊的那趟也搬進去() throws {
        var k: Desk = desk()
        add(&k, "乙")
        k.act(true) { (d: inout AppState) -> Void in
            shelveCurrent(&d)
        }
        k.s.pool = ["甲", "乙"]
        let id: String = try XCTUnwrap(k.s.shelf.first?.id)
        k.act(true) { (d: inout AppState) -> Void in
            _ = openShelved(&d, id)
        }
        XCTAssertEqual(k.s.trip?.pool, ["乙", "甲"])
        XCTAssertEqual(k.s.pool, [])

        // 退回去：搬進來的回到原本那一份，那一趟自己的留著
        k.undo()
        XCTAssertNil(k.s.trip)
        XCTAssertEqual(k.s.pool, ["甲", "乙"])
        XCTAssertEqual(k.s.shelf.first?.trip.pool, ["乙"])
    }

    func test復原開一趟_搬過去的不會變成兩份_再開一趟還在() {
        var k: Desk = Desk()
        k.s.pool = ["甲"]
        startTrip(&k, "新的")
        XCTAssertEqual(k.s.trip?.pool, ["甲"])
        k.undo()
        XCTAssertNil(k.s.trip)
        XCTAssertEqual(count(k.s, "甲"), 1)
        XCTAssertEqual(k.s.pool, ["甲"])
        startTrip(&k, "再一趟")
        XCTAssertEqual(k.s.trip?.pool, ["甲"])
        XCTAssertEqual(count(k.s, "甲"), 1)
    }

    /* ---------- 不掉 ---------- */

    func test整趟重排_兩種都帶著() throws {
        var k: Desk = desk()
        add(&k, "甲")
        k.act(true) { (d: inout AppState) -> Void in
            _ = replanCurrent(&d)
        }
        XCTAssertEqual(k.s.trip?.pool, ["甲"])
        // AI 整趟重排走的也是 replanTrip，只是多打散
        let trip: Trip = try XCTUnwrap(k.s.trip)
        let next: Trip = replanTrip(trip, draftOf(trip), k.s.settings, true)
        XCTAssertEqual(next.pool, ["甲"])
    }

    func test每趟各一份_放一邊再切回來不掉() throws {
        var k: Desk = desk()
        add(&k, "甲")
        startTrip(&k, "B")
        XCTAssertNil(k.s.trip?.pool, "新的一趟沒有別趟的")
        add(&k, "乙")
        let id: String = try XCTUnwrap(k.s.shelf.first?.id)
        k.act(true) { (d: inout AppState) -> Void in
            _ = openShelved(&d, id)
        }
        XCTAssertEqual(k.s.trip?.pool, ["甲"])
        XCTAssertEqual(k.s.shelf.first?.trip.pool, ["乙"])
        k.undo()
        XCTAssertEqual(k.s.trip?.pool, ["乙"])
        XCTAssertEqual(k.s.shelf.first?.trip.pool, ["甲"])
    }

    func test存檔備份帶著每一趟的() throws {
        var k: Desk = desk()
        add(&k, "甲")
        startTrip(&k, "B")
        add(&k, "乙")
        let back: AppState = try hydrated(k.s)
        XCTAssertEqual(back.trip?.pool, ["乙"])
        XCTAssertEqual(back.shelf.first?.trip.pool, ["甲"])
    }

    func test收起來_去過的旅行和其他排好的都帶著() throws {
        var k: Desk = desk()
        add(&k, "甲")
        var gone: AppState = k.s
        archiveTrip(&gone)
        XCTAssertEqual(gone.shelf.first?.trip.pool, ["甲"])

        var trip: Trip = try XCTUnwrap(k.s.trip)
        let first: Found = try XCTUnwrap(allItems(trip).first)
        trip.slots[first.si].items[first.ii].status = .pulled
        k.s.trip = trip
        k.act(true) { (d: inout AppState) -> Void in
            _ = archiveTrip(&d)
        }
        XCTAssertEqual(k.s.baskets.first?.trip?.pool, ["甲"])
        k.undo()
        XCTAssertEqual(k.s.trip?.pool, ["甲"])
        XCTAssertEqual(count(k.s, "甲"), 1)
    }

    func test不要這一版_先留著_放進下一趟_復原也不會兩份() {
        var k: Desk = desk()
        add(&k, "甲")
        var said: String? = nil
        k.act(true) { (d: inout AppState) -> Void in
            said = dropPlan(&d)
        }
        XCTAssertEqual(said, "這一版拿掉了，可以重新開一趟。順路清單的 1 個地方留著，會放進下一趟。")
        XCTAssertEqual(k.s.pool, ["甲"])
        startTrip(&k, "下一趟")
        XCTAssertEqual(k.s.trip?.pool, ["甲"])
        XCTAssertEqual(count(k.s, "甲"), 1)

        k.undo()
        XCTAssertEqual(count(k.s, "甲"), 1)
        k.undo()
        XCTAssertEqual(k.s.trip?.name, "A")
        XCTAssertEqual(k.s.trip?.pool, ["甲"])
        XCTAssertEqual(count(k.s, "甲"), 1)
    }

    func test不要這一版_沒加過順路的_話不變() {
        var k: Desk = desk()
        let said: String? = dropPlan(&k.s)
        XCTAssertEqual(said, "這一版拿掉了，可以重新開一趟。")
        XCTAssertEqual(k.s.pool, [])
    }

    /* ---------- 加、拿掉 ---------- */

    func test加_不重複_頭尾空白不算不同() {
        var d: AppState = desk().s
        XCTAssertEqual(addToPool(&d, " 甲 "), "「甲」放進這趟的順路清單，不排時間。")
        XCTAssertEqual(addToPool(&d, "甲"), "「甲」已經在這趟的順路清單裡，沒有再加一次。")
        XCTAssertNil(addToPool(&d, "  "))
        XCTAssertEqual(d.trip?.pool, ["甲"])
    }

    func test沒有這趟_不加也不掉() {
        var d: AppState = AppState()
        XCTAssertNil(addToPool(&d, "甲"))
        XCTAssertNil(removeFromPool(&d, "甲"))
        XCTAssertEqual(d, AppState())
    }

    func test拿掉_可以復原_順序不變() {
        var k: Desk = desk()
        add(&k, "甲")
        add(&k, "乙")
        add(&k, "丙")
        var said: String? = nil
        k.act(true) { (d: inout AppState) -> Void in
            said = removeFromPool(&d, "乙")
        }
        XCTAssertEqual(said, "「乙」從順路清單拿掉了。")
        XCTAssertEqual(k.s.trip?.pool, ["甲", "丙"])
        k.undo()
        XCTAssertEqual(k.s.trip?.pool, ["甲", "乙", "丙"])
    }

    func test拿掉最後一個_變回沒有_清單沒有的不動() {
        var d: AppState = desk().s
        addToPool(&d, "甲")
        let before: AppState = d
        XCTAssertNil(removeFromPool(&d, "乙"))
        XCTAssertEqual(d, before)
        removeFromPool(&d, "甲")
        XCTAssertNil(d.trip?.pool)
    }

    func test順路清單不算改過這一版() throws {
        var d: AppState = desk().s
        let trip: Trip = try XCTUnwrap(d.trip)
        let mark: String = planMarkOf(trip)
        addToPool(&d, "甲")
        let after: Trip = try XCTUnwrap(d.trip)
        XCTAssertEqual(planMarkOf(after), mark)
    }
}
