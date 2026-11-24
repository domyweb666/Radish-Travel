// 2026-11-24 code review 修的「跟 AI 講」幾條：沒改就不說改好了、沒做的幾步講出來、沒站不說拔完了、重排由手機做。
// iOS 版才有，mobile/tests/ 沒有對應的。
import XCTest

@testable import RadishCore

final class TalkFixesTests: XCTestCase {
    private func trip() -> Trip {
        let d: TripDraft = TripDraft(start: "2026-12-04", days: 5, arrive: .pm, leave: .pm, people: 2)
        return generate(d, defaultSettings())
    }

    /// 每一站都改一下
    private func eachStop(_ t: Trip, _ change: (inout Stop) -> Void) -> Trip {
        var out: Trip = t
        for si in out.slots.indices {
            for ii in out.slots[si].items.indices {
                change(&out.slots[si].items[ii])
            }
        }
        return out
    }

    private func emptyDay(_ t: Trip, _ day: Int) -> Trip {
        var out: Trip = t
        for si in out.slots.indices where out.slots[si].day == day {
            out.slots[si].items = []
        }
        return out
    }

    private func bare(_ name: String) -> String {
        return name.replacingOccurrences(of: "（.*?）", with: "", options: .regularExpression)
    }

    private func error(_ run: () throws -> BrainOut) -> AskError? {
        do {
            _ = try run()
            return nil
        } catch let e {
            return e as? AskError
        }
    }

    /* ---------- 1 沒回好就丟錯 ---------- */

    func testAI只回純文字_截斷_沒有reply_都算沒回好() {
        let bad: [String] = [
            "沒有 JSON",
            "{\"reply\":\"第 3 天少排",
            "{\"reply\":\"好\",\"ops\":[{\"op\":\"remove\",\"id\":\"p3\"}",
            "{\"ops\":[]}",
            "{\"reply\":null,\"ops\":[]}",
            "{\"reply\":\"  \",\"ops\":[]}",
            "{\"reply\":\"好\",\"ops\":{\"op\":\"remove\",\"id\":\"p3\"}}",
            "{}",
        ]
        for text in bad {
            XCTAssertEqual(error { try brainFromText(text) }, AskError.badReply, text)
        }
    }

    func test有reply沒有ops_當成沒有要改() throws {
        let out: BrainOut = try brainFromText("{\"reply\":\"這天已經算順。\"}")
        XCTAssertEqual(out.reply, "這天已經算順。")
        XCTAssertTrue(out.ops.isEmpty)
        let null: BrainOut = try brainFromText("{\"reply\":\"好\",\"ops\":null}")
        XCTAssertTrue(null.ops.isEmpty)
    }

    private func claude(_ stop: String, _ text: String) throws -> Data {
        let obj: [String: Any] = [
            "stop_reason": stop,
            "content": [["type": "text", "text": text] as [String: Any]],
        ]
        return try JSONSerialization.data(withJSONObject: obj, options: [])
    }

    func test直接問Claude_被切斷和被擋下都算沒回好() throws {
        let full: String = "{\"reply\":\"改好了。\",\"ops\":[]}"
        let cut: Data = try claude("max_tokens", full)
        let refused: Data = try claude("refusal", full)
        let fine: Data = try claude("end_turn", full)
        XCTAssertEqual(error { try brainFromClaude(cut) }, AskError.cutOff)
        XCTAssertEqual(error { try brainFromClaude(refused) }, AskError.refused)
        XCTAssertEqual(try brainFromClaude(fine).reply, "改好了。")
        XCTAssertEqual(error { try brainFromClaude(Data("壞的".utf8)) }, AskError.badReply)
    }

    func test後端回的_兩種格式都讀得出來_缺reply算沒回好() throws {
        let plain: Data = Data("{\"reply\":\"好的。\",\"ops\":[]}".utf8)
        XCTAssertEqual(try brainFromServer(plain).reply, "好的。")
        let wrapped: Data = try JSONSerialization.data(
            withJSONObject: ["text": "好 {\"reply\":\"好的。\",\"ops\":[]}"] as [String: Any], options: [])
        XCTAssertEqual(try brainFromServer(wrapped).reply, "好的。")
        let pure: Data = Data("{\"text\":\"我不會用 JSON\"}".utf8)
        XCTAssertEqual(error { try brainFromServer(pure) }, AskError.badReply)
        for raw in ["null", "[]", "{}", "壞的", "{\"error\":\"x\"}"] {
            let body: Data = Data(raw.utf8)
            XCTAssertEqual(error { try brainFromServer(body) }, AskError.badReply, raw)
        }
        let cut: Data = Data("{\"stop_reason\":\"max_tokens\",\"text\":\"{}\"}".utf8)
        XCTAssertEqual(error { try brainFromServer(cut) }, AskError.cutOff)
    }

