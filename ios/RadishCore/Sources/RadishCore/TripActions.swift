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
    // 收起來、不要這一版之後，要先訂的打勾還留著（給復原用）。那是上一趟的，不能併進這一趟
    let rest: [String: Bool] = otherChecks(d.checks)
    d.checks = rest
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

/* ---------- 剛排好那張卡（S01 第一次，線框 A4） ---------- */

/// 這一版是誰排的。畫面上兩種講法不能一樣（.uiux/02-流程-暫定.md 9-6 第 7 條）
enum PlanBy: String, Codable, Sendable {
    /// AI 照他講的排的
    case ai
    /// app 內建的排法排的，沒有問 AI
    case app
}

/// 這一版的樣子，變成一小段字。站換了、移了、拔了、日期或住哪改了、這趟的調整改了，算出來就不一樣。
/// 調整要算：排好之後才說「想輕鬆一點」沒有重排，剛排好那張卡不能寫成照它調過。
/// 沒有調整時算法跟以前一樣，舊存檔記的還對得上
func planMarkOf(_ t: Trip) -> String {
    var text: String = "\(t.start)|\(t.days)|\(t.base?.rawValue ?? "")"
    for s in t.slots {
        text += "|\(s.day)\(s.part.rawValue)\(s.rest ? "r" : "")\(s.off == true ? "o" : "")"
        for it in s.items {
            text += "," + it.id + (it.status == .pulled ? "p" : "")
        }
    }
    let tweaks: [String] = (t.tweaks ?? []).map { (k: Tweak) -> String in k.rawValue }
    if !tweaks.isEmpty {
        // 排序過再接：順序不同不算改過
        let sorted: [String] = tweaks.sorted()
        text += "|tw:" + sorted.joined(separator: ",")
    }
    // djb2：每次開 app 都要算出一樣的字，不能用 Swift 的 hashValue（每次開都不一樣）
    var h: UInt64 = 5381
    for u in text.unicodeScalars {
        h = (h &* 33) &+ UInt64(u.value)
    }
    return String(h, radix: 36)
}

/// 看起來還沒動過：沒有自己加的、AI 加的、換過的、拔起來的站。
/// 給還沒記過 planMark 的舊行程用：動過的舊行程不再跳出剛排好那張卡
func planUntouched(_ t: Trip) -> Bool {
    for x in allItems(t) {
        let it: Stop = x.it
        if it.mine == true || it.ai == true || it.swaps > 0 || it.status == .pulled { return false }
    }
    return true
}

/// YYYY-MM-DD 變成 11/22。看不懂就回 nil
private func planMonthDay(_ iso: String) -> String? {
    let parts: [Substring] = iso.split(separator: "-")
    guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    return "\(m)/\(d)"
}

/// 剛排好那張卡的兩行字：上面一行是誰排的，下面一段是照你說的排了哪些
struct PlanCardText: Hashable, Sendable {
    let head: String
    let body: String
}

/// 喜歡的那幾類各排了幾個。沒說喜歡什麼就是空字串
private func planCatLine(_ t: Trip, _ st: Settings) -> String {
    let liked: [Cat] = Cat.allCases.filter { (c: Cat) -> Bool in (st.play[c] ?? 0) > 0 }
    if liked.isEmpty { return "" }
    let all: [Found] = allItems(t)
    var counts: [(c: Cat, n: Int)] = []
    for c in liked {
        let n: Int = all.filter { (x: Found) -> Bool in x.it.c == c }.count
        counts.append((c: c, n: n))
    }
    let first: Int = counts[0].n
    let same: Bool = counts.allSatisfy { (x: (c: Cat, n: Int)) -> Bool in x.n == first }
    if same && first > 0 && counts.count > 1 {
        let names: [String] = counts.map { (x: (c: Cat, n: Int)) -> String in CAT[need: x.c] }
        return names.joined(separator: "、") + "各排了 \(first) 個"
    }
    let bits: [String] = counts.map { (x: (c: Cat, n: Int)) -> String in
        return x.n > 0 ? "\(CAT[need: x.c])排了 \(x.n) 個" : "\(CAT[need: x.c])這次沒排到"
    }
    return bits.joined(separator: "，")
}

/// 剛排好那張卡要寫的字。平常的我有設過，沒講到的寫「先照平常的我排」；沒設過才寫「先照一般的排法」
/// （.uiux/03-線框/方向說明-暫定.md：A4 跟 A1 的平常的我要對得起來）
func planCardText(_ t: Trip, _ st: Settings) -> PlanCardText {
    var head: String = "這一版是 app 內建的排法排的，沒有問 AI"
    if t.planBy == .ai {
        head = "AI 照你說的排的"
        if let at = t.planAt, let md = planMonthDay(at) {
            head += "・" + md
        }
    }
    var bits: [String] = []
    bits.append("住\(HOTEL[need: baseOf(t, st)].n)一帶")
    let cats: String = planCatLine(t, st)
    if !cats.isEmpty { bits.append(cats) }
    var most: Int = 0
    if t.days >= 1 {
        for d in 1...t.days {
            most = max(most, bigCount(t, d))
        }
    }
    if most > 0 { bits.append("一天最多 \(most) 個主要景點") }
    let tweaks: String = tweakSummary(t)
    if !tweaks.isEmpty { bits.append("這趟照你選的「\(tweaks)」調過") }
    let rest: String = st.tuned ? "你沒講到的，先照平常的我排。" : "你沒講到的，先照一般的排法。"
    return PlanCardText(head: head, body: bits.joined(separator: "；") + "。" + rest)
}

/// 剛排好那張卡的「不要這一版」：這一版拿掉，回到開一趟。可以復原。
/// 跟收起來一樣，對話會清掉，復原只拿回行程
@discardableResult
func dropPlan(_ d: inout AppState) -> String? {
    guard d.trip != nil else { return nil }
    clearCurrent(&d, true)
    return "這一版拿掉了，可以重新開一趟。"
}

func shareText(_ trip: Trip) -> String {
    let start: String = trip.start
    let end: String = addDays(start, trip.days - 1)
    let body: String = planText(trip, false, { (d: Int) -> String in fmtDay(addDays(start, d - 1)) })
    return "首爾 \(trip.days) 天　\(fmtDay(start))–\(fmtDay(end))\n\n\(body)\n（蘿蔔旅行排的。地點還沒核對過，看完跟我說哪天想改。）"
}
