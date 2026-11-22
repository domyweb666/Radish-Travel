// 跟 AI 講（片 2、片 3）：在看哪裡怎麼帶進句子、手機答得出的先答、改完每一天差多少、舊的對話存檔讀得出來。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class TalkTests: XCTestCase {
    private func trip() -> Trip {
        let d: TripDraft = TripDraft(start: "2026-12-04", days: 5, arrive: .pm, leave: .pm, people: 2)
        return generate(d, defaultSettings())
    }

    func test在看哪一天_這天換成第幾天_沒講哪天的補上_講整趟的不動() {
        let t: Trip = trip()
        XCTAssertEqual(talkLocal("這天太滿", t, 3, nil, true), "第 3 天太滿")
        XCTAssertEqual(talkLocal("上午下午對調", t, 3, nil, true), "第 3 天上午下午對調")
        XCTAssertEqual(talkLocal("第 2 天上午下午對調", t, 3, nil, true), "第 2 天上午下午對調")
        XCTAssertEqual(talkLocal("這趟想輕鬆一點", t, 3, nil, true), "這趟想輕鬆一點")
        let out: BrainOut = localBrain(talkLocal("上午下午對調", t, 3, nil, true), t)
        XCTAssertEqual(out.ops.count, 1, "補上第 3 天之後本機指令聽得懂")
    }

    func test在看某一站_這一站換成站名() throws {
        let t: Trip = trip()
        let x: Found = try XCTUnwrap(dayStops(t, 3).first, "第 3 天應該有站")
        let heard: String = talkLocal("不去這一站", t, x.s.day, x.it.id, false)
        XCTAssertFalse(heard.contains("這一站"))
        XCTAssertEqual(localBrain(heard, t).ops.count, 1, "換成站名之後本機指令拿得掉")
        XCTAssertTrue(talkFocus(t, nil, x.it.id).contains(x.it.id))
        XCTAssertTrue(talkFocus(t, 3, nil).contains("第 3 天"))
        XCTAssertEqual(talkFocus(t, 99, nil), "")
    }

    func test手機答得出的先答_要改這趟的不答() {
        var d: AppState = AppState()
        d.trip = trip()
        let count: String? = phoneAnswer("第 3 天還剩幾站？", d, 1, nil, nil)
        XCTAssertNotNil(count)
        XCTAssertTrue(count?.hasPrefix("第 3 天還剩") == true)
        XCTAssertNotNil(phoneAnswer("有哪些要先訂", d, 3, nil, nil))
        XCTAssertNotNil(phoneAnswer("下次再來有哪些", d, 3, nil, nil))
        XCTAssertNil(phoneAnswer("多排一間咖啡廳", d, 3, nil, nil))
        XCTAssertNil(phoneAnswer("第 3 天太滿", d, 3, nil, nil))
        XCTAssertNil(phoneAnswer("下一站換掉", d, 3, nil, nil))
        XCTAssertEqual(phoneAnswer("第 9 天還剩幾站", d, 3, nil, nil), "這趟只有 5 天。")
    }

    func test說今天明天_旅途中照今天算() {
        let now: TripNow = TripNow(day: 2, part: .am, clock: "09:00")
        XCTAssertEqual(talkDay("明天要注意什麼", 1, now), 3)
        XCTAssertEqual(talkDay("今天還剩幾站", 1, now), 2)
        XCTAssertEqual(talkDay("明天要注意什麼", 4, nil), 4, "不在旅途中，明天不知道是哪天")
        XCTAssertEqual(talkDay("第 5 天呢", 1, now), 5)
    }

    func test改完每一天差多少_沒變的天不寫() throws {
        let before: Trip = trip()
        var after: Trip = before
        var seeds: [Seed] = []
        let x: Found = try XCTUnwrap(dayStops(before, 3).first)
        applyOps(&after, &seeds, [opJSON(.remove(id: x.it.id))])
        let lines: [String] = dayDeltas(before, after, defaultSettings())
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines.first?.hasPrefix("第 3 天：") == true)
        XCTAssertTrue(lines.first?.hasSuffix("分鐘（估）") == true)
        XCTAssertEqual(dayDeltas(before, before, defaultSettings()), [])
    }

    func test提示詞帶上在看哪裡() {
        let t: Trip = trip()
        let focus: String = talkFocus(t, 3, nil)
        XCTAssertTrue(aiPrompt("這天太滿", t, defaultSettings(), [], nil, focus).contains(focus))
        XCTAssertFalse(aiPrompt("這天太滿", t, defaultSettings(), []).contains("使用者現在在看"))
    }

    func test舊的對話存檔讀得出來_新欄位是空的() throws {
        let old: String = #"{"r":"ai","t":"好了。","changes":["第 2 天上午和下午對調"]}"#
        let m: ChatMsg = try JSONDecoder().decode(ChatMsg.self, from: Data(old.utf8))
        XCTAssertEqual(m.t, "好了。")
        XCTAssertNil(m.local)
        XCTAssertNil(m.failed)
        XCTAssertNil(m.undo)
        XCTAssertNil(m.day)
    }

    func test直接問Claude_回的文字裡夾著JSON也讀得出來() throws {
        let text: String = "好的。 {\"reply\":\"第 3 天少排一站。\",\"ops\":[{\"op\":\"remove\",\"id\":\"p3\"}]}"
        let out: BrainOut = try brainFromText(text)
        XCTAssertEqual(out.reply, "第 3 天少排一站。")
        XCTAssertEqual(out.ops.count, 1)
        let none: BrainOut = try brainFromText("沒有 JSON")
        XCTAssertEqual(none.reply, "好了。")
        XCTAssertTrue(none.ops.isEmpty)
    }

    func test有填金鑰就算接上AI() {
        let oldKey: String = CLAUDE_KEY
        let oldEnd: String = AI_ENDPOINT
        defer {
            CLAUDE_KEY = oldKey
            AI_ENDPOINT = oldEnd
        }
        CLAUDE_KEY = ""
        AI_ENDPOINT = ""
        XCTAssertFalse(aiReady())
        CLAUDE_KEY = "sk-ant-test"
        XCTAssertTrue(aiReady())
        XCTAssertEqual(AskError.badKey(401).description, "Claude API 金鑰不能用（HTTP 401），到平常的我重新填")
    }

    func test句數_只有走後端才算_第一趟20句之後100句() {
        var t: Trip = trip()
        XCTAssertNil(aiLeft(t, firstTrip: true, metered: false), "自己的金鑰或電腦 CLI 不限")
        XCTAssertEqual(aiLeft(t, firstTrip: true, metered: true), 20)
        XCTAssertEqual(aiLeft(t, firstTrip: false, metered: true), 100)
        t.aiUsed = 25
        XCTAssertEqual(aiLeft(t, firstTrip: true, metered: true), 0, "用超過也不會變負的")
        let oldKey: String = CLAUDE_KEY
        let oldEnd: String = AI_ENDPOINT
        let oldBridge: String = BRIDGE_URL
        defer {
            CLAUDE_KEY = oldKey
            AI_ENDPOINT = oldEnd
            BRIDGE_URL = oldBridge
        }
        CLAUDE_KEY = ""
        BRIDGE_URL = ""
        AI_ENDPOINT = "https://example.com/ai"
        XCTAssertTrue(aiMetered())
        BRIDGE_URL = "http://192.168.1.2:8787/ask?t=abc"
        XCTAssertFalse(aiMetered())
    }

    func test電腦CLI的網址要有ask和密碼() {
        XCTAssertTrue(looksLikeBridge("http://192.168.1.23:8787/ask?t=0123abcd"))
        XCTAssertFalse(looksLikeBridge("http://192.168.1.23:8787/ask"))
        XCTAssertFalse(looksLikeBridge("http://192.168.1.23:8787/ping?t=0123"))
        XCTAssertFalse(looksLikeBridge("隨便一串字"))
    }
}
