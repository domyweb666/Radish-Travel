// 實際花費：使用者一筆一筆記韓元，用自己填的匯率換成台幣。這裡只算，不碰畫面。
// 匯率是「1000 韓元換多少台幣」，app 不抓即時匯率，沒填就只顯示韓元。
// 照 mobile/src/domain/spend.ts 搬。
import Foundation

private let KRW_MAX: Double = 99_999_999
private let RATE_MAX: Double = 100
/// TS 的 \d 只認這十個字，全形數字不算
private let SPEND_DIGITS: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

/// TS 的 Math.round：.5 往正的方向進位（Swift 的 rounded() 是離 0 遠的方向，負數會不一樣）
private func spendRound(_ x: Double) -> Double {
    return (x + 0.5).rounded(.down)
}

/// TS 的 toLocaleString('en-US')：整數加千分位
private func spendGrouped(_ n: Double) -> String {
    if n.isNaN { return "NaN" }
    if !n.isFinite { return n > 0 ? "∞" : "-∞" }
    if abs(n) >= 9.0e15 { return String(n) }
    let neg: Bool = n < 0
    let whole: Int = Int(abs(n))
    let digits: [Character] = Array(String(whole))
    var out: String = ""
    for (i, ch) in digits.enumerated() {
        if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return (neg ? "-" : "") + out
}

/// 重排行程時要留下來的：使用者自己填的機票、花費紀錄、匯率
func ownOf(_ t: Trip) -> (flight: Double, spend: [Spend]?, rate: Double?) {
    return (flight: t.flight, spend: t.spend, rate: t.rate)
}

/// 同一趟整趟重排：照 d 和 st 重新排，ownOf 那三樣、這趟的代號、問了 AI 幾句、順路清單都留著。
/// 重排同一趟一律走這裡，不要直接用 generate() 換掉（那是開新的一趟，句數從 0 算）。
/// visited 是以前去過的地點（visitedOf(d.baskets)），沒給就當第一次來
func replanTrip(
    _ old: Trip, _ d: TripDraft, _ st: Settings, _ shuffle: Bool = false, visited: [String: Int] = [:]
) -> Trip {
    var next: Trip = generate(d, st, shuffle, visited: visited)
    let own: (flight: Double, spend: [Spend]?, rate: Double?) = ownOf(old)
    next.flight = own.flight
    next.spend = own.spend
    next.rate = own.rate
    next.id = old.id
    next.aiUsed = old.aiUsed
    // 這一版照哪些調整排的，記下來：之後才說的不能講成照它排的
    next.planTweaks = d.tweaks ?? []
    // 開一趟時寫的那句留著；照它改過的站被重排掉了，wishChanges 不帶
    next.wish = old.wish
    next.wishOff = old.wishOff
    // 順路清單是使用者自己加的，跟排法無關
    next.pool = old.pool
    // 代購清單也是使用者自己打的，重排不能弄丟
    next.errands = old.errands
    keepPhotos(old, &next)
    return next
}

/// 重排之後，新的這一版裡還有同一個地點的，自己加的照片跟過去。
/// 新的這一版沒排到的地點，照片只留在重排前那一步（可以復原回去）
private func keepPhotos(_ old: Trip, _ next: inout Trip) {
    var byId: [String: [String]] = [:]
    for x in allItems(old) {
        let list: [String] = x.it.photos ?? []
        if !list.isEmpty { byId[x.it.id] = list }
    }
    if byId.isEmpty { return }
    for i in next.slots.indices {
        for j in next.slots[i].items.indices {
            let id: String = next.slots[i].items[j].id
            guard let list = byId[id], (next.slots[i].items[j].photos ?? []).isEmpty else { continue }
            next.slots[i].items[j].photos = list
            byId[id] = nil
        }
    }
}

/// 使用者打的金額 → 韓元整數。打錯或空的是 0
func parseKrw(_ text: String) -> Double {
    // TS：parseInt(text.replace(/\D/g, ''), 10) || 0，再跟上限取小的
    var digits: String = ""
    for ch in text where SPEND_DIGITS.contains(ch) {
        digits.append(ch)
    }
    // 前面的 0 不算位數
    var trimmed: Substring = Substring(digits)
    while trimmed.hasPrefix("0") { trimmed = trimmed.dropFirst() }
    if trimmed.isEmpty { return 0 }
    // 上限是八位數，九位以上一定超過
    if trimmed.count > 8 { return KRW_MAX }
    let n: Double = Double(Int(trimmed) ?? 0)
    return min(KRW_MAX, n)
}

/// 使用者打的匯率 → 數字。空的、0、不合理的都當成沒填
func parseRate(_ text: String) -> Double? {
    // TS：parseFloat(text.replace(/[^\d.]/g, ''))。parseFloat 只吃開頭看得懂的那一段：
    // 數字、最多一個小數點、數字；碰到第二個小數點就停
    var whole: String = ""
    var frac: String = ""
    var seenDot: Bool = false
    for ch in text {
        if SPEND_DIGITS.contains(ch) {
            if seenDot { frac.append(ch) } else { whole.append(ch) }
        } else if ch == "." {
            if seenDot { break }
            seenDot = true
        }
    }
    if whole.isEmpty && frac.isEmpty { return nil }
    let joined: String = (whole.isEmpty ? "0" : whole) + "." + (frac.isEmpty ? "0" : frac)
    guard let n = Double(joined) else { return nil }
    return n > 0 && n <= RATE_MAX ? n : nil
}

func krwText(_ n: Double) -> String {
    return "₩ " + spendGrouped(spendRound(n))
}

/// 換成台幣。沒填匯率就是 nil，不猜
func toTwd(_ krw: Double, _ rate: Double?) -> Double? {
    // TS 的 rate ? … : null：沒填、0、NaN 都算沒有
    guard let r = rate, r != 0, !r.isNaN else { return nil }
    return spendRound((krw / 1000) * r)
}

/// 整趟的合計：花費頁和一站頁都在一份 t.spend 裡，一站頁記的一起算。
/// krw 只加韓元那幾筆；twd 是全部換成台幣（有韓元又沒填匯率是 nil，不猜）
func spendTotal(_ t: Trip) -> (count: Int, krw: Double, twd: Double?) {
    let sum: SpendSum = spendSum(t.spend ?? [], t.rate)
    return (count: sum.count, krw: sum.krw, twd: sum.twd)
}

/// 好幾筆加起來。韓元和台幣分開加，有匯率才合成一個台幣數字
struct SpendSum: Hashable, Sendable {
    var count: Int
    var krw: Double  // 韓元那幾筆加起來
    var ntd: Double  // 台幣那幾筆加起來
    var twd: Double?  // 全部換成台幣。有韓元又沒填匯率是 nil
}

extension Spend {
    /// 這一筆是哪一種錢
    var cur: SpendCur {
        return twd != nil ? SpendCur.twd : SpendCur.krw
    }

    /// 這一筆原本的金額（韓元或台幣）
    var amount: Double {
        return twd ?? krw
    }
}

func spendSum(_ list: [Spend], _ rate: Double?) -> SpendSum {
    var krw: Double = 0
    var ntd: Double = 0
    for x in list {
        switch x.cur {
        case SpendCur.krw: krw += x.krw
        case SpendCur.twd: ntd += x.twd ?? 0
        }
    }
    let twd: Double?
    if krw == 0 {
        // 沒有韓元：一筆都沒有就照舊（有匯率是 0、沒有是 nil），只有台幣就是台幣加起來
        twd = list.isEmpty ? toTwd(0, rate) : ntd
    } else if let conv = toTwd(krw, rate) {
        twd = conv + ntd
    } else {
        twd = nil
    }
    return SpendSum(count: list.count, krw: krw, ntd: ntd, twd: twd)
}

/// 在這一站記的那幾筆，新的在上面
func stopSpends(_ t: Trip, _ stopId: String) -> [Spend] {
    let list: [Spend] = t.spend ?? []
    return list.filter { (x: Spend) -> Bool in x.stopId == stopId }
}

/// 一筆的金額，照它自己的幣別寫：₩ 12,000、NT$ 300
func spendAmountText(_ x: Spend) -> String {
    switch x.cur {
    case SpendCur.krw: return krwText(x.krw)
    case SpendCur.twd: return money(x.twd ?? 0)
    }
}

/// 一筆換成台幣的那一行（「約 NT$ 276」）。台幣那一筆本來就是台幣、沒填匯率，都是 nil
func spendTwdText(_ x: Spend, _ rate: Double?) -> String? {
    if x.cur == SpendCur.twd { return nil }
    guard let t = toTwd(x.krw, rate) else { return nil }
    return "約 \(money(t))"
}

/// 合計的一句，後面不帶句號：
/// 「2 筆，一共 ₩ 20,000，約 NT$ 460（照你填的匯率算）」、「1 筆，一共 NT$ 300」、
/// 「3 筆，₩ 20,000 和 NT$ 300，合起來約 NT$ 760（照你填的匯率算）」。沒填匯率就不合起來
func spendSumText(_ s: SpendSum) -> String {
    let head: String = "\(s.count) 筆"
    if s.krw > 0 && s.ntd > 0 {
        let both: String = "\(head)，\(krwText(s.krw)) 和 \(money(s.ntd))"
        guard let twd = s.twd else { return both }
        return both + "，合起來約 \(money(twd))（照你填的匯率算）"
    }
    if s.ntd > 0 {
        return "\(head)，一共 \(money(s.ntd))"
    }
    let krw: String = "\(head)，一共 \(krwText(s.krw))"
    guard let twd = s.twd, s.krw > 0 else { return krw }
    return krw + "，約 \(money(twd))（照你填的匯率算）"
}

/// 有韓元的那幾筆，但沒填匯率，換不成台幣
func spendNeedsRate(_ s: SpendSum) -> Bool {
    return s.krw > 0 && s.twd == nil
}

/// 這一筆是在哪一站記的：現在這趟裡找得到就用現在的站名，找不到用記的時候的站名。從花費頁記的是 nil
func spendPlaceName(_ t: Trip, _ x: Spend) -> String? {
    guard let id = x.stopId else { return nil }
    if let found = findItem(t, id) { return found.it.n }
    return x.stopName
}

/// 記一筆，新的排最上面。金額是 0 就不記。
/// cur 是台幣的話，金額記在 twd、krw 是 0。stopId、stopName 是在一站頁記的那一站
@discardableResult
func addSpend(
    _ t: inout Trip, _ amount: Double, _ note: String, _ day: Int? = nil,
    cur: SpendCur = SpendCur.krw, stopId: String? = nil, stopName: String? = nil
) -> Spend? {
    // TS 是 if (krw <= 0) return；NaN 在 TS 會記進去，這裡照樣
    if amount <= 0 { return nil }
    let trimmed: String = note.trimmingCharacters(in: .whitespacesAndNewlines)
    let isTwd: Bool = cur == SpendCur.twd
    let x: Spend = Spend(
        id: newId("s"), krw: isTwd ? 0 : amount, note: trimmed.isEmpty ? nil : trimmed, day: day,
        stopId: stopId, stopName: stopName, twd: isTwd ? amount : nil)
    let old: [Spend] = t.spend ?? []
    t.spend = [x] + old
    return x
}

@discardableResult
func removeSpend(_ t: inout Trip, _ id: String) -> Spend? {
    guard let list = t.spend else { return nil }
    let found: Spend? = list.first { (y: Spend) -> Bool in y.id == id }
    guard let x = found else { return nil }
    t.spend = list.filter { (y: Spend) -> Bool in y.id != id }
    return x
}