    /* ---------- 2 本機指令套不上就老實說 ---------- */

    func test本機指令_沒有那一天_沒有時段_跟現在一樣_都不說做好了() {
        let t: Trip = trip()
        let far: BrainOut = localBrain("第 2 天跟第 9 天對調", t)
        XCTAssertTrue(far.ops.isEmpty)
        XCTAssertTrue(far.reply.contains("沒有第 9 天"), far.reply)
        XCTAssertFalse(far.reply.contains("對調了"), far.reply)

        XCTAssertNil(slotAt(t, 1, .am), "第 1 天上午在路上")
        let road: BrainOut = localBrain("第 1 天上午下午對調", t)
        XCTAssertTrue(road.ops.isEmpty)
        XCTAssertTrue(road.reply.contains("沒做成"), road.reply)

        let same: BrainOut = localBrain("第 2 天跟第 2 天對調", t)
        XCTAssertTrue(same.ops.isEmpty)
        XCTAssertTrue(same.reply.contains("跟現在一樣"), same.reply)

        let huge: BrainOut = localBrain("第 99999999999999999999 天輕鬆一點", t)
        XCTAssertTrue(huge.ops.isEmpty)
        XCTAssertTrue(huge.reply.contains("只有 5 天"), huge.reply)
    }

    func test本機指令_套得上的照舊_一邊在路上的不說整天() {
        let t: Trip = trip()
        let full: BrainOut = localBrain("第 2 天跟第 4 天對調", t)
        XCTAssertEqual(full.ops.count, 1)
        XCTAssertEqual(full.reply, "第 2 天和第 4 天整天對調了。")
        let half: BrainOut = localBrain("第 1 天跟第 3 天對調", t)
        XCTAssertEqual(half.ops.count, 1)
        XCTAssertTrue(half.reply.contains("在路上的時段沒有動"), half.reply)
    }

    func test本機指令_動到自己加的站_說要點頭_不說拿掉了() throws {
        let t: Trip = eachStop(trip()) { (s: inout Stop) -> Void in s.mine = true }
        let x: Found = try XCTUnwrap(dayStops(t, 3).first)
        for said in ["不要\(bare(x.it.n))", "第 3 天輕鬆一點", "第 2 天跟第 4 天對調"] {
            let out: BrainOut = localBrain(said, t)
            XCTAssertEqual(out.reply, NEED_CONFIRM, said)
            let split: (direct: [Any], confirm: [[String: Any]]) = splitOps(t, out.ops)
            XCTAssertEqual(split.confirm.count, 1, said)
            XCTAssertEqual(split.direct.count, 0, said)
        }
    }

    func test本機指令_拔起來的站_沒有站的那天() throws {
        let t: Trip = eachStop(trip()) { (s: inout Stop) -> Void in s.status = .pulled }
        let x: Found = try XCTUnwrap(dayStops(t, 3).first)
        let out: BrainOut = localBrain("不要\(bare(x.it.n))", t)
        XCTAssertTrue(out.ops.isEmpty)
        XCTAssertTrue(out.reply.contains("拔起來了"), out.reply)
        let none: BrainOut = localBrain("第 3 天輕鬆一點", emptyDay(trip(), 3))
        XCTAssertTrue(none.ops.isEmpty)
        XCTAssertTrue(none.reply.contains("沒有還能拿掉的站"), none.reply)
    }

    func test本機指令_這趟已經有的調整_不再跳確認卡() {
        var t: Trip = trip()
        t.tweaks = [Tweak.easy]
        let out: BrainOut = localBrain("這趟想輕鬆一點", t)
        XCTAssertTrue(out.ops.isEmpty)
        XCTAssertTrue(out.reply.contains("已經有"), out.reply)
    }

    /* ---------- 3 沒做的幾步講出來 ---------- */

    func test看不懂的動作_講有幾步沒做() {
        var t: Trip = trip()
        let before: Trip = t
        var seeds: [Seed] = []
        let ops: [Any] = [["op": "pull", "id": "p3"] as [String: Any], 5, "x", ["id": "p3"] as [String: Any]]
        let r: (changes: [String], notes: [String]) = applyOps(&t, &seeds, ops)
        XCTAssertEqual(r.changes, [])
        XCTAssertEqual(r.notes, ["有 4 步看不懂，沒有做"])
        XCTAssertEqual(t, before)
    }

