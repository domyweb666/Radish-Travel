// Now.swift 和它接進對話的地方：AI 知道現在第幾天幾點，過去的時段和拔起來的站不動。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class NowTests: XCTestCase {
    /// 12/4（五）出發，五天
    private func trip() -> Trip {
        let d: TripDraft = TripDraft(start: "2026-12-04", days: 5, arrive: .pm, leave: .pm, people: 2)
        return generate(d, defaultSettings())
    }

    /// 第 3 天（12/6 星期日）下午兩點五分
    private let clock: ChatClock = ChatClock(phase: .trip(day: 3), hour: 14, minute: 5)

    func test幾點算哪個時段_旅途中才有現在() {
        XCTAssertEqual(partAt(11), Part.am)
        XCTAssertEqual(partAt(12), Part.pm)
        XCTAssertEqual(partAt(17), Part.pm)
        XCTAssertEqual(partAt(18), Part.eve)
        XCTAssertNil(tripNow(ChatClock(phase: .plan(daysToGo: 12), hour: 9, minute: 0)))
        XCTAssertNil(tripNow(ChatClock(phase: .done, hour: 9, minute: 0)))
        XCTAssertNil(tripNow(nil))
        XCTAssertEqual(tripNow(clock), TripNow(day: 3, part: .pm, clock: "14:05"))
    }

    func test過去的時段_前幾天和今天更早的時段算過了_現在這段不算() {
        let now: TripNow? = tripNow(clock)
        XCTAssertTrue(slotPast(now, 2, .eve))
        XCTAssertTrue(slotPast(now, 3, .am))
        XCTAssertFalse(slotPast(now, 3, .pm))
        XCTAssertFalse(slotPast(now, 4, .am))
        XCTAssertFalse(slotPast(nil, 1, .am), "還沒出發時什麼都沒過")
    }

    func test旅途中_過去的時段不准動_還沒到的照常改() throws {
        var t: Trip = trip()
        var seeds: [Seed] = []
        let now: TripNow? = tripNow(clock)
        let before: Trip = t
        let old: Found = try XCTUnwrap(dayStops(t, 2).first, "第 2 天應該有站")

        let move: [Any] = [["op": "move", "id": old.it.id, "day": 4, "part": "pm"] as [String: Any]]
        let r1: (changes: [String], notes: [String]) = applyOps(&t, &seeds, move, now)
        XCTAssertEqual(r1.changes.count, 0)
        XCTAssertTrue(r1.notes.first?.contains("已經過了") == true)

        let add: [Any] = [["op": "add", "day": 3, "part": "am", "place": ["n": "測試咖啡"]] as [String: Any]]
        XCTAssertTrue(applyOps(&t, &seeds, add, now).notes.first?.contains("已經過了") == true)

        let swapToday: [Any] = [opJSON(.swapDays(a: 3, b: 4))]
        XCTAssertTrue(applyOps(&t, &seeds, swapToday, now).notes.first?.contains("不能整天對調") == true)

        let remove: [Any] = [opJSON(.remove(id: old.it.id))]
        XCTAssertEqual(applyOps(&t, &seeds, remove, now).changes.count, 0)
        XCTAssertEqual(seeds.count, 0)
        XCTAssertEqual(t, before, "擋下來的動作一個都沒改到行程")

        let later: [Any] = [opJSON(.swapDays(a: 4, b: 5))]
        XCTAssertEqual(applyOps(&t, &seeds, later, now).changes.count, 1, "還沒到的兩天照常對調")

        // 沒給現在（還沒出發），第 2 天的站照常能動
        var free: Trip = trip()
        let id: String = try XCTUnwrap(dayStops(free, 2).first).it.id
        let ok: [Any] = [["op": "move", "id": id, "day": 4, "part": "pm"] as [String: Any]]
        XCTAssertEqual(applyOps(&free, &seeds, ok).changes.count, 1)
    }

    func test拔起來的站_不管什麼時候都不動() throws {
        var t: Trip = trip()
        var seeds: [Seed] = []
        let x: Found = try XCTUnwrap(dayStops(t, 4).first, "第 4 天應該有站")
        t.slots[x.si].items[x.ii].status = .pulled
        let r: (changes: [String], notes: [String]) = applyOps(&t, &seeds, [opJSON(.remove(id: x.it.id))])
        XCTAssertEqual(r.changes.count, 0)
        XCTAssertTrue(r.notes.first?.contains("拔起來了") == true)
        XCTAssertTrue(applyOps(&t, &seeds, [opJSON(.swapDays(a: 4, b: 5))]).notes.first?.contains("不能整天對調") == true)
    }

    func test本機指令_今天就是第幾天_旅途中不整趟重排() {
        let t: Trip = trip()
        let now: TripNow? = tripNow(clock)
        let out: BrainOut = localBrain("今天好累", t, now)
        for raw in out.ops {
            guard let o = raw as? [String: Any], let id = o["id"] as? String, let x = findItem(t, id) else {
                XCTFail("拿掉的應該是行程裡的站")
                continue
            }
            XCTAssertEqual(x.s.day, 3)
            XCTAssertFalse(slotPast(now, x.s.day, x.s.part), "不會拿掉今天已經過了的時段")
        }
        let regen: BrainOut = localBrain("重排", t, now)
        XCTAssertNil(regen.regen)
        XCTAssertEqual(regen.reply, NO_REGEN_ON_TRIP)
        XCTAssertEqual(localBrain("重排", t).regen, true, "還沒出發照常重排")
    }

    func test提示詞_講現在_每天有星期幾_標出過了和拔起來的() throws {
        var t: Trip = trip()
        let x: Found = try XCTUnwrap(dayStops(t, 4).first)
        t.slots[x.si].items[x.ii].status = .pulled
        let st: Settings = defaultSettings()
        let p: String = aiPrompt("下一站去哪", t, st, [], clock)
        XCTAssertTrue(p.contains("現在是旅途中第 3 天 12/6（日） 14:05，下午。"))
        XCTAssertTrue(p.contains("第 1 天 12/4（五）"))
        XCTAssertTrue(p.contains("第 3 天 12/6（日）（今天）"))
        XCTAssertTrue(p.contains("；已經過了"))
        XCTAssertTrue(p.contains(",拔起來了"))
        XCTAssertTrue(p.contains("旅途中不要整趟重排"))

        let plan: String = aiPrompt("下一站去哪", t, st, [], ChatClock(phase: .plan(daysToGo: 12), hour: 9, minute: 0))
        XCTAssertTrue(plan.contains("現在還沒出發，離出發還有 12 天。"))
        XCTAssertTrue(plan.contains("第 1 天 12/4（五）"))
        XCTAssertFalse(plan.contains("已經過了"))

        let old: String = aiPrompt("下一站去哪", t, st, [])
        XCTAssertFalse(old.contains("現在是"))
    }
}
