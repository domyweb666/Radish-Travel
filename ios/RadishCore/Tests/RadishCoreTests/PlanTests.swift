// 排行程規則的測試。照 mobile/tests/plan.test.ts 一個一個搬。
import XCTest

@testable import RadishCore

private func planDraft(
    days: Int = 5, arrive: Part = .pm, leave: Part = .pm, start: String = "2026-12-04", tweaks: [Tweak]? = nil
) -> TripDraft {
    return TripDraft(
        tweaks: tweaks, city: nil, base: nil, stayName: nil, name: nil, cover: nil,
        start: start, days: days, arrive: arrive, leave: leave, people: 2
    )
}

/// TS 的 n.replace(/（.*?）/g, '')
private func stripParens(_ s: String) -> String {
    guard let re = try? NSRegularExpression(pattern: "（.*?）", options: []) else { return s }
    let range: NSRange = NSRange(s.startIndex..<s.endIndex, in: s)
    return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
}

final class PlanTests: XCTestCase {
    func test排出來的行程守住機制規則() throws {
        let daysList: [Int] = [3, 4, 5, 7, 10, 14]
        let paces: [Pace] = [.slow, .mid, .fast]
        for days in daysList {
            for pace in paces {
                var st: Settings = defaultSettings()
                st.pace = pace
                let t: Trip = generate(planDraft(days: days), st)
                XCTAssertEqual(t.slots.count, days * 3)
                let all: [Found] = allItems(t)
                let ids: [String] = all.map { (x: Found) -> String in x.it.id }
                XCTAssertEqual(Set(ids).count, ids.count, "同一站不會排兩次")
                for d in 1...days {
                    XCTAssertTrue(bigCount(t, d) <= 2, "第 \(d) 天大站不超過 2")
                }
                XCTAssertEqual(bigCount(t, 1), 0, "第一天不排大站")
                XCTAssertEqual(bigCount(t, days), 0, "最後一天不排大站")
                let allWhy: Bool = all.allSatisfy { (x: Found) -> Bool in x.it.why.count > 0 }
                XCTAssertTrue(allWhy, "每一站都有為什麼")
            }
        }
    }

    func test下午到的第一天_上午是在路上() throws {
        let t: Trip = generate(planDraft(arrive: .pm), defaultSettings())
        let am: Slot? = t.slots.first { (s: Slot) -> Bool in s.day == 1 && s.part == .am }
        let eve: Slot? = t.slots.first { (s: Slot) -> Bool in s.day == 1 && s.part == .eve }
        XCTAssertEqual(am?.off, true)
        XCTAssertNil(eve?.off)
    }

    func test拿掉的站進下次再來_可以排回原本的時段() throws {
        var t: Trip = generate(planDraft(), defaultSettings())
        var seeds: [Seed] = []
        let x: Found = try XCTUnwrap(dayStops(t, 2).first)
        let before: Int = allItems(t).count
        _ = seedOut(&t, &seeds, x.it.id, "測試")
        XCTAssertEqual(allItems(t).count, before - 1)
        XCTAssertEqual(seeds.count, 1)
        let seedId: String = try XCTUnwrap(seeds.first).id
        let msg: String = restoreSeed(&t, &seeds, seedId)
        XCTAssertTrue(msg.contains("第 \(x.s.day) 天"), msg)
        XCTAssertEqual(allItems(t).count, before)
        XCTAssertEqual(seeds.count, 0)
    }

    func test移動_對調_換一個_自己加() throws {
        let st: Settings = defaultSettings()
        var t: Trip = generate(planDraft(), st)
        let x: Found = try XCTUnwrap(dayStops(t, 2).first)
        let id: String = x.it.id
        let moved: String? = moveItem(&t, id, 3, .pm)
        XCTAssertNil(moved)
        let day3: [Found] = dayStops(t, 3)
        XCTAssertTrue(day3.contains { (y: Found) -> Bool in y.it.id == id })
        let blocked: String = moveItem(&t, id, 1, .am) ?? ""
        XCTAssertTrue(blocked.contains("在路上"), blocked)
        let swapped: String? = swapParts(&t, 2, .am, .pm)
        XCTAssertNil(swapped)
        let target: Stop = try XCTUnwrap(dayStops(t, 3).first).it
        let alts: [Place] = alternatives(t, st, target)
        XCTAssertTrue(alts.count > 0)
        let alt: Place = try XCTUnwrap(alts.first)
        let replaced: String? = replaceWith(&t, target.id, alt)
        XCTAssertNil(replaced)
        let after: [Found] = allItems(t)
        XCTAssertTrue(after.contains { (y: Found) -> Bool in y.it.id == alt.id })
        var seeds: [Seed] = []
        let added: String = addOwn(&t, &seeds, "我想去的店")
        XCTAssertTrue(added.contains("排在第"), added)
    }

    func test本機指令聽得懂的那幾種() throws {
        var t: Trip = generate(planDraft(), defaultSettings())
        var seeds: [Seed] = []
        let a: BrainOut = localBrain("第 2 天上午下午對調", t)
        let ra = applyOps(&t, &seeds, a.ops)
        XCTAssertEqual(ra.changes.count, 1)
        let third: Found = try XCTUnwrap(dayStops(t, 3).first)
        let name: String = stripParens(third.it.n)
        let b: BrainOut = localBrain("不要\(name)", t)
        let r = applyOps(&t, &seeds, b.ops)
        XCTAssertEqual(r.changes.count, 1)
        XCTAssertEqual(seeds.count, 1)
        XCTAssertEqual(localBrain("重排", t).regen, true)
        XCTAssertEqual(localBrain("今天天氣如何", t).ops.count, 0)
        let bad: [Op] = [Op.move(id: "nope", day: 2, part: .am)]
        let rbad = applyOps(&t, &seeds, bad)
        XCTAssertEqual(rbad.notes, ["找不到那一站"])
    }

    func test花費與路程算得出數字() throws {
        let st: Settings = defaultSettings()
        let t: Trip = generate(planDraft(), st)
        let c: (rows: [CostRow], total: Double, people: Int) = cost(t, st)
        XCTAssertTrue(c.total > 0 && c.total.isFinite)
        let legs: [Leg?] = dayLegs(t, st, 2)
        XCTAssertEqual(legs.count, dayStops(t, 2).count + 1)
        XCTAssertTrue(planText(t).contains("第 5 天"))
    }

    func test日期() throws {
        XCTAssertEqual(addDays("2026-12-30", 3), "2027-01-02")
        XCTAssertEqual(diffDays("2026-12-04", "2026-12-08"), 4)
        XCTAssertEqual(fmtDay("2026-12-04"), "12/4（五）")
        let grid: [String?] = monthGrid(2026, 12)
        let filled: [String] = grid.compactMap { (x: String?) -> String? in x }
        XCTAssertEqual(filled.count, 31)
        XCTAssertEqual(phaseOf("2026-12-04", 5, "2026-11-15", nil), Phase.plan(daysToGo: 19))
        XCTAssertEqual(phaseOf("2026-12-04", 5, "2026-12-06", nil), Phase.trip(day: 3))
        XCTAssertEqual(phaseOf("2026-12-04", 5, "2026-12-09", nil), Phase.done)
        XCTAssertEqual(phaseOf("2026-12-04", 5, "2026-11-15", 2), Phase.trip(day: 2))
    }
}
