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

/// 收進去過的旅行的那一份整趟。去過的站的那一句和照片已經在 items 裡，這裡拿掉，
/// 之後在去過的那一趟改那一句、拿掉照片，才不會還留著一份舊的
private func keptTrip(_ t: Trip) -> Trip {
    var out: Trip = t
    for i in out.slots.indices {
        for j in out.slots[i].items.indices where out.slots[i].items[j].status == .pulled {
            out.slots[i].items[j].say = nil
            out.slots[i].items[j].photos = nil
        }
    }
    return out
}

/// 把這趟收起來。有去過的站：收進「去過的旅行」，花費、匯率、沒去的站、對話一起留著。
/// 一站都沒去過：整趟放到「其他排好的」，什麼都不會不見，只是不再提醒訂位
@discardableResult
func archiveTrip(_ d: inout AppState) -> String? {
    guard let trip = d.trip else { return nil }
    let items: [BasketItem] = visitedOf(trip)
    if items.isEmpty {
        shelveCurrent(&d)
        if !d.shelf.isEmpty {
            d.shelf[0].shut = true
        }
        return "這趟收起來了，放在「旅行」的「其他排好的」。"
    }
    var basket: Basket = Basket(
        id: newId("b"),
        title: "\(tripTitle(trip))・\(fmtDay(trip.start))出發",
        cover: trip.cover,
        items: items,
        start: trip.start,
        days: trip.days
    )
    basket.trip = keptTrip(trip)
    basket.chat = d.chat.isEmpty ? nil : d.chat
    d.baskets.insert(basket, at: 0)
    // 勾選先不動；排下一趟時才清
    clearCurrent(&d, true)
    return "這趟收進「去過的旅行」了，去過的 \(items.count) 站、花費、沒去的站都在裡面。"
}

/// 收進去過的旅行的那一趟裡，當時沒去的站，照行程順序。舊檔沒有留就是空的
func basketLeft(_ b: Basket) -> [Found] {
    guard let trip = b.trip else { return [] }
    return allItems(trip).filter { (x: Found) -> Bool in x.it.status != .pulled }
}

/// 排訂位提醒要看的那一份：按過「不排了，收起來」的那幾趟不提醒
func remindState(_ s: AppState) -> AppState {
    var out: AppState = s
    out.shelf = s.shelf.filter { (x: Shelved) -> Bool in x.shut != true }
    return out
}

/* ---------- 整趟重排 ---------- */

/// 有去過的站：整趟重排會把去過的紀錄洗掉，所以不重排
func tripVisited(_ t: Trip) -> Bool {
    return allItems(t).contains { (x: Found) -> Bool in x.it.status == .pulled }
}

/// 有去過的站、說要整趟重排時回的話（旅途中的那一句在 Chat.swift 的 NO_REGEN_ON_TRIP）
let NO_REGEN_VISITED: String = "這趟已經有去過的站，整趟重排會把去過的紀錄洗掉，所以沒有重排。想改哪一天，直接說哪一段。"

/// 照現在的設定整趟重排。有去過的站就不動，回講清楚的那一句
func replanCurrent(_ d: inout AppState) -> String? {
    guard let old = d.trip else { return nil }
    if tripVisited(old) { return NO_REGEN_VISITED }
    d.trip = replanTrip(old, draftOf(old), d.settings)
    d.settingsDirty = false
    return "照新的設定重排了。手動改過的地方也一起重排了。"
}

/* ---------- 等 AI 回覆的時候換了一趟 ---------- */

/// 對話裡第 me 則是不是我說的那一句
func isSaid(_ chat: [ChatMsg], _ me: Int, _ said: String) -> Bool {
    guard me >= 0 && me < chat.count else { return false }
    return chat[me].r == .me && chat[me].t == said
}

