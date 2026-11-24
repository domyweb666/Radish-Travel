// 問 AI 的句數：復原、重排、放一邊、收掉再復原都不退，每一趟各算各的。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class AIQuotaTests: XCTestCase {
    private func plan(_ start: String, _ days: Int) -> Trip {
        let d: TripDraft = TripDraft(city: "seoul", start: start, days: days, arrive: .pm, leave: .pm, people: 2)
        return generate(d, defaultSettings())
    }

    /// 開著一趟，代號補好了
    private func state() -> AppState {
        var d: AppState = AppState()
        d.trip = plan("2026-12-04", 5)
        syncAIUsed(&d)
        return d
    }

    private func ask(_ d: inout AppState, _ times: Int) throws {
        let id: String = try XCTUnwrap(d.trip?.id)
        for _ in 0..<times {
            countAI(&d, id)
        }
    }

    func test代號_剛開的一趟會補上_再對一次不會換() throws {
        var d: AppState = state()
        let id: String = try XCTUnwrap(d.trip?.id)
        syncAIUsed(&d)
        XCTAssertEqual(d.trip?.id, id)
        let t: Trip = try XCTUnwrap(d.trip)
        XCTAssertNil(t.aiUsed, "還沒問過")
        XCTAssertEqual(aiLeft(t, firstTrip: true, metered: true), 20)
    }

    func test復原_行程退回去_句數不退() throws {
        var d: AppState = state()
        let before: Trip = try XCTUnwrap(d.trip)
        var moved: Trip = before
        for i in moved.slots.indices {
            moved.slots[i].items = []
        }
        d.trip = moved
        try ask(&d, 3)
        XCTAssertEqual(d.trip?.aiUsed, 3)
        XCTAssertNotEqual(d.trip?.slots, before.slots)
        restoreTrip(&d, before)
        XCTAssertEqual(d.trip?.slots, before.slots, "行程是退回去的那一份")
        XCTAssertEqual(d.trip?.aiUsed, 3)
    }

    func test整趟重排_照新設定重排_改行程設定重排_句數和代號不變() throws {
        var d: AppState = state()
        try ask(&d, 4)
        let old: Trip = try XCTUnwrap(d.trip)
        let shuffled: Trip = replanTrip(old, draftOf(old), d.settings, true)
        XCTAssertEqual(shuffled.aiUsed, 4)
        XCTAssertEqual(shuffled.id, old.id)

        var st: Settings = d.settings
        st.pace = .slow
        let tuned: Trip = replanTrip(old, draftOf(old), st)
        XCTAssertEqual(tuned.aiUsed, 4)
        XCTAssertEqual(tuned.id, old.id)

        var draft: TripDraft = draftOf(old)
        draft.start = "2027-01-10"
        draft.days = 3
        let changed: Trip = replanTrip(old, draft, d.settings)
        XCTAssertEqual(changed.days, 3)
        XCTAssertEqual(changed.aiUsed, 4, "換日期、換天數還是同一趟")
        XCTAssertEqual(changed.id, old.id)

        // 重排之後再問一句，復原到重排之前：五句都在
        d.trip = changed
        try ask(&d, 1)
        restoreTrip(&d, old)
        XCTAssertEqual(d.trip?.days, 5)
        XCTAssertEqual(d.trip?.aiUsed, 5)
    }

    func test重排_機票_花費_匯率都帶著() {
        var t: Trip = plan("2026-12-04", 5)
        t.flight = 12000
        t.rate = 23
        addSpend(&t, 5000, "A")
        let again: Trip = replanTrip(t, draftOf(t), defaultSettings())
        XCTAssertEqual(again.flight, 12000)
        XCTAssertEqual(again.rate, 23)
        XCTAssertEqual(again.spend?.count, 1)
    }

    func test開新的一趟_從0算_復原回到前一趟_各算各的() throws {
        var d: AppState = state()
        let first: Trip = try XCTUnwrap(d.trip)
        try ask(&d, 6)
        shelveCurrent(&d)
        d.trip = plan("2027-03-10", 3)
        syncAIUsed(&d)
        let second: Trip = try XCTUnwrap(d.trip)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertNil(second.aiUsed, "前一趟的句數不帶過來")
        try ask(&d, 2)
        XCTAssertEqual(d.trip?.aiUsed, 2)
        XCTAssertEqual(d.shelf.first?.trip.aiUsed, 6, "放一邊的那趟沒有被加到")

        // 換回前一趟還沒問過的那一份：是前一趟的 6 句，不是 0 也不是 2
        restoreTrip(&d, first)
        XCTAssertEqual(d.trip?.aiUsed, 6)
        restoreTrip(&d, second)
        XCTAssertEqual(d.trip?.aiUsed, 2)
    }

    func test放一邊再切回來_句數還在() throws {
        var d: AppState = state()
        try ask(&d, 3)
        shelveCurrent(&d)
        d.trip = plan("2027-03-10", 3)
        syncAIUsed(&d)
        let shelfId: String = try XCTUnwrap(d.shelf.first?.id)
        openShelved(&d, shelfId)
        syncAIUsed(&d)
        XCTAssertEqual(d.trip?.aiUsed, 3)
        let other: Trip = try XCTUnwrap(d.shelf.first?.trip)
        XCTAssertNil(other.aiUsed)
    }

    func test收掉再復原_不要這一版再復原_不退句數() throws {
        var d: AppState = state()
        let fresh: Trip = try XCTUnwrap(d.trip)
        try ask(&d, 7)
        let full: Trip = try XCTUnwrap(d.trip)
        archiveTrip(&d)
        XCTAssertNil(d.trip)
        restoreTrip(&d, full)
        XCTAssertEqual(d.trip?.aiUsed, 7)
        dropPlan(&d)
        XCTAssertNil(d.trip)
        restoreTrip(&d, fresh)
        XCTAssertEqual(d.trip?.aiUsed, 7, "拿回來的是問之前的那一份，句數還是七句")
    }

    func test等回覆的時候收掉了_那一句算在原本那趟() throws {
        var d: AppState = state()
        try ask(&d, 1)
        let first: Trip = try XCTUnwrap(d.trip)
        let firstId: String = try XCTUnwrap(first.id)
        archiveTrip(&d)
        d.trip = plan("2027-03-10", 3)
        syncAIUsed(&d)
        countAI(&d, firstId)
        let second: Trip = try XCTUnwrap(d.trip)
        XCTAssertNil(second.aiUsed, "不會算到新的這趟")
        restoreTrip(&d, first)
        XCTAssertEqual(d.trip?.aiUsed, 2)
    }

    func test貼上自己的舊備份_同一趟取多的_全部清掉就真的清掉() throws {
        var d: AppState = state()
        try ask(&d, 2)
        var backup: AppState = d
        try ask(&d, 3)
        carryAILog(&backup, d)
        XCTAssertEqual(backup.trip?.aiUsed, 5)
        var empty: AppState = AppState()
        carryAILog(&empty, d)
        XCTAssertEqual(empty, AppState())
    }

    func test存檔_句數和代號讀得回來_舊檔沒有代號也讀得出來() throws {
        var d: AppState = state()
        try ask(&d, 2)
        let data: Data = try JSONEncoder().encode(d)
        let back: AppState = try XCTUnwrap(AppState.hydrate(data))
        XCTAssertEqual(back.trip?.id, d.trip?.id)
        XCTAssertEqual(back.trip?.aiUsed, 2)
        XCTAssertEqual(back.aiLog, d.aiLog)

        // 0.3.0 的存檔：有 aiUsed，沒有代號和 aiLog
        var old: AppState = d
        var bare: Trip = try XCTUnwrap(old.trip)
        bare.id = nil
        old.trip = bare
        let encoded: Data = try JSONEncoder().encode(old)
        let parsed: Any = try JSONSerialization.jsonObject(with: encoded, options: [])
        var json: [String: Any] = try XCTUnwrap(parsed as? [String: Any])
        json.removeValue(forKey: "aiLog")
        let oldData: Data = try JSONSerialization.data(withJSONObject: json, options: [])
        var loaded: AppState = try XCTUnwrap(AppState.hydrate(oldData))
        let before: Trip = try XCTUnwrap(loaded.trip)
        XCTAssertNil(before.id)
        XCTAssertEqual(loaded.aiLog, [:])
        syncAIUsed(&loaded)
        let after: Trip = try XCTUnwrap(loaded.trip)
        XCTAssertNotNil(after.id)
        XCTAssertEqual(after.aiUsed, 2)
    }
}
