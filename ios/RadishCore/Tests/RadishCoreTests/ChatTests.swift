// mobile/tests/plan.test.ts 裡只測 chat.ts（localBrain、applyOps）的那一條：「本機指令聽得懂的那幾種」。
// plan.test.ts 其他的在 PlanTests.swift，這一條不要再搬一次。
import XCTest

@testable import RadishCore

final class ChatTests: XCTestCase {
    private func draft() -> TripDraft {
        return TripDraft(start: "2026-12-04", days: 5, arrive: .pm, leave: .pm, people: 2)
    }

    func test本機指令聽得懂的那幾種() {
        var t: Trip = generate(draft(), defaultSettings())
        var seeds: [Seed] = []
        let a: BrainOut = localBrain("第 2 天上午下午對調", t)
        XCTAssertEqual(applyOps(&t, &seeds, a.ops).changes.count, 1)
        guard let third = dayStops(t, 3).first else {
            XCTFail("第 3 天應該有站")
            return
        }
        // TS：n.replace(/（.*?）/g, '')
        let name: String = third.it.n.replacingOccurrences(of: "（.*?）", with: "", options: .regularExpression)
        let b: BrainOut = localBrain("不要\(name)", t)
        let r: (changes: [String], notes: [String]) = applyOps(&t, &seeds, b.ops)
        XCTAssertEqual(r.changes.count, 1)
        XCTAssertEqual(seeds.count, 1)
        XCTAssertEqual(localBrain("重排", t).regen, true)
        XCTAssertEqual(localBrain("今天天氣如何", t).ops.count, 0)
        let raw: [Any] = [["op": "move", "id": "nope", "day": 2, "part": "am"] as [String: Any]]
        XCTAssertEqual(applyOps(&t, &seeds, raw).notes, ["找不到那一站"])
    }
}