/// 送出那一句的那一趟現在放在一邊：回的話留在它的對話裡，改動不套。回那一趟的名字；找不到就回 nil、什麼都不動
@discardableResult
func leaveReply(
    _ d: inout AppState, _ tripId: String, _ me: Int, _ said: String, _ reply: ChatMsg, _ hadChanges: Bool
) -> String? {
    let found: Int? = d.shelf.firstIndex { (x: Shelved) -> Bool in x.trip.id == tripId }
    guard let i = found, isSaid(d.shelf[i].chat, me, said) else { return nil }
    d.shelf[i].chat.append(reply)
    if hadChanges {
        d.shelf[i].chat.append(ChatMsg(r: .sys, t: "等回覆的時候你換到別趟了，這次的改動沒有套上去。要的話再講一次。"))
    }
    return tripTitle(d.shelf[i].trip)
}

/// 送出那一句的那一趟現在放在一邊：在它的對話裡記下沒收到回覆，切回去可以再送一次
func leaveFail(_ d: inout AppState, _ tripId: String, _ me: Int, _ said: String, _ code: String) {
    let found: Int? = d.shelf.firstIndex { (x: Shelved) -> Bool in x.trip.id == tripId }
    guard let i = found, isSaid(d.shelf[i].chat, me, said) else { return }
    d.shelf[i].chat[me].failed = code
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
/// 給還沒記過 planMark 的行程用：動過的不再跳出剛排好那張卡。
/// 這趟的調整跟排的時候不一樣也算動過：在問 AI 重排完、還沒看這一頁就加了調整，卡上不能寫照它調過
func planUntouched(_ t: Trip) -> Bool {
    if let planned = t.planTweaks, tweakKeys(planned) != tweakKeys(t.tweaks) { return false }
    for x in allItems(t) {
        let it: Stop = x.it
        if it.mine == true || it.ai == true || it.swaps > 0 || it.status == .pulled { return false }
    }
    return true
}

/// 排序過再比：順序不同不算不一樣
private func tweakKeys(_ list: [Tweak]?) -> [String] {
    let keys: [String] = (list ?? []).map { (k: Tweak) -> String in k.rawValue }
    return keys.sorted()
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

/// 剛排好那張卡的「不要這一版」：這一版拿掉，回到開一趟。復原拿得回行程和對話
@discardableResult
func dropPlan(_ d: inout AppState) -> String? {
    guard d.trip != nil else { return nil }
    clearCurrent(&d, true)
    return "這一版拿掉了，可以重新開一趟。"
}

/* ---------- 復原 ---------- */

/// 改之前的樣子，復原用。只放在記憶體。
/// 只改這趟的那一步：還原行程、下次再來、順路、去過的旅行、學到的；對話、打勾不動。
/// 換掉現在這趟的那一步（切到別趟、開新的一趟、收起來、不要這一版）：連其他排好的、對話、要先訂的打勾一起還原
struct UndoSnap: Sendable {
    var trip: Trip?
    var seeds: [Seed]
    var pool: [String]
    var baskets: [Basket]
    var settingsDirty: Bool
    /// 設定裡「從行程學到的」：拿掉一站順便記的，要能跟著那一步一起復原
    var learned: [Learned]
    var shelf: [Shelved]
    var chat: [ChatMsg]
    var checks: [String: Bool]
    var debugDay: Int?
    /// 這一步換掉了現在這趟
    var swap: Bool
    /// 這一步的記號（跟 AI 講的那一輪才有），對話裡用它認「還是不是最後一步」
    var mark: String?
}

/// 這一步有沒有換掉現在這趟，或動到其他排好的。兩份都要先補好代號（syncAIUsed）
func tripSwapped(_ before: AppState, _ after: AppState) -> Bool {
    if before.trip?.id != after.trip?.id { return true }
    let a: [String] = before.shelf.map { (x: Shelved) -> String in x.id }
    let b: [String] = after.shelf.map { (x: Shelved) -> String in x.id }
    return a != b
}

func undoSnap(_ prev: AppState, swap: Bool, mark: String? = nil) -> UndoSnap {
    return UndoSnap(
        trip: prev.trip, seeds: prev.seeds, pool: prev.pool, baskets: prev.baskets,
        settingsDirty: prev.settingsDirty, learned: prev.settings.learned,
        shelf: prev.shelf, chat: prev.chat, checks: prev.checks, debugDay: prev.debugDay,
        swap: swap, mark: mark)
}

/// 退回那一步之前。句數不跟著退（Chat.swift 的 restoreTrip、syncAIUsed）。回提示條要講的那一句
@discardableResult
func applyUndo(_ d: inout AppState, _ snap: UndoSnap) -> String {
    // 那一步之後才改的「平常的我」還沒套到這趟，這件事不能跟著退掉
    let dirty: Bool = snap.settingsDirty || d.settingsDirty
    let open: String? = d.trip?.id
    var text: String = "復原了上一步。"
    // 照順序退，只改這趟的那一步退的時候一定還是那一趟；萬一不是，也照換了一趟的做法，不把現在這趟蓋掉
    if snap.swap || snap.trip?.id != d.trip?.id {
        unswap(&d, snap)
        // 剛剛開著的那趟，換趟之前還沒有：放到其他排好的了
        let known: Bool = open == snap.trip?.id || snap.shelf.contains { (x: Shelved) -> Bool in x.trip.id == open }
        if open != nil && !known {
            text = "復原了上一步。剛剛那一趟放在「其他排好的」，沒有不見。"
        }
    } else {
        restoreTrip(&d, snap.trip)
    }
    d.seeds = snap.seeds
    d.pool = snap.pool
    d.baskets = snap.baskets
    d.settings.learned = snap.learned
    d.settingsDirty = dirty && d.trip != nil
    return text
}

/// 從 list 拿出代號一樣的那一趟
private func takeTrip(_ list: inout [Shelved], _ id: String?) -> Shelved? {
    guard let id = id else { return nil }
    let found: Int? = list.firstIndex { (x: Shelved) -> Bool in x.trip.id == id }
    guard let i = found else { return nil }
    return list.remove(at: i)
}

/// 退回換趟之前。換過去之後講的話、打的勾（都不算一步）留著；換趟之後才有的那一趟放到其他排好的
private func unswap(_ d: inout AppState, _ snap: UndoSnap) {
    syncAIUsed(&d)
    // 現在手上的每一趟，開著的排最前面
    var now: [Shelved] = []
    if let t = d.trip {
        now.append(
            Shelved(id: newId("t"), trip: t, chat: d.chat, checks: bookingChecks(d.checks), debugDay: d.debugDay))
    }
    now.append(contentsOf: d.shelf)

    var chat: [ChatMsg] = snap.chat
    var books: [String: Bool] = bookingChecks(snap.checks)
    var debugDay: Int? = snap.debugDay
    if let x = takeTrip(&now, snap.trip?.id) {
        chat = x.chat
        books = x.checks
        debugDay = x.debugDay
    }
    var shelf: [Shelved] = []
    for old in snap.shelf {
        var kept: Shelved = old
        if let x = takeTrip(&now, old.trip.id) {
            kept.trip = x.trip
            kept.chat = x.chat
            kept.checks = x.checks
            kept.debugDay = x.debugDay
        }
        shelf.append(kept)
    }
    var checks: [String: Bool] = otherChecks(d.checks)
    for (k, v) in books { checks[k] = v }
    d.trip = snap.trip
    d.shelf = now + shelf
    d.chat = chat
    d.checks = checks
    d.debugDay = debugDay
    syncAIUsed(&d)
}

func shareText(_ trip: Trip) -> String {
    let start: String = trip.start
    let end: String = addDays(start, trip.days - 1)
    let body: String = planText(trip, false, { (d: Int) -> String in fmtDay(addDays(start, d - 1)) })
    return "首爾 \(trip.days) 天　\(fmtDay(start))–\(fmtDay(end))\n\n\(body)\n（蘿蔔旅行排的。地點還沒核對過，看完跟我說哪天想改。）"
}
