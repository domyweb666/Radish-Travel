// 對整趟做的事：收起來、先放一邊去排另一趟、切回來、變成一段可以傳給旅伴的文字。
// 都是直接改傳進來那份狀態的純函式，由 store 呼叫。照 mobile/src/domain/tripActions.ts 搬。
import Foundation

func tripTitle(_ t: Trip) -> String {
    let name: String = (t.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "首爾 \(t.days) 天" : name
}

/// 這趟去過的站，照行程順序。收起來和做地圖網頁都用這一份
func visitedOf(_ t: Trip) -> [BasketItem] {
    var out: [BasketItem] = []
    for x in allItems(t) {
        let it: Stop = x.it
        if it.status != .pulled { continue }
        out.append(
            BasketItem(
                id: it.id,
                n: it.n,
                s: it.s,
                c: it.c,
                ic: it.ic,
                say: it.say,
                kr: it.kr.isEmpty ? nil : it.kr,
                lat: it.lat,
                lng: it.lng,
                day: x.s.day,
                photos: it.photos
            ))
    }
    return out
}

private func bookingChecks(_ checks: [String: Bool]) -> [String: Bool] {
    var out: [String: Bool] = [:]
    for (k, v) in checks where k.hasPrefix("b_") { out[k] = v }
    return out
}

private func otherChecks(_ checks: [String: Bool]) -> [String: Bool] {
    var out: [String: Bool] = [:]
    for (k, v) in checks where !k.hasPrefix("b_") { out[k] = v }
    return out
}

private func clearCurrent(_ d: inout AppState, _ keepChecks: Bool = false) {
    d.trip = nil
    d.chat = []
    d.debugDay = nil
    d.settingsDirty = false
    if !keepChecks {
        let rest: [String: Bool] = otherChecks(d.checks)
        d.checks = rest
    }
}

/// 把這趟收起來：去過的站收進「去過的旅行」，行程清空
@discardableResult
func archiveTrip(_ d: inout AppState) -> String? {
    guard let trip = d.trip else { return nil }
    let items: [BasketItem] = visitedOf(trip)
    if !items.isEmpty {
        let basket: Basket = Basket(
            id: newId("b"),
            title: "\(tripTitle(trip))・\(fmtDay(trip.start))出發",
            cover: trip.cover,
            items: items,
            start: trip.start,
            days: trip.days
        )
        d.baskets.insert(basket, at: 0)
    }
    // 收起來可以復原，所以勾選先不動；排下一趟時才清
    clearCurrent(&d, true)
    return items.isEmpty ? "這趟收起來了。" : "這趟去過的 \(items.count) 站收進「去過的旅行」了。"
}

/// 現在這趟先放到「其他排好的」，讓出位置排新的一趟。什麼都不會不見
func shelveCurrent(_ d: inout AppState) {
    guard let trip = d.trip else { return }
    let kept: Shelved = Shelved(
        id: newId("t"),
        trip: trip,
        chat: d.chat,
        checks: bookingChecks(d.checks),
        debugDay: d.debugDay
    )
    d.shelf.insert(kept, at: 0)
    clearCurrent(&d)
}

/// 切到另一趟：現在這趟先放一邊，再把那一趟拿出來
@discardableResult
func openShelved(_ d: inout AppState, _ id: String) -> String? {
    let found: Int? = d.shelf.firstIndex { (x: Shelved) -> Bool in x.id == id }
    guard let i = found else { return nil }
    let x: Shelved = d.shelf.remove(at: i)
    shelveCurrent(&d)
    d.trip = x.trip
    d.chat = x.chat
    d.debugDay = x.debugDay
    var merged: [String: Bool] = d.checks
    for (k, v) in x.checks { merged[k] = v }
    d.checks = merged
    return "切到「\(tripTitle(x.trip))・\(fmtDay(x.trip.start))出發」了。"
}

/// 已經收起來的旅行裡的某一站。補一句、加照片時用。
/// 注意：Swift 拿到的是複製的一份，改了不會寫回去；要改請用 updateBasketItem
func basketItem(_ d: AppState, _ basketId: String, _ index: Int) -> BasketItem? {
    let found: Basket? = d.baskets.first { (b: Basket) -> Bool in b.id == basketId }
    guard let basket = found else { return nil }
    guard index >= 0 && index < basket.items.count else { return nil }
    return basket.items[index]
}

/// TS 是拿到 basketItem 回的那一站直接改。Swift 的 struct 是複製，所以多這一個：
/// 找到那一站、交給 change 改、寫回去，回改完的樣子。找不到就回 nil、什麼都不動
@discardableResult
func updateBasketItem(_ d: inout AppState, _ basketId: String, _ index: Int, _ change: (inout BasketItem) -> Void) -> BasketItem? {
    let found: Int? = d.baskets.firstIndex { (b: Basket) -> Bool in b.id == basketId }
    guard let bi = found else { return nil }
    guard index >= 0 && index < d.baskets[bi].items.count else { return nil }
    var item: BasketItem = d.baskets[bi].items[index]
    change(&item)
    d.baskets[bi].items[index] = item
    return item
}

func shareText(_ trip: Trip) -> String {
    let start: String = trip.start
    let end: String = addDays(start, trip.days - 1)
    let body: String = planText(trip, false, { (d: Int) -> String in fmtDay(addDays(start, d - 1)) })
    return "首爾 \(trip.days) 天　\(fmtDay(start))–\(fmtDay(end))\n\n\(body)\n（蘿蔔旅行排的。地點還沒核對過，看完跟我說哪天想改。）"
}