    func test超過20步_後面的不做_講有幾步() {
        let one: [String: Any] = ["op": "rest", "day": 3, "part": "pm", "on": true]
        let ops: [Any] = Array(repeating: one as Any, count: 22)
        var t: Trip = trip()
        var seeds: [Seed] = []
        let r: (changes: [String], notes: [String]) = applyOps(&t, &seeds, ops)
        XCTAssertEqual(r.changes.count, OPS_MAX)
        XCTAssertEqual(r.notes, ["一次最多做 20 步，後面有 2 步沒做"])

        // app 是先分堆再套：分堆切掉的也要講
        var t2: Trip = trip()
        let split: (direct: [Any], confirm: [[String: Any]]) = splitOps(t2, ops)
        let r2: (changes: [String], notes: [String]) = applyOps(&t2, &seeds, split.direct)
        XCTAssertEqual(r2.changes.count, OPS_MAX)
        XCTAssertEqual(r2.notes, ["一次最多做 20 步，後面有 2 步沒做"])
    }

    func test超過20步_全部要確認_也講得出來() {
        let one: [String: Any] = ["op": "setTweak", "tweak": "easy", "on": true]
        let ops: [Any] = Array(repeating: one as Any, count: 23)
        var t: Trip = trip()
        var seeds: [Seed] = []
        let split: (direct: [Any], confirm: [[String: Any]]) = splitOps(t, ops)
        XCTAssertEqual(split.confirm.count, OPS_MAX)
        let r: (changes: [String], notes: [String]) = applyOps(&t, &seeds, split.direct)
        XCTAssertEqual(r.changes, [])
        XCTAssertEqual(r.notes, ["一次最多做 20 步，後面有 3 步沒做"])
    }

    /* ---------- 4 沒站就講沒站 ---------- */

    func test下一站_今天沒站講沒站_拔完了才講拔完() {
        let now: TripNow = TripNow(day: 3, part: .am, clock: "09:00")
        var d: AppState = AppState()
        d.trip = emptyDay(trip(), 3)
        XCTAssertEqual(phoneAnswer("下一站去哪", d, 3, nil, now), "今天沒有排站。")
        d.trip = eachStop(trip()) { (s: inout Stop) -> Void in s.status = .pulled }
        XCTAssertEqual(phoneAnswer("下一站去哪", d, 3, nil, now), "今天排的都拔完了。")
    }

    /* ---------- 5 重排由手機做 ---------- */

    func test重排_只認單純叫整趟重排的() {
        let yes: [String] = [
            "重排", "重排。", "整趟重排", "整趟重排一次", "幫我重排", "請幫我整趟重新排", "重新排過", "那就重排吧", "照這個調整重排", "行程重排一遍",
        ]
        for s in yes { XCTAssertTrue(talkWantsRegen(s), s) }
        let no: [String] = [
            "不要重排", "別重排", "先不重排", "要不要重排？", "第 3 天重排", "這天重排", "今天重排", "重排之後多一點咖啡廳", "已經重排了", "排咖啡廳", "",
        ]
        for s in no { XCTAssertFalse(talkWantsRegen(s), s) }
    }

    func test重排_在看某一天的時候說_還是整趟() {
        let t: Trip = trip()
        let heard: String = talkLocal("重排", t, 3, nil, true)
        XCTAssertEqual(heard, "重排")
        XCTAssertEqual(localBrain(heard, t).regen, true)
    }

    func test重排_只講一天或說不要_不會整趟重排() {
        let t: Trip = trip()
        for s in ["第 3 天重排", "不要重排"] {
            let out: BrainOut = localBrain(s, t)
            XCTAssertNil(out.regen, s)
            XCTAssertTrue(out.ops.isEmpty, s)
            XCTAssertTrue(out.reply.contains("這趟沒有動"), out.reply)
        }
    }

    func test重排_有拔起來的站就不重排() {
        let t: Trip = eachStop(trip()) { (s: inout Stop) -> Void in s.status = .pulled }
        let out: BrainOut = localBrain("重排", t)
        XCTAssertNil(out.regen)
        XCTAssertEqual(out.reply, NO_REGEN_VISITED)
    }

    func test提示詞_告訴AI沒有整趟重排() {
        let p: String = aiPrompt("幫我看一下", trip(), defaultSettings(), [])
        XCTAssertTrue(p.contains("你沒有整趟重排的動作"))
    }
}
