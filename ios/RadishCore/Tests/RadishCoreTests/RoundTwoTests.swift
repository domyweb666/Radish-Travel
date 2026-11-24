// 第二輪 code review 找到的：「想怎麼玩」那句拿掉、改過再講、再講一次；沒人回的句子補上再送一次；那句什麼時候給手機答。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class RoundTwoTests: XCTestCase {
    private let said: String = "想去弘大和聖水逛街，晚上吃烤肉"

    private func trip(_ wish: String?, _ id: String = "k1") -> Trip {
        let d: TripDraft = TripDraft(
            city: "seoul", base: .C, start: "2027-03-10", days: 5, arrive: .pm, leave: .pm, people: 2)
        var t: Trip = generate(d, defaultSettings())
        t.planTweaks = []
        t.id = id
        t.wish = wish
        return t
    }

    private func mine(_ text: String) -> ChatMsg {
        var m: ChatMsg = ChatMsg(r: .me, t: text, day: 1)
        m.wish = true
        return m
    }

    private func shelved(_ t: Trip, _ chat: [ChatMsg]) -> Shelved {
        return Shelved(id: newId("t"), trip: t, chat: chat)
    }

    /* ---------- 1 拿掉、改過再講 ---------- */

    func test從那句清空_算拿掉_卡說實話_不再是還沒送() throws {
        var t: Trip = trip(said)
        let step: WishTyped = wishTyped(t, [], said, "", nil)
        XCTAssertEqual(step, WishTyped(line: nil, off: .removed))
        t.wishOff = step.off
        XCTAssertEqual(wishStatus(t, [], false), WishStatus.removed)
        let c: PlanCardText = planCardText(t, defaultSettings(), [], false)
        let line: String = try XCTUnwrap(c.wish)
        XCTAssertTrue(line.contains("拿掉"))
        XCTAssertFalse(line.contains("隨時可以送"))
        XCTAssertTrue(c.head.contains("沒有問 AI"))
    }

    func test一個字一個字刪到空_也算拿掉() {
        let t: Trip = trip("想逛街")
        var step: WishTyped = wishTyped(t, [], "想逛街", "想逛", nil)
        XCTAssertEqual(step, WishTyped(line: "想逛", off: nil), "還沒刪完不算")
        step = wishTyped(t, [], "想逛", "想", step.line)
        XCTAssertEqual(step.line, "想")
        step = wishTyped(t, [], "想", "", step.line)
        XCTAssertEqual(step, WishTyped(line: nil, off: .removed))
    }

    func test打別的字再清掉_不算拿掉() {
        let t: Trip = trip(said)
        let a: WishTyped = wishTyped(t, [], "", "這天太滿", nil)
        XCTAssertEqual(a, WishTyped(line: nil, off: nil))
        let b: WishTyped = wishTyped(t, [], "這天太滿", "", a.line)
        XCTAssertEqual(b, WishTyped(line: nil, off: nil))
        XCTAssertEqual(wishTyped(trip(nil), [], "嗨", "", nil).off, nil, "沒寫那句")
        XCTAssertNil(wishTyped(t, [mine(said)], said, "", nil).off, "送過了就不用記")
    }

    func test打回一樣的字_又算還沒送() {
        var t: Trip = trip(said)
        t.wishOff = .removed
        XCTAssertNil(wishTyped(t, [], "", said, nil).off)
        XCTAssertTrue(wishPending(t, [], said), "拿掉之後再講一樣的，一樣講整趟")
    }

    func test改過再講_卡說改過_不說還沒送() throws {
        var t: Trip = trip(said)
        let next: String = "想去弘大逛街"
        let step: WishTyped = wishTyped(t, [], said, next, nil)
        XCTAssertEqual(step, WishTyped(line: next, off: nil))
        XCTAssertTrue(wishFromLine(step.line, "想去弘大逛街 "))
        XCTAssertFalse(wishFromLine(step.line, "這天太滿"))
        XCTAssertFalse(wishFromLine(nil, ""))
        t.wishOff = .edited
        let chat: [ChatMsg] = [ChatMsg(r: .me, t: next, day: 1), ChatMsg(r: .ai, t: "好。")]
        XCTAssertEqual(wishStatus(t, chat, false), WishStatus.edited)
        let c: PlanCardText = planCardText(t, defaultSettings(), chat, false)
        XCTAssertTrue(try XCTUnwrap(c.wish).contains("改過字才講"))
        XCTAssertFalse(c.head.contains("沒有問 AI"), "改過的那句問過了")
        XCTAssertEqual(wishTyped(t, chat, said, "", nil).off, .edited, "講過了就一直是改過再講")
    }

    func test拿掉之後復原別的_重排_存檔_都記得() throws {
        var d: AppState = AppState()
        d.trip = trip(said)
        syncAIUsed(&d)
        let snap: UndoSnap = undoSnap(d, swap: false)
        d.trip?.stayName = "民宿"
        setWishOff(&d, .removed)
        applyUndo(&d, snap)
        XCTAssertNil(d.trip?.stayName)
        XCTAssertEqual(d.trip?.wishOff, .removed)
        let t: Trip = try XCTUnwrap(d.trip)
        XCTAssertEqual(replanTrip(t, draftOf(t), defaultSettings(), true).wishOff, .removed)
        let back: AppState = try XCTUnwrap(AppState.hydrate(try JSONEncoder().encode(d)))
        XCTAssertEqual(back.trip?.wishOff, .removed)
    }

    func test換趟再復原_每一趟記各自的() throws {
        var d: AppState = AppState()
        d.trip = trip(said, "a")
        d.shelf = [shelved(trip(said, "b"), [])]
        syncAIUsed(&d)
        let snap: UndoSnap = undoSnap(d, swap: true)
        let id: String = try XCTUnwrap(d.shelf.first?.id)
        openShelved(&d, id)
        setWishOff(&d, .removed)
        applyUndo(&d, snap)
        XCTAssertEqual(d.trip?.id, "a")
        XCTAssertNil(d.trip?.wishOff)
        XCTAssertEqual(d.shelf.first?.trip.wishOff, .removed)
    }

    func test舊檔沒有這一欄_讀得出來() throws {
        var d: AppState = AppState()
        d.trip = trip(said)
        let raw: Data = try JSONEncoder().encode(d)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("wishOff"))
        let back: AppState = try XCTUnwrap(AppState.hydrate(raw))
        XCTAssertNil(back.trip?.wishOff)
    }

    /* ---------- 2 沒人回的句子 ---------- */

    func test最後一則是我說的_補成沒收到_有錯誤代碼的不蓋掉() {
        var chat: [ChatMsg] = [ChatMsg(r: .me, t: "甲"), ChatMsg(r: .ai, t: "好。"), ChatMsg(r: .me, t: "乙")]
        XCTAssertTrue(markUnanswered(chat: &chat))
        XCTAssertEqual(chat[2].failed, "")
        XCTAssertNil(chat[0].failed)
        XCTAssertFalse(markUnanswered(chat: &chat), "補過就不用再補")
        chat[2].failed = "HTTP 500"
        XCTAssertFalse(markUnanswered(chat: &chat))
        XCTAssertEqual(chat[2].failed, "HTTP 500")
    }

    func test有人回的_空的_不動() {
        var answered: [ChatMsg] = [ChatMsg(r: .me, t: "甲"), ChatMsg(r: .ai, t: "好。")]
        XCTAssertFalse(markUnanswered(chat: &answered))
        XCTAssertNil(answered[0].failed)
        var empty: [ChatMsg] = []
        XCTAssertFalse(markUnanswered(chat: &empty))
    }

    func test其他排好的也補() {
        var d: AppState = AppState()
        d.trip = trip(nil, "a")
        d.shelf = [shelved(trip(nil, "b"), [ChatMsg(r: .me, t: "乙")])]
        XCTAssertTrue(markUnanswered(&d))
        XCTAssertEqual(d.shelf[0].chat[0].failed, "")
        XCTAssertFalse(markUnanswered(&d))
    }

    func test等回覆時不要這一版_復原回來_那句補得到() {
        var d: AppState = AppState()
        d.trip = trip(said)
        d.chat = [mine(said)]
        syncAIUsed(&d)
        let snap: UndoSnap = undoSnap(d, swap: true)
        dropPlan(&d)
        XCTAssertNil(leaveReply(&d, "k1", 0, said, ChatMsg(r: .ai, t: "好。"), true), "回來的時候這趟不在手上")
        applyUndo(&d, snap)
        XCTAssertTrue(markUnanswered(&d))
        XCTAssertEqual(d.chat.first?.failed, "")
    }

    /* ---------- 4 那句什麼時候給手機答 ---------- */

    func test講好幾件_有想_就算是問句也不給手機答() {
        var d: AppState = AppState()
        d.trip = trip(nil)
        XCTAssertNil(wishPhone("想住弘大附近多逛街，晚上可以吃烤肉嗎", d, nil))
        XCTAssertNil(wishPhone("住弘大附近，晚上可以吃烤肉嗎？", d, nil))
        XCTAssertNil(wishPhone("想問附近有什麼嗎", d, nil))
        XCTAssertNil(wishPhone("有哪些要先訂？附近可以吃烤肉嗎？", d, nil))
        XCTAssertNotNil(wishPhone("有哪些要先訂？", d, nil))
        XCTAssertNotNil(wishPhone("有哪些要先訂", d, nil))
    }

    /* ---------- 6 再講一次 ---------- */

    func test改完又復原_再講一次還是講整趟() {
        let t: Trip = trip(said)
        let chat: [ChatMsg] = [mine(said), ChatMsg(r: .ai, t: "好。", changes: ["甲"])]
        XCTAssertEqual(wishStatus(t, chat, false), WishStatus.gone)
        XCTAssertTrue(wishPending(t, chat, said))
        var still: Trip = t
        still.wishChanges = ["甲"]
        XCTAssertFalse(wishPending(still, chat, said), "還照它改著，就是新的一句")
    }

    func test換趟沒套上_再講一次還是講整趟() throws {
        var d: AppState = AppState()
        d.trip = trip(nil, "a")
        d.shelf = [shelved(trip(said, "b"), [mine(said)])]
        XCTAssertNotNil(leaveReply(&d, "b", 0, said, ChatMsg(r: .ai, t: "好。"), true))
        let b: Shelved = try XCTUnwrap(d.shelf.first)
        XCTAssertTrue(wishPending(b.trip, b.chat, said))
        XCTAssertFalse(wishPending(b.trip, [mine(said), ChatMsg(r: .ai, t: "好。")], said), "只是回答，沒有要改的")
    }

    func test套用過又復原這次_再講一次還是講整趟() {
        let t: Trip = trip(said)
        var reply: ChatMsg = ChatMsg(r: .ai, t: "好。")
        reply.asked = true
        XCTAssertFalse(wishPending(t, [mine(said), reply], said))
        reply.undone = true
        XCTAssertTrue(wishPending(t, [mine(said), reply], said))
    }
}
