// Permit.swift：權限表。直接改的照做，要確認的沒按「套用」不做，表上沒有的不做。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class PermitTests: XCTestCase {
    private func trip() -> Trip {
        let d: TripDraft = TripDraft(start: "2026-12-04", days: 5, arrive: .pm, leave: .pm, people: 2)
        return generate(d, defaultSettings())
    }

    /// 把第 3 天第一站改成「自己加的」
    private func withMine(_ t: inout Trip) throws -> Found {
        let x: Found = try XCTUnwrap(dayStops(t, 3).first, "第 3 天應該有站")
        t.slots[x.si].items[x.ii].mine = true
        return try XCTUnwrap(findItem(t, x.it.id))
    }

    func test權限表_一般的直接改_自己加的站和這趟調整要確認_表上沒有的不做() throws {
        var t: Trip = trip()
        let normal: Found = try XCTUnwrap(dayStops(t, 2).first)
        XCTAssertEqual(opLevel(t, opJSON(.remove(id: normal.it.id))), OpLevel.direct)
        XCTAssertEqual(opLevel(t, ["op": "setTweak", "tweak": "easy", "on": true]), OpLevel.confirm)
        XCTAssertNil(opLevel(t, ["op": "pull", "id": normal.it.id]), "拔起來沒有 op 能做")
        XCTAssertNil(opLevel(t, ["op": "setHabit"]))

        let mine: Found = try withMine(&t)
        XCTAssertEqual(opLevel(t, opJSON(.remove(id: mine.it.id))), OpLevel.confirm)
        XCTAssertEqual(opLevel(t, opJSON(.move(id: mine.it.id, day: 4, part: .pm))), OpLevel.confirm)
        XCTAssertEqual(opLevel(t, opJSON(.swapDays(a: 3, b: 4))), OpLevel.confirm, "整天對調會帶走自己加的站")
        XCTAssertEqual(opLevel(t, opJSON(.swapParts(day: 3, a: mine.s.part, b: mine.s.part == .am ? .pm : .am))), OpLevel.confirm)
        XCTAssertEqual(opLevel(t, opJSON(.swapDays(a: 4, b: 5))), OpLevel.direct)
    }

    func test分兩堆_要確認的沒按套用不做_按了才做() throws {
        var t: Trip = trip()
        var seeds: [Seed] = []
        let mine: Found = try withMine(&t)
        let other: Found = try XCTUnwrap(dayStops(t, 2).first)
        let ops: [Any] = [
            opJSON(.remove(id: other.it.id)),
            opJSON(.remove(id: mine.it.id)),
            ["op": "setTweak", "tweak": "save", "on": true] as [String: Any],
        ]
        let split: (direct: [Any], confirm: [[String: Any]]) = splitOps(t, ops)
        XCTAssertEqual(split.direct.count, 1)
        XCTAssertEqual(split.confirm.count, 2)

        // 繞過分堆、直接整串丟進 applyOps：要確認的照樣不做，只記一句
        var raw: Trip = t
        var rawSeeds: [Seed] = []
        let blind: (changes: [String], notes: [String]) = applyOps(&raw, &rawSeeds, ops)
        XCTAssertEqual(blind.changes.count, 1)
        XCTAssertEqual(blind.notes.filter { (n: String) -> Bool in n.hasSuffix("要你確認才改") }.count, 2)
        XCTAssertNotNil(findItem(raw, mine.it.id), "自己加的站還在")
        XCTAssertNil(raw.tweaks)

        // 存進對話再拿出來（模擬按套用）
        _ = applyOps(&t, &seeds, split.direct)
        let packed: String = packOps(split.confirm)
        let lines: [String] = split.confirm.map { (o: [String: Any]) -> String in opLine(t, o) }
        XCTAssertTrue(lines[0].contains(mine.it.n) && lines[0].contains("自己加的"))
        XCTAssertEqual(lines[1], "這趟加上「想省一點」")
        let r: (changes: [String], notes: [String]) = applyOps(&t, &seeds, unpackOps(packed), nil, true)
        XCTAssertEqual(r.changes.count, 2)
        XCTAssertNil(findItem(t, mine.it.id))
        XCTAssertEqual(t.tweaks, [Tweak.save])
        XCTAssertEqual(seeds.count, 2, "拿掉的兩站都在下次再來")
    }

    func test這趟調整_加上拿掉_不重複() {
        var t: Trip = trip()
        XCTAssertNil(setTweak(&t, "easy", true))
        XCTAssertNil(setTweak(&t, "easy", true))
        XCTAssertEqual(t.tweaks, [Tweak.easy])
        XCTAssertNil(setTweak(&t, "easy", false))
        XCTAssertNil(t.tweaks)
        XCTAssertEqual(setTweak(&t, "party", true), "沒有這種調整")
    }

    func test本機指令_這趟想輕鬆一點_回確認卡() throws {
        let t: Trip = trip()
        let out: BrainOut = localBrain("這趟想輕鬆一點", t)
        XCTAssertEqual(out.reply, NEED_CONFIRM)
        let split: (direct: [Any], confirm: [[String: Any]]) = splitOps(t, out.ops)
        XCTAssertEqual(split.confirm.count, 1)
        XCTAssertEqual(opLine(t, try XCTUnwrap(split.confirm.first)), "這趟加上「想輕鬆一點」")
        XCTAssertEqual(LOCAL_HINTS.first, "這趟想輕鬆一點")
        XCTAssertTrue(localBrain("第 3 天輕鬆一點", t).reply.contains("鬆一點"), "講到第幾天的照舊拿掉一站")
    }

    func test提示詞_告訴AI哪些要確認() {
        let p: String = aiPrompt("這趟想省一點", trip(), defaultSettings(), [])
        XCTAssertTrue(p.contains("\"op\":\"setTweak\""))
        XCTAssertTrue(p.contains("不要說已經改好"))
    }
}
