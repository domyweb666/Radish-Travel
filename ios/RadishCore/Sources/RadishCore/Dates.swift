// 日期都用 'YYYY-MM-DD' 字串，算的時候一律用 UTC，避免時區把日期推前推後一天。
// 照 mobile/src/domain/dates.ts 搬。這裡不靠 Calendar，直接用整數算「從 1970-01-01 起第幾天」。
import Foundation

private let WEEK: [String] = ["日", "一", "二", "三", "四", "五", "六"]

/// 整數除法往下取（Swift 的 / 是往 0 取，負數會不一樣）
private func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q: Int = a / b
    let r: Int = a % b
    if r != 0 && ((r < 0) != (b < 0)) { return q - 1 }
    return q
}

/// 西元年月日 → 從 1970-01-01 起第幾天。月份、日期超出範圍會自己進位（跟 Date.UTC 一樣）
private func daysFromCivil(_ y0: Int, _ m0: Int, _ d: Int) -> Int {
    let mIndex: Int = m0 - 1
    let yShift: Int = floorDiv(mIndex, 12)
    let m: Int = mIndex - yShift * 12 + 1
    var y: Int = y0 + yShift
    if m <= 2 { y -= 1 }
    let era: Int = floorDiv(y, 400)
    let yoe: Int = y - era * 400
    let mp: Int = m > 2 ? m - 3 : m + 9
    let doy: Int = (153 * mp + 2) / 5 + d - 1
    let doe: Int = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

/// 從 1970-01-01 起第幾天 → 西元年月日
private func civilFromDays(_ z0: Int) -> (y: Int, m: Int, d: Int) {
    let z: Int = z0 + 719468
    let era: Int = floorDiv(z, 146097)
    let doe: Int = z - era * 146097
    let yoe: Int = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let doy: Int = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp: Int = (5 * doy + 2) / 153
    let d: Int = doy - (153 * mp + 2) / 5 + 1
    let m: Int = mp < 10 ? mp + 3 : mp - 9
    let y: Int = yoe + era * 400 + (m <= 2 ? 1 : 0)
    return (y: y, m: m, d: d)
}

/// 'YYYY-MM-DD' 拆成三個數字。拆不出來的那一格當 0
private func isoParts(_ iso: String) -> (y: Int, m: Int, d: Int) {
    let bits: [String] = iso.components(separatedBy: "-")
    let y: Int = bits.count > 0 ? (Int(bits[0]) ?? 0) : 0
    let m: Int = bits.count > 1 ? (Int(bits[1]) ?? 0) : 0
    let d: Int = bits.count > 2 ? (Int(bits[2]) ?? 0) : 0
    return (y: y, m: m, d: d)
}

private func pad(_ n: Int, _ width: Int) -> String {
    var s: String = String(n)
    while s.count < width { s = "0" + s }
    return s
}

/// TS 的 toUTC，單位改成天
private func toDays(_ iso: String) -> Int {
    let p: (y: Int, m: Int, d: Int) = isoParts(iso)
    return daysFromCivil(p.y, p.m, p.d)
}

/// TS 的 fromUTC，單位改成天
private func fromDays(_ days: Int) -> String {
    let c: (y: Int, m: Int, d: Int) = civilFromDays(days)
    return "\(pad(c.y, 4))-\(pad(c.m, 2))-\(pad(c.d, 2))"
}

/// 星期幾：0 是星期日。1970-01-01 是星期四
private func utcDay(_ days: Int) -> Int {
    return (((days + 4) % 7) + 7) % 7
}

/// 裝置當地的今天
func todayISO(_ now: Date = Date()) -> String {
    let cal: Calendar = Calendar.current
    let c: DateComponents = cal.dateComponents([.year, .month, .day], from: now)
    let y: Int = c.year ?? 1970
    let m: Int = c.month ?? 1
    let d: Int = c.day ?? 1
    return "\(pad(y, 4))-\(pad(m, 2))-\(pad(d, 2))"
}

func addDays(_ iso: String, _ n: Int) -> String {
    return fromDays(toDays(iso) + n)
}

func diffDays(_ a: String, _ b: String) -> Int {
    return toDays(b) - toDays(a)
}

func weekday(_ iso: String) -> String {
    return WEEK[utcDay(toDays(iso))]
}

/// 11/20（五）
func fmtDay(_ iso: String) -> String {
    let p: (y: Int, m: Int, d: Int) = isoParts(iso)
    return "\(p.m)/\(p.d)（\(weekday(iso))）"
}

/// 這個月的格子：前面補空格，每格是 ISO 日期或 nil
func monthGrid(_ year: Int, _ month: Int) -> [String?] {
    let first: Int = daysFromCivil(year, month, 1)
    let lead: Int = utcDay(first)
    let days: Int = daysFromCivil(year, month + 1, 1) - first
    var cells: [String?] = Array(repeating: nil, count: lead)
    if days >= 1 {
        for d in 1...days {
            cells.append(fromDays(first + d - 1))
        }
    }
    while cells.count % 7 != 0 { cells.append(nil) }
    return cells
}

enum Phase: Equatable {
    case plan(daysToGo: Int)
    case trip(day: Int)
    case done
}

/// 這趟現在在哪個階段：還沒出發、旅途中第幾天、已經回來
func phaseOf(_ start: String, _ days: Int, _ today: String, _ debugDay: Int?) -> Phase {
    if let dd = debugDay {
        return dd > days ? Phase.done : Phase.trip(day: max(1, dd))
    }
    let d: Int = diffDays(start, today)
    if d < 0 { return Phase.plan(daysToGo: -d) }
    if d >= days { return Phase.done }
    return Phase.trip(day: d + 1)
}
