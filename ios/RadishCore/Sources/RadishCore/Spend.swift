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
/// 重排同一趟一律走這裡，不要直接用 generate() 換掉（那是開新的一趟，句數從 0 算）
func replanTrip(_ old: Trip, _ d: TripDraft, _ st: Settings, _ shuffle: Bool = false) -> Trip {
    var next: Trip = generate(d, st, shuffle)
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
    return next
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

func spendTotal(_ t: Trip) -> (count: Int, krw: Double, twd: Double?) {
    let list: [Spend] = t.spend ?? []
    var krw: Double = 0
    for x in list { krw += x.krw }
    return (count: list.count, krw: krw, twd: toTwd(krw, t.rate))
}

/// 記一筆，新的排最上面。金額是 0 就不記
@discardableResult
func addSpend(_ t: inout Trip, _ krw: Double, _ note: String, _ day: Int? = nil) -> Spend? {
    // TS 是 if (krw <= 0) return；NaN 在 TS 會記進去，這裡照樣
    if krw <= 0 { return nil }
    let trimmed: String = note.trimmingCharacters(in: .whitespacesAndNewlines)
    let x: Spend = Spend(id: newId("s"), krw: krw, note: trimmed.isEmpty ? nil : trimmed, day: day)
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
