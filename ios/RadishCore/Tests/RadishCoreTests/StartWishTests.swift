// 開一趟時寫的那句「想怎麼玩」（❓49 B 版）：剛排好那張卡講的是實話、重排和復原之後也是、沒接 AI 時哪些手機做得了。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class StartWishTests: XCTestCase {
    private let said: String = "想去弘大和聖水逛街，晚上吃烤肉"

    private func trip(_ wish: String?) -> Trip {
        let d: TripDraft = TripDraft(
            city: "seoul", base: .C, start: "2027-03-10", days: 5, arrive: .pm, leave: .pm, people: 2)
        var t: Trip = generate(d, defaultSettings())
        t.planTweaks = []
        t.wish = wish
        return t
    }

    private func mine(_ text: String) -> ChatMsg {
        var m: ChatMsg = ChatMsg(r: .me, t: text, day: 1)
        m.wish = true
        return m
    }

    private func card(_ t: Trip, _ chat: [ChatMsg] = [], _ busy: Bool = false) -> PlanCardText {
        return planCardText(t, defaultSettings(), chat, busy)
    }

    /* ---------- 剛排好那張卡 ---------- */

    func test沒寫那句_卡跟以前一樣() {
        let c: PlanCardText = card(trip(nil))
        XCTAssertEqual(c.head, "這一版是 app 內建的排法排的，沒有問 AI")
        XCTAssertNil(c.wish)
        XCTAssertTrue(c.body.contains("你沒講到的"))
    }

    func test還沒送_卡說沒有問AI_那句還沒送() throws {
        let t: Trip = trip(said)
        XCTAssertEqual(wishStatus(t, [], false), WishStatus.held)
        let c: PlanCardText = card(t)
        XCTAssertEqual(c.head, "這一版是 app 內建的排法排的，沒有問 AI")
        let line: String = try XCTUnwrap(c.wish)
        XCTAssertTrue(line.contains("還沒有送給 AI"))
        XCTAssertFalse(c.body.contains("你沒講到的"), "那句沒照做，不能講得像聽進去了")
    }

    func test等回覆_沒收到_都不說改了() throws {
        let t: Trip = trip(said)
        var chat: [ChatMsg] = [mine(said)]
        XCTAssertEqual(wishStatus(t, chat, true), WishStatus.waiting)
        XCTAssertEqual(wishStatus(t, chat, false), WishStatus.noReply, "app 被結束，等不到了")
        chat[0].failed = "HTTP 500"
        XCTAssertEqual(wishStatus(t, chat, true), WishStatus.noReply)
        let c: PlanCardText = card(t, chat)
        XCTAssertFalse(c.head.contains("AI 再照"))
        XCTAssertTrue(try XCTUnwrap(c.wish).contains("沒有收到"))
    }

    func testAI改了_底子寫手機排的_列出改了哪些() throws {
        var t: Trip = trip(said)
        t.wishChanges = ["甲", "乙", "丙", "丁"]
        let chat: [ChatMsg] = [mine(said), ChatMsg(r: .ai, t: "好。", changes: ["甲", "乙", "丙", "丁"])]
        XCTAssertEqual(wishStatus(t, chat, false), WishStatus.changed(local: false))
        let c: PlanCardText = card(t, chat)
        XCTAssertEqual(c.head, "先由手機照你選的排好，AI 再照你寫的那句改過")
        let line: String = try XCTUnwrap(c.wish)
        XCTAssertTrue(line.contains("甲；乙；丙"))
        XCTAssertTrue(line.contains("一共 4 項"))
        XCTAssertFalse(line.contains("丁"))
    }

    func test手機改的不寫成AI改的() throws {
        var t: Trip = trip("第 3 天輕鬆一點")
        t.wishChanges = ["甲"]
        var reply: ChatMsg = ChatMsg(r: .ai, t: "好。", changes: ["甲"])
        reply.local = true
        let c: PlanCardText = card(t, [mine("第 3 天輕鬆一點"), reply])
        XCTAssertTrue(c.head.contains("沒有問 AI"))
        XCTAssertTrue(try XCTUnwrap(c.wish).hasPrefix("手機照你寫的"))
    }

    func testAI回了沒改_要點頭的_按過套用的() {
        let t: Trip = trip(said)
        var reply: ChatMsg = ChatMsg(r: .ai, t: "好。")
        XCTAssertEqual(wishStatus(t, [mine(said), reply], false), WishStatus.answered(local: false))
        XCTAssertFalse(card(t, [mine(said), reply]).head.contains("沒有問 AI"), "問過了就不能說沒問")
        reply.ask = ["這趟加上想輕鬆一點"]
        reply.askOps = "[]"
        XCTAssertEqual(wishStatus(t, [mine(said), reply], false), WishStatus.asking)
        reply.askOps = nil
        reply.asked = true
        XCTAssertEqual(wishStatus(t, [mine(said), reply], false), WishStatus.agreed)
    }

    func test重排_那句留著_改過的不算在新的一版() throws {
        var t: Trip = trip(said)
        t.wishChanges = ["甲"]
        let chat: [ChatMsg] = [mine(said), ChatMsg(r: .ai, t: "好。", changes: ["甲"])]
        let next: Trip = replanTrip(t, draftOf(t), defaultSettings(), true)
        XCTAssertEqual(next.wish, said)
        XCTAssertNil(next.wishChanges)
        XCTAssertEqual(wishStatus(next, chat, false), WishStatus.gone)
        XCTAssertFalse(card(next, chat).head.contains("AI 再照"))
    }

    func test復原那一輪_卡不再說AI改過() {
        var d: AppState = AppState()
        d.trip = trip(said)
        d.chat = [mine(said)]
        syncAIUsed(&d)
        let snap: UndoSnap = undoSnap(d, swap: false)
        d.trip?.wishChanges = ["甲"]
        d.chat.append(ChatMsg(r: .ai, t: "好。", changes: ["甲"]))
        applyUndo(&d, snap)
        XCTAssertEqual(d.trip?.wish, said)
        XCTAssertNil(d.trip?.wishChanges)
        if let t = d.trip {
            XCTAssertEqual(wishStatus(t, d.chat, false), WishStatus.gone)
        }
    }

    /* ---------- 再送那句 ---------- */

    func test認得是不是那句_換行變空白也認得_送成了就不算() {
        let t: Trip = trip("想逛街\n晚上吃烤肉")
        XCTAssertTrue(wishPending(t, [], "想逛街 晚上吃烤肉"))
        XCTAssertEqual(oneLine("想逛街\n\n晚上吃烤肉"), "想逛街 晚上吃烤肉")
        XCTAssertFalse(wishPending(t, [], "想逛街"))
        XCTAssertFalse(wishPending(trip(nil), [], "想逛街"))
        var failed: ChatMsg = mine("想逛街\n晚上吃烤肉")
        failed.failed = ""
        XCTAssertTrue(wishPending(t, [failed], "想逛街 晚上吃烤肉"), "沒收到回覆的可以再送")
        let done: [ChatMsg] = [mine("想逛街\n晚上吃烤肉"), ChatMsg(r: .ai, t: "好。")]
        XCTAssertFalse(wishPending(t, done, "想逛街 晚上吃烤肉"))
        XCTAssertNil(cleanWish(" \n "))
        XCTAssertEqual(cleanWish(" 逛街\n"), "逛街")
    }

    func test寫想要什麼_不會被手機當成在問() {
        var d: AppState = AppState()
        d.trip = trip(nil)
        XCTAssertNil(wishPhone("想在弘大附近逛街", d, nil))
        XCTAssertNil(wishPhone("一天幾站就好", d, nil))
        XCTAssertNotNil(wishPhone("有哪些要先訂？", d, nil))
    }

    func test沒接AI_只有一件事而且聽得懂才給手機做() {
        let t: Trip = trip(nil)
        XCTAssertTrue(wishLocalCan("這趟想輕鬆一點。", t))
        XCTAssertTrue(wishLocalCan("第 3 天輕鬆一點", t))
        XCTAssertFalse(wishLocalCan(said, t))
        XCTAssertFalse(wishLocalCan("這趟想輕鬆一點，多吃烤肉", t), "做了一件，另一件會掉")
        XCTAssertFalse(wishLocalCan("", t))
        XCTAssertEqual(localBrain("想吃烤肉", t).reply, LOCAL_LOST)
    }

    /* ---------- 存檔 ---------- */

    func test存了讀回來_舊檔沒有這幾欄也讀得出來() throws {
        var d: AppState = AppState()
        var t: Trip = trip(said)
        t.wishChanges = ["甲"]
        d.trip = t
        d.chat = [mine(said)]
        let data: Data = try JSONEncoder().encode(d)
        let back: AppState = try XCTUnwrap(AppState.hydrate(data))
        XCTAssertEqual(back.trip?.wish, said)
        XCTAssertEqual(back.trip?.wishChanges, ["甲"])
        XCTAssertEqual(back.chat.first?.wish, true)

        var old: AppState = AppState()
        old.trip = trip(nil)
        old.chat = [ChatMsg(r: .me, t: "嗨")]
        let raw: Data = try JSONEncoder().encode(old)
        let text: String = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(text.contains("wishChanges"))
        let oldBack: AppState = try XCTUnwrap(AppState.hydrate(raw))
        XCTAssertNil(oldBack.trip?.wish)
        XCTAssertNil(oldBack.chat.first?.wish)
    }
}
